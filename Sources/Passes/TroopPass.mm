#import "Passes.h"
#import "Backoff.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Runtime.h"
#import "Log.h"
#import "Roster.h"
#import "RpcClient.h"
#import "Troop.h"
#import "TroopPlan.h"

// Keep the walking troop on the Pikmin worth raising. The troop is the subset
// that walks with the player, gains friendship, is fed and fights; its cap is
// PikminUtils.GetPikminInTroopCountMax (level-based).
//
// WHICH Pikmin is decided by Model/TroopPlan.mm (decor under 4 hearts first,
// then each colour's elite toward 7; read its header for the rules). This pass only
// applies the plan: the ideal set is recomputed every pass and SWAPPED in —
// members outside it move out, missing ones move in. The arrange RPC is async
// and the in-troop read lags a pass or two, so a Pikmin is not moved again
// within the cooldown.
static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:90 factor:1 max:90]; });
    return b;
}

NSString *pkTroopPass(void) {
    if (!pkRpc() || !pkInv() || !pkRuntimeReady()) return @"서버 대기";
    PKTroopCounts counts = pkTroopCounts();
    if (counts.max <= 0) return @"부대 최대치 0";
    NSArray<PKPikmin *> *roster = pkRoster();
    if (!roster.count) return @"로스터 대기";
    NSSet<NSString *> *members = pkTroopMembers(roster);

    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    for (PKPikmin *p in roster) [alive addObject:p.pid];
    [backoff() pruneKeeping:alive];

    NSArray<PKPikmin *> *elig = nil;
    int busyInTroop = 0;
    NSString *plan = nil;
    NSArray<PKPikmin *> *want = pkTroopWanted(roster, members, counts.max, &elig, &busyInTroop, &plan);
    PKLOGC(@"troop.plan", ([NSString stringWithFormat:@"[부대] 배정: %@", plan]));
    NSMutableSet<NSString *> *wantIds = [NSMutableSet set];
    for (PKPikmin *p in want) [wantIds addObject:p.pid];

    NSMutableArray<NSString *> *out = [NSMutableArray array], *in = [NSMutableArray array];
    for (PKPikmin *p in elig)
        if ([members containsObject:p.pid] && ![wantIds containsObject:p.pid] && [backoff() ready:p.pid]) [out addObject:p.pid];
    for (PKPikmin *p in want)
        if (![members containsObject:p.pid] && [backoff() ready:p.pid]) [in addObject:p.pid];

    if (!out.count && !in.count)
        return [NSString stringWithFormat:@"부대 %d/%d — 이미 최적 (%@)", counts.total, counts.max, plan];
    if (!pkRpcArrangeTroop(in, out)) return @"부대 교체 요청 실패";
    for (NSString *pid in [in arrayByAddingObjectsFromArray:out]) [backoff() recordSend:pid];
    pkTroopInvalidate();
    pkRosterInvalidate();
    PALOG(@"[부대] 교체: 넣기 +%lu / 빼기 -%lu (목표 %lu/%d, 작업중 %d)", (unsigned long)in.count, (unsigned long)out.count,
          (unsigned long)want.count, counts.max, busyInTroop);
    return [NSString stringWithFormat:@"🚶 부대 교체 +%lu/-%lu (목표 %lu/%d) %@", (unsigned long)in.count, (unsigned long)out.count,
            (unsigned long)want.count, counts.max, plan];
}
