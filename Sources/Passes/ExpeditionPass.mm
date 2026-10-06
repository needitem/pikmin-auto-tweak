#import "Passes.h"
#import "Backoff.h"
#import "Expeditions.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Layout.h"
#import "Log.h"
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

// Who may be sent. The rules the game itself applies (PikminInventoryTools.
// ReservingPikminForTroop): troop members ARE sendable; the game only holds back
// enough of them to keep the troop at its minimum size:
//   needToReserve = count(eligible in troop) - troopCount + minTroop
// Busy Pikmin (on a task) are the only hard exclusion; favourites stay home.
//
// On top of that, the roster strategy (Model/TroopPlan.mm) decides WHO is
// expendable. A Pikmin away on an expedition is neither walking in the troop
// nor available for a mushroom, so:
//  * whoever the troop plan wants in the troop right now is never sent;
//  * of the rest, ordinary Pikmin go first, strongest first (they carry more,
//    so the smallest party that can start is smaller);
//  * each colour's elite are the mushroom force and go last, weakest first,
//    only if the others cannot make the party.
// (The old rule sent only 4-heart-and-up Pikmin, i.e. exactly the mushroom
// force.)
static NSArray<PKPikmin *> *candidates(NSArray<PKPikmin *> *roster) {
    PKTroopCounts troop = pkTroopCounts();
    NSSet<NSString *> *members = pkTroopMembers(roster);
    int minTroop = pkMinTroop();
    NSSet<NSString *> *elite = pkTroopElite(roster);

    // Who the troop pass would put in the troop (same inputs, same answer).
    NSMutableArray<PKPikmin *> *movable = [NSMutableArray array];
    int busyInTroop = 0;
    for (PKPikmin *p in roster) {
        if (p.status == PK_STATUS_TASK) { if ([members containsObject:p.pid]) busyInTroop++; continue; }
        [movable addObject:p];
    }
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];
    for (PKPikmin *p in pkTroopPlan(roster, movable, (NSUInteger)MAX(troop.max - busyInTroop, 0), NULL)) [wanted addObject:p.pid];

    NSMutableArray<PKPikmin *> *plain = [NSMutableArray array], *spare = [NSMutableArray array], *held4troop = [NSMutableArray array];
    int nBusy = 0, nStarred = 0;
    for (PKPikmin *p in roster) {
        if (p.status == PK_STATUS_TASK || p.status == 0) { nBusy++; continue; }
        if (p.starred) { nStarred++; continue; }
        if ([wanted containsObject:p.pid]) [held4troop addObject:p];
        else if ([elite containsObject:p.pid]) [spare addObject:p];
        else [plain addObject:p];
    }
    [plain sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) {
        if (a.hearts != b.hearts) return a.hearts > b.hearts ? NSOrderedAscending : NSOrderedDescending;
        return [a.pid compare:b.pid];
    }];
    [spare sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) {
        if (a.hearts != b.hearts) return a.hearts < b.hearts ? NSOrderedAscending : NSOrderedDescending;
        return [a.pid compare:b.pid];
    }];
    NSMutableArray<PKPikmin *> *pool = [NSMutableArray arrayWithArray:plain];
    [pool addObjectsFromArray:spare];
    BOOL onlyTroop = NO;
    if (!pool.count) { [pool addObjectsFromArray:held4troop]; onlyTroop = YES; }   // never stall completely

    int poolInTroop = 0;
    for (PKPikmin *p in pool) if ([members containsObject:p.pid]) poolInTroop++;
    int need = poolInTroop - troop.total + minTroop;
    NSMutableArray<PKPikmin *> *out = [NSMutableArray array];
    int held = 0;
    for (PKPikmin *p in pool) {
        if (need > 0 && held < need && [members containsObject:p.pid]) { held++; continue; }
        [out addObject:p];
    }

    if (!out.count)
        PKLOGC(@"exp.nopool", ([NSString stringWithFormat:@"[탐험] 후보0 — 전체 %lu, 작업중제외 %d, 즐겨찾기제외 %d, 부대배정제외 %lu, 부대유보 %d/%d (부대 %d, 최소 %d)",
              (unsigned long)roster.count, nBusy, nStarred, (unsigned long)held4troop.count, held, need, troop.total, minTroop]));
    else
        PKLOGC(@"exp.pool", ([NSString stringWithFormat:@"[탐험] 후보 %lu마리 (일반 %lu · 정예 %lu · 부대배정 제외 %lu%@, 부대유보 %d, 부대 %d, 최소 %d)",
                              (unsigned long)out.count, (unsigned long)plain.count, (unsigned long)spare.count, (unsigned long)held4troop.count,
                              onlyTroop ? @" → 배정자만 남아 포함" : @"", held, troop.total, minTroop]));
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

NSString *pkExpeditionPass(void) {
    if (!pkExpStore()) {
        PKLOGC(@"exp.nostore", @"[탐험] 스토어 미포착 — 지도에 탐험이 뜨면 잡힘");
        return @"탐험 목록 대기 (지도에 탐험이 보이면 잡힘)";
    }
    NSArray<NSValue *> *exps = pkExpeditionItems();
    if (!exps.count) return @"탐험 없음";

    // Census, so "nothing sent" can be told from "nothing startable is in the store".
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

    NSArray<PKPikmin *> *roster = pkRoster();
    {   // Best-value expeditions first (stable inside a tier).
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
        exps = sorted;
    }
    NSArray<PKPikmin *> *cands = roster.count ? candidates(roster) : nil;
    if (!cands.count) return @"보낼 피크민 없음";

    // Several send-offs per pass; Pikmin already committed this pass are held
    // back so two expeditions never claim the same ones.
    NSMutableSet<NSString *> *committed = [NSMutableSet set];
    int launched = 0, lastParty = 0, seen = 0;
    for (NSValue *ev in exps) {
        void *d = ev.pointerValue;
        void *proto = pkExpeditionTaskProto(d);
        if (!proto || pkGetInt(proto, &F_Task_case) != PK_TASK_EXPEDITION) continue;
        // The game's own state machine, not our reading of startTimeMs_.
        if (pkExpeditionState(d) != PK_EXP_AVAILABLE) continue;
        seen++;
        // startTimeMs_ only flips once the server has answered, so a second pass
        // inside that round trip would send it again. Still Available after a
        // send means the server did not take it.
        NSString *tkey = pkExpeditionKey(d);
        if (tkey && (![backoff() ready:tkey] || ![refused() ready:tkey])) continue;

        int maxN = pkUnboxInt(pkCall0(d, "get_MaxPikminsAllowed"));
        if (maxN <= 0) continue;
        void *mAllows = pkMethodOf(d, "Allows", 1);

        // Decide the party in OUR memory first, then touch the game's task as
        // little as possible. The task object is live game state (a panel may be
        // showing it), and the old loop rewrote its party and recomputed its
        // cached stats once per candidate — dozens of writes per task, undone
        // again when the party was too weak. Now:
        //   1) the eligible candidates are collected with read-only calls;
        //   2) one write tries the largest party the task allows — if the game
        //      says even that cannot start, nothing smaller can, and the task is
        //      put back with a single restore;
        //   3) otherwise the smallest party that works is found by bisection
        //      (adding Pikmin never lowers carrying power), a handful of writes.
        NSArray<NSString *> *original = pkExpeditionParty(d);     // whatever the game (or the player) had there
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
        if (!elig.count) continue;                                        // nothing to write
        NSMutableArray<NSString *> *eligIds = [NSMutableArray arrayWithCapacity:elig.count];
        for (PKPikmin *c in elig) [eligIds addObject:c.pid];
        // CanTryStart == !Started && CarryingPower >= Weight, recomputed by the game.
        BOOL (^canStartWith)(NSUInteger) = ^BOOL(NSUInteger n) {
            pkExpeditionSetParty(d, [eligIds subarrayWithRange:NSMakeRange(0, n)]);
            return pkUnboxBool(pkCall0(d, "get_CanTryStart"));
        };
        BOOL ready = canStartWith(elig.count);
        NSUInteger want = elig.count;
        if (ready) {
            NSUInteger lo = 1, hi = elig.count;                           // smallest n in [lo, hi] that starts
            while (lo < hi) {
                NSUInteger mid = (lo + hi) / 2;
                if (canStartWith(mid)) hi = mid; else lo = mid + 1;
            }
            want = lo;
            if (want != elig.count) ready = canStartWith(want);           // leave the task holding exactly this party
        }
        NSArray<NSString *> *picked = [eligIds subarrayWithRange:NSMakeRange(0, want)];
        if (!ready) {
            pkExpeditionSetParty(d, original);
            if (tkey) [refused() recordSend:tkey];
            PKLOGC(@"exp.weak", ([NSString stringWithFormat:@"[탐험] 힘 부족 — 후보 %lu, 가능 %lu, 최대 %d",
                                  (unsigned long)cands.count, (unsigned long)elig.count, maxN]));
            continue;
        }
        // With a party assigned, the game's own veto is meaningful: out of range,
        // inventory full, feature locked, still not strong enough, …
        void *why = pkCall0(d, "get_StartDisabledReason");
        if (why) {
            pkExpeditionSetParty(d, original);
            if (tkey) [refused() recordSend:tkey];
            PKLOGC(@"exp.skip", ([NSString stringWithFormat:@"[탐험] 건너뜀 — %@", pkStr(why) ?: @"불가"]));
            continue;
        }
        BOOL started = NO;
        pkInvokeEx(pkMethodOf(d, "StartExpeditionAsync", 0), d, NULL, &started);
        if (!started) { pkExpeditionSetParty(d, original); return @"StartExpeditionAsync 호출 실패"; }
        if (tkey) [backoff() recordSend:tkey];
        PALOG(@"[탐험] 출발 task=%@ 피크민 %lu마리 (최대 %d, %d번째 시도%@)", tkey ?: @"?", (unsigned long)picked.count,
              maxN, tkey ? [backoff() tries:tkey] : 1,
              tkey && [backoff() tries:tkey] > 1 ? [NSString stringWithFormat:@", 다음 대기 %.0f초", [backoff() waitFor:tkey]] : @"");
        [committed addObjectsFromArray:picked];
        pkTroopInvalidate();                 // the roster just changed
        pkRosterInvalidate();
        lastParty = (int)picked.count;
        if (++launched >= kExpPerPass) break;
    }
    if (launched)
        return [NSString stringWithFormat:@"🚀 탐험 %d건 출발 (마지막 %d마리, 후보 %lu)", launched, lastParty, (unsigned long)cands.count];
    return seen ? [NSString stringWithFormat:@"보낼 수 있는 탐험 없음 (미출발 %d건)", seen] : @"대기 중인 탐험 없음";
}
