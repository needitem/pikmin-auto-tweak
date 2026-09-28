#import "Passes.h"
#import "Backoff.h"
#import "Expeditions.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Layout.h"
#import "Log.h"
#import "Roster.h"
#import "Troop.h"

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

static const int kExpPerPass = 4;

// A task the server keeps refusing must not be retried forever: the wait
// triples with each attempt that left it Available, up to an hour.
static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:30 factor:3 max:3600]; });
    return b;
}

// Candidates, decided the way the game decides. PikminInventoryTools.
// ReservingPikminForTroop: troop members ARE sendable; the game only holds back
// enough of them to keep the troop at its minimum size:
//   needToReserve = count(eligible in troop) - troopCount + minTroop
// Busy Pikmin (on a task) are the only hard exclusion; favourites stay home.
static NSArray<PKPikmin *> *candidates(NSArray<PKPikmin *> *roster) {
    PKTroopCounts troop = pkTroopCounts();
    NSSet<NSString *> *members = pkTroopMembers(roster);
    int minTroop = pkMinTroop();

    NSMutableArray<PKPikmin *> *pool = [NSMutableArray array];
    int nBusy = 0, nStarred = 0, poolInTroop = 0;
    for (PKPikmin *p in roster) {
        if (p.status == PK_STATUS_TASK || p.status == 0) { nBusy++; continue; }
        if (p.starred) { nStarred++; continue; }
        [pool addObject:p];
        if ([members containsObject:p.pid]) poolInTroop++;
    }
    int need = poolInTroop - troop.total + minTroop;
    NSMutableArray<PKPikmin *> *out = [NSMutableArray array], *grown = [NSMutableArray array];
    int held = 0;
    for (PKPikmin *p in pool) {
        if (need > 0 && held < need && [members containsObject:p.pid]) { held++; continue; }
        [out addObject:p];
        if (p.hearts >= PK_HEARTS_TARGET) [grown addObject:p];
    }
    // Under 4 hearts is still being raised in the troop: send only the grown
    // ones (no troop/expedition contention). Use everyone only when nobody is
    // grown, so expeditions never stall completely.
    if (grown.count) out = grown;

    if (!out.count)
        PALOG(@"[탐험] 후보0 — 전체 %lu, 작업중제외 %d, 즐겨찾기제외 %d, 부대유보 %d/%d (부대 %d, 최소 %d)",
              (unsigned long)roster.count, nBusy, nStarred, held, need, troop.total, minTroop);
    else
        PKLOGC(@"exp.pool", ([NSString stringWithFormat:@"[탐험] 후보 %lu마리 (부대원 포함 %d, 부대유보 %d, 부대 %d, 최소 %d)",
                              (unsigned long)out.count, poolInTroop, held, troop.total, minTroop]));
    return out;
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
    PKLOGC(@"exp.census", ([NSString stringWithFormat:@"[탐험] 스토어 %lu건 / 탐험 %d건 / 미출발 %d건",
                            (unsigned long)exps.count, nExp, nIdle]));

    NSArray<PKPikmin *> *roster = pkRoster();
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
        if (tkey && ![backoff() ready:tkey]) continue;

        int maxN = pkUnboxInt(pkCall0(d, "get_MaxPikminsAllowed"));
        if (maxN <= 0) continue;
        void *mAllows = pkMethodOf(d, "Allows", 1);

        NSArray<NSString *> *original = pkExpeditionParty(d);     // whatever the game (or the player) had there
        NSMutableArray<NSString *> *picked = [NSMutableArray array];
        BOOL ready = NO;
        for (PKPikmin *c in cands) {
            if ((int)picked.count >= maxN) break;
            if ([committed containsObject:c.pid]) continue;
            if (mAllows) {
                void *a[1] = { c.item };
                if (!pkUnboxBool(pkInvoke(mAllows, d, a))) continue;      // restricted task
            }
            [picked addObject:c.pid];
            if (picked.count == 1) pkExpeditionSetParty(d, picked); else pkExpeditionAddToParty(d, c.pid);
            // CanTryStart == !Started && CarryingPower >= Weight, recomputed by the game.
            if (pkUnboxBool(pkCall0(d, "get_CanTryStart"))) { ready = YES; break; }
        }
        if (!ready) {
            pkExpeditionSetParty(d, original);
            PKLOGC(@"exp.weak", ([NSString stringWithFormat:@"[탐험] 힘 부족 — 후보 %lu, 뽑음 %lu, 최대 %d",
                                  (unsigned long)cands.count, (unsigned long)picked.count, maxN]));
            continue;
        }
        // With a party assigned, the game's own veto is meaningful: out of range,
        // inventory full, feature locked, still not strong enough, …
        void *why = pkCall0(d, "get_StartDisabledReason");
        if (why) {
            pkExpeditionSetParty(d, original);
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
