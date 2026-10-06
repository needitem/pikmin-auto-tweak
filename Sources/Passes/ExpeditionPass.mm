#import "Passes.h"
#import "Reflection.h"
#import "Backoff.h"
#import "Bisect.h"
#import "ExpeditionPool.h"
#import "Expeditions.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Layout.h"
#import "Log.h"
#import "SeedReader.h"
#import "SeedValue.h"
#import "Roster.h"
#import "Troop.h"
#import "TroopPlan.h"

// Sends Pikmin on expeditions — the fruit/seedling/gift/postcard tasks, not
// mushrooms. Every decision is the game's own code, so the request that goes
// out is the one the Go button would have sent:
//   ExpeditionItemData.Allows(pikmin)       honours the task's restriction
//   .get_MaxPikminsAllowed()                stats.Weight * 2 (1 if restricted)
//   .get_CanTryStart()                      !Started && CarryingPower >= Weight
//   .get_StartDisabledReason()              non-null means the game would refuse
//   .StartExpeditionAsync()                 builds and sends the start request
// Assigning Pikmin is what the panel's auto-pick does: write the ids into the
// task proto and invalidate the cached stats. One Pikmin at a time, asking the
// game after each whether the party is strong enough — so the party is the
// smallest one the game accepts.

// One start per pass (the pass runs every 8 s). Four at once were sent in a
// single tick, and every freeze of the game we could attribute (10/2, 10/6, and
// the one on 10/6 09:51, a second after four starts) came within seconds of an
// expedition start: the game builds the party, its map objects and its UI for
// each one on the main thread.
static const int kExpPerPass = 1;

// A task the server keeps refusing must not be retried forever: the wait
// triples with each attempt that left it Available, up to an hour.
static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:30 factor:3 max:3600]; });
    return b;
}

// A task the game would refuse to start ("힘 부족", or a StartDisabledReason)
// cost a full candidate walk every pass — each candidate means game calls that
// recompute the task's cached stats — for the same answer. It waits, shorter
// than the backoff above because a refusal here is the game's own verdict and
// can lift as soon as Pikmin come home or grow.
static PKBackoff *refused(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:20 factor:2 max:120]; });
    return b;
}

// Who may be sent: the policy is Model/ExpeditionPool; this gathers what the game
// says (the troop, its minimum size) and the troop plan's current answer.
static NSArray<PKPikmin *> *candidates(NSArray<PKPikmin *> *roster) {
    PKTroopCounts troop = pkTroopCounts();
    NSSet<NSString *> *members = pkTroopMembers(roster);
    int minTroop = pkMinTroop();

    NSMutableSet<NSString *> *wanted = [NSMutableSet set];          // who the troop pass would put in the troop (same inputs, same answer)
    for (PKPikmin *p in pkTroopWanted(roster, members, troop.max, NULL, NULL, NULL)) [wanted addObject:p.pid];

    PKPoolStats st;
    NSArray<PKPikmin *> *out = pkExpeditionPool(roster, members, troop.total, minTroop, wanted, pkTroopElite(roster), &st);
    if (!out.count)
        PKLOGC(@"exp.nopool", ([NSString stringWithFormat:@"[탐험] 후보0 — 전체 %lu, 작업중제외 %d, 즐겨찾기제외 %d, 부대배정제외 %lu, 부대유보 %d/%d (부대 %d, 최소 %d)",
              (unsigned long)roster.count, st.busy, st.starred, (unsigned long)st.heldForTroop, st.reserved, st.need, troop.total, minTroop]));
    else
        PKLOGC(@"exp.pool", ([NSString stringWithFormat:@"[탐험] 후보 %lu마리 (일반 %lu · 정예 %lu · 부대배정 제외 %lu%@, 부대유보 %d, 부대 %d, 최소 %d)",
                              (unsigned long)out.count, (unsigned long)st.plain, (unsigned long)st.spare, (unsigned long)st.heldForTroop,
                              st.onlyTroop ? @" → 배정자만 남아 포함" : @"", st.reserved, troop.total, minTroop]));
    return out;
}

// What an expedition is worth, lower = start first (the pass launches only a
// few per run and they share the same candidates):
//   0 special seedling, 1 large seedling,
//   2 anything else (gifts, fruit, big flowers, and ordinary seedlings of a
//     colour the roster still wants),
//   3 ordinary seedlings of a colour it already has enough of.
// Nothing is skipped; this only decides the order.
static int expeditionTier(void *d, NSDictionary<NSNumber *, NSNumber *> *need) {
    static int seedTarget = -2;
    if (seedTarget == -2) {
        seedTarget = -1;
        NSString *ns = nil;
        NSDictionary<NSNumber *, NSString *> *m = pkEnumMap(pkFindClassByName("TargetCase", &ns));
        for (NSNumber *k in m) if ([m[k] isEqualToString:@"Seed"]) seedTarget = k.intValue;
    }
    if (seedTarget < 0 || pkUnboxInt(pkCall0(d, "get_Target")) != seedTarget) return 2;
    void *seed = pkCall0(d, "get_PikminSeed");
    if (!seed) return 2;
    PKSeedTraits t = pkSeedTraits(seed);
    if (t.tier != PKSeedTierPlain) return t.tier;
    return need[@(t.color)].doubleValue > 0 ? 2 : 3;
}

// ---------- the pass, one step at a time ----------

// "nothing sent" can be told from "nothing startable is in the store" by the
// census. Also forgets backoff entries of tasks that no longer exist.
static void census(NSArray<NSValue *> *exps) {
    int nExp = 0, nIdle = 0;
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    for (NSValue *ev in exps) {
        void *d = ev.pointerValue;
        void *proto = pkExpeditionTaskProto(d);
        if (!proto || pkGetInt(proto, &F_Task_case) != PK_TASK_EXPEDITION) continue;
        nExp++;
        if (pkGetI64(proto, &F_Task_start) == 0) nIdle++;
        NSString *k = pkExpeditionKey(d);
        if (k) [alive addObject:k];
    }
    [backoff() pruneKeeping:alive];
    [refused() pruneKeeping:alive];
    PKLOGC(@"exp.census", ([NSString stringWithFormat:@"[탐험] 스토어 %lu건 / 탐험 %d건 / 미출발 %d건",
                            (unsigned long)exps.count, nExp, nIdle]));
}

// Best-value expeditions first (stable inside a tier).
static NSArray<NSValue *> *orderedByValue(NSArray<NSValue *> *exps, NSArray<PKPikmin *> *roster) {
    NSDictionary<NSNumber *, NSNumber *> *need = pkColorNeed(roster);
    NSMutableArray<NSNumber *> *tiers = [NSMutableArray array];
    for (NSValue *ev in exps) [tiers addObject:@(expeditionTier(ev.pointerValue, need))];
    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    for (NSUInteger i = 0; i < exps.count; i++) [order addObject:@(i)];
    [order sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        int ta = tiers[a.unsignedIntegerValue].intValue, tb = tiers[b.unsignedIntegerValue].intValue;
        if (ta != tb) return ta < tb ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
    NSMutableArray<NSValue *> *sorted = [NSMutableArray array];
    for (NSNumber *i in order) [sorted addObject:exps[i.unsignedIntegerValue]];
    return sorted;
}

// The candidates this task accepts, strongest-first as given, at most `maxN`;
// read-only calls. Pikmin already committed to another task this pass are held back
// so two expeditions never claim the same ones.
static NSArray<PKPikmin *> *eligibleFor(void *d, NSArray<PKPikmin *> *cands, NSSet<NSString *> *committed, int maxN) {
    void *mAllows = pkMethodOf(d, "Allows", 1);
    NSMutableArray<PKPikmin *> *elig = [NSMutableArray array];
    for (PKPikmin *c in cands) {
        if ((int)elig.count >= maxN) break;
        if ([committed containsObject:c.pid]) continue;
        if (mAllows) {
            void *a[1] = { c.item };
            if (!pkUnboxBool(pkInvoke(mAllows, d, a))) continue;      // restricted task
        }
        [elig addObject:c];
    }
    return elig;
}

// Decide the party in OUR memory first, then touch the game's task as little as
// possible. The task object is live game state (a panel may be showing it), and
// the old loop rewrote its party and recomputed its cached stats once per
// candidate — dozens of writes per task, undone again when the party was too
// weak. Now:
//   1) one write tries the largest party the task allows — if the game says even
//      that cannot start, nothing smaller can;
//   2) otherwise the smallest party that works is found by bisection (adding
//      Pikmin never lowers carrying power), a handful of writes.
// Returns the party ids and leaves the task holding exactly that party, or returns
// nil (task still holding the largest try — the caller restores it).
static NSArray<NSString *> *chooseParty(void *d, NSArray<NSString *> *eligibleIds) {
    // CanTryStart == !Started && CarryingPower >= Weight, recomputed by the game.
    BOOL (^canStartWith)(NSUInteger) = ^BOOL(NSUInteger n) {
        pkExpeditionSetParty(d, [eligibleIds subarrayWithRange:NSMakeRange(0, n)]);
        return pkUnboxBool(pkCall0(d, "get_CanTryStart"));
    };
    if (!canStartWith(eligibleIds.count)) return nil;
    NSUInteger want = pkSmallestPassing(eligibleIds.count, canStartWith);
    if (want != eligibleIds.count && !canStartWith(want)) return nil;     // leave the task holding exactly this party
    return [eligibleIds subarrayWithRange:NSMakeRange(0, want)];
}

typedef enum { kNotLaunched, kLaunched, kStartCallFailed } PKLaunch;

// One expedition: the checks that need no write, the party, the game's own veto,
// then the start. Records what it did in the backoffs and the log.
static PKLaunch tryLaunch(void *d, NSArray<PKPikmin *> *cands, NSMutableSet<NSString *> *committed, int *partySize) {
    // startTimeMs_ only flips once the server has answered, so a second pass
    // inside that round trip would send it again. Still Available after a
    // send means the server did not take it.
    NSString *tkey = pkExpeditionKey(d);
    if (tkey && (![backoff() ready:tkey] || ![refused() ready:tkey])) return kNotLaunched;

    int maxN = pkUnboxInt(pkCall0(d, "get_MaxPikminsAllowed"));
    if (maxN <= 0) return kNotLaunched;

    NSArray<NSString *> *original = pkExpeditionParty(d);                 // whatever the game (or the player) had there
    NSArray<PKPikmin *> *elig = eligibleFor(d, cands, committed, maxN);
    if (!elig.count) return kNotLaunched;                                 // nothing to write
    NSMutableArray<NSString *> *eligIds = [NSMutableArray arrayWithCapacity:elig.count];
    for (PKPikmin *c in elig) [eligIds addObject:c.pid];

    NSArray<NSString *> *picked = chooseParty(d, eligIds);
    if (!picked) {
        pkExpeditionSetParty(d, original);
        if (tkey) [refused() recordSend:tkey];
        PKLOGC(@"exp.weak", ([NSString stringWithFormat:@"[탐험] 힘 부족 — 후보 %lu, 가능 %lu, 최대 %d",
                              (unsigned long)cands.count, (unsigned long)elig.count, maxN]));
        return kNotLaunched;
    }
    // With a party assigned, the game's own veto is meaningful: out of range,
    // inventory full, feature locked, still not strong enough, …
    void *why = pkCall0(d, "get_StartDisabledReason");
    if (why) {
        pkExpeditionSetParty(d, original);
        if (tkey) [refused() recordSend:tkey];
        PKLOGC(@"exp.skip", ([NSString stringWithFormat:@"[탐험] 건너뜀 — %@", pkStr(why) ?: @"불가"]));
        return kNotLaunched;
    }
    BOOL started = NO;
    pkInvokeEx(pkMethodOf(d, "StartExpeditionAsync", 0), d, NULL, &started);
    if (!started) { pkExpeditionSetParty(d, original); return kStartCallFailed; }
    if (tkey) [backoff() recordSend:tkey];
    PALOG(@"[탐험] 출발 task=%@ 피크민 %lu마리 (최대 %d, %d번째 시도%@)", tkey ?: @"?", (unsigned long)picked.count,
          maxN, tkey ? [backoff() tries:tkey] : 1,
          tkey && [backoff() tries:tkey] > 1 ? [NSString stringWithFormat:@", 다음 대기 %.0f초", [backoff() waitFor:tkey]] : @"");
    [committed addObjectsFromArray:picked];
    pkTroopInvalidate();                 // the roster just changed
    pkRosterInvalidate();
    *partySize = (int)picked.count;
    return kLaunched;
}

NSString *pkExpeditionPass(void) {
    if (!pkExpStore()) {
        PKLOGC(@"exp.nostore", @"[탐험] 스토어 미포착 — 지도에 탐험이 뜨면 잡힘");
        return @"탐험 목록 대기 (지도에 탐험이 보이면 잡힘)";
    }
    NSArray<NSValue *> *exps = pkExpeditionItems();
    if (!exps.count) return @"탐험 없음";
    census(exps);

    NSArray<PKPikmin *> *roster = pkRoster();
    exps = orderedByValue(exps, roster);
    NSArray<PKPikmin *> *cands = roster.count ? candidates(roster) : nil;
    if (!cands.count) return @"보낼 피크민 없음";

    NSMutableSet<NSString *> *committed = [NSMutableSet set];
    int launched = 0, lastParty = 0, seen = 0;
    for (NSValue *ev in exps) {
        void *d = ev.pointerValue;
        void *proto = pkExpeditionTaskProto(d);
        if (!proto || pkGetInt(proto, &F_Task_case) != PK_TASK_EXPEDITION) continue;
        // The game's own state machine, not our reading of startTimeMs_.
        if (pkExpeditionState(d) != PK_EXP_AVAILABLE) continue;
        seen++;
        int party = 0;
        PKLaunch r = tryLaunch(d, cands, committed, &party);
        if (r == kStartCallFailed) return @"StartExpeditionAsync 호출 실패";
        if (r != kLaunched) continue;
        lastParty = party;
        if (++launched >= kExpPerPass) break;
    }
    if (launched)
        return [NSString stringWithFormat:@"🚀 탐험 %d건 출발 (마지막 %d마리, 후보 %lu)", launched, lastParty, (unsigned long)cands.count];
    return seen ? [NSString stringWithFormat:@"보낼 수 있는 탐험 없음 (미출발 %d건)", seen] : @"대기 중인 탐험 없음";
}
