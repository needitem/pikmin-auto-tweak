#import "Passes.h"
#import "Backoff.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Runtime.h"
#import "Log.h"
#import "Roster.h"
#import "RpcClient.h"
#import "Troop.h"

// Fill the walking troop up to its cap by a 4-tier priority. The target is to
// raise every Pikmin to 4 hearts (the red maximum), so those still under 4
// come first, and decor (costume) Pikmin before ordinary ones within a tier:
//   1) decor < 4   2) plain < 4   3) decor >= 4   4) plain >= 4
// The troop is the subset that walks with the player, gains friendship, is fed
// and fights; its cap is PikminUtils.GetPikminInTroopCountMax (level-based).
//
// The ideal set is recomputed every pass and SWAPPED in: members outside it
// move out, missing ones move in, so weaker members are replaced instead of
// lingering. The arrange RPC is async and the in-troop read lags a pass or two,
// so a Pikmin is not moved again within the cooldown.
static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:90 factor:1 max:90]; });
    return b;
}

static int tierOf(PKPikmin *p) {
    if (p.hearts < PK_HEARTS_TARGET) return p.isDecor ? 1 : 2;
    return p.isDecor ? 3 : 4;
}

NSString *pkTroopPass(void) {
    if (!pkRpc() || !pkInv() || !pkRuntimeReady()) return @"서버 대기";
    PKTroopCounts counts = pkTroopCounts();
    if (counts.max <= 0) return @"부대 최대치 0";
    NSArray<PKPikmin *> *roster = pkRoster();
    if (!roster.count) return @"로스터 대기";
    NSSet<NSString *> *members = pkTroopMembers(roster);

    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    NSMutableArray<PKPikmin *> *elig = [NSMutableArray array];
    int busyInTroop = 0;
    for (PKPikmin *p in roster) {
        [alive addObject:p.pid];
        if (p.status == PK_STATUS_TASK) {                 // busy on a task — cannot be moved,
            if ([members containsObject:p.pid]) busyInTroop++;   // but it still occupies a troop slot
            continue;
        }
        [elig addObject:p];
    }
    [backoff() pruneKeeping:alive];

    [elig sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) {
        int ta = tierOf(a), tb = tierOf(b);
        if (ta != tb) return ta < tb ? NSOrderedAscending : NSOrderedDescending;       // lower tier first
        if (a.hearts != b.hearts) return a.hearts > b.hearts ? NSOrderedAscending : NSOrderedDescending;  // closest to 4 first, so slots rotate
        return [a.pid compare:b.pid];                                                   // deterministic: no membership flapping
    }];

    NSUInteger slots = (NSUInteger)MAX(counts.max - busyInTroop, 0);
    NSArray<PKPikmin *> *want = elig.count > slots ? [elig subarrayWithRange:NSMakeRange(0, slots)] : elig;
    NSMutableSet<NSString *> *wantIds = [NSMutableSet set];
    for (PKPikmin *p in want) [wantIds addObject:p.pid];

    NSMutableArray<NSString *> *out = [NSMutableArray array], *in = [NSMutableArray array];
    for (PKPikmin *p in elig)
        if ([members containsObject:p.pid] && ![wantIds containsObject:p.pid] && [backoff() ready:p.pid]) [out addObject:p.pid];
    for (PKPikmin *p in want)
        if (![members containsObject:p.pid] && [backoff() ready:p.pid]) [in addObject:p.pid];

    if (!out.count && !in.count)
        return [NSString stringWithFormat:@"부대 %d/%d — 이미 최적(데코 우선 4티어)", counts.total, counts.max];
    if (!pkRpcArrangeTroop(in, out)) return @"부대 교체 요청 실패";
    for (NSString *pid in [in arrayByAddingObjectsFromArray:out]) [backoff() recordSend:pid];
    pkTroopInvalidate();
    pkRosterInvalidate();
    PALOG(@"[부대] 교체: 넣기 +%lu / 빼기 -%lu (목표 %lu/%d, 작업중 %d)", (unsigned long)in.count, (unsigned long)out.count,
          (unsigned long)want.count, counts.max, busyInTroop);
    return [NSString stringWithFormat:@"🚶 부대 교체 +%lu/-%lu (목표 %lu/%d)", (unsigned long)in.count, (unsigned long)out.count,
            (unsigned long)want.count, counts.max];
}
