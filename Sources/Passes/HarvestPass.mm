#import "Passes.h"
#import "Backoff.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Runtime.h"
#import "Roster.h"
#import "RpcClient.h"

// Only Pikmin whose petals have actually fallen — wiltedCount_ above zero, or
// the explicit FLOWER_READY_TO_PICK state. Sending the whole squad, most of it
// still growing, got the entire batch ignored.
static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:10 factor:1.5 max:120]; });
    return b;
}

// The game's own scheduler (SchedulePickPikminFlowerBatchedRequest) queues into
// its own throttled batches and dribbles a few Pikmin at a time — 37 flowers
// took over a minute — so it is only the fallback when the direct request
// cannot be built.
static void gameRoute(NSArray<NSString *> *pids) {
    void *action = pkAction();
    void *sched = action ? pkMethodOf(action, "SchedulePickPikminFlowerBatchedRequest", 1) : NULL;
    if (!sched) return;
    for (NSString *pid in pids) {
        void *a[1] = { pkNewString(pid) };
        pkInvoke(sched, action, a);
    }
}

NSString *pkHarvestPass(void) {
    if (!pkMgr() || !pkRpc()) return @"게임/서버 준비 대기";
    NSArray<PKPikmin *> *squad = pkSquad();
    if (!squad.count) return @"🌸 대열에 피크민 없음";

    NSMutableArray<PKPikmin *> *ids = [NSMutableArray array];
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    NSUInteger growing = 0, waiting = 0;
    long long pickable = 0;
    for (PKPikmin *p in squad) {
        [alive addObject:p.pid];
        if (p.wilted > 0 || p.flowerState == PK_PF_PICK) {
            pickable += p.wilted;
            // A request that changed nothing (same head, same petals) backs off;
            // one that did resets the wait.
            if ([backoff() ready:p.pid]) [ids addObject:p]; else waiting++;
        } else {
            growing++;
        }
    }
    [backoff() pruneKeeping:alive];
    if (!ids.count && !waiting)
        return [NSString stringWithFormat:@"🌸 딸 꽃잎 없음 (자라는 중 %lu)", (unsigned long)growing];
    if (!ids.count)
        return [NSString stringWithFormat:@"🌸 결과 대기 %lu마리 (자라는 중 %lu)", (unsigned long)waiting, (unsigned long)growing];

    void (^note)(PKPikmin *) = ^(PKPikmin *p) {
        [backoff() recordSend:p.pid signature:[NSString stringWithFormat:@"%d/%d/%d", p.flowerState, p.flowerCount, p.wilted]];
    };

    // Direct request first: five ids each, every chunk in this same pass, so the
    // whole squad is picked at once. The game's own scheduler
    // (SchedulePickPikminFlowerBatchedRequest) queues into its own throttled
    // batches and dribbles a few Pikmin at a time — 37 flowers took over a minute
    // — so it is only the fallback when the direct request cannot be built.
    // The requests are queued and sent a quarter of a second apart (RpcClient),
    // not all in this tick: ninety Pikmin is eighteen requests, and the game
    // answers each one on its main thread.
    int sent = 0;
    for (NSUInteger i = 0; i < ids.count; i += 5) {
        NSArray<PKPikmin *> *chunk = [ids subarrayWithRange:NSMakeRange(i, MIN((NSUInteger)5, ids.count - i))];
        NSMutableArray<NSString *> *pids = [NSMutableArray array];
        for (PKPikmin *p in chunk) [pids addObject:p.pid];
        pkRpcDefer(^{ if (!pkRpcPickFlowers(pids)) gameRoute(pids); });
        sent += (int)chunk.count;
        for (PKPikmin *p in chunk) note(p);
    }
    return [NSString stringWithFormat:@"🌸 수확 %d마리 / 꽃잎 %lld (자라는 중 %lu)", sent, pickable, (unsigned long)growing];
}
