#import "Passes.h"
#import "Backoff.h"
#import "Clock.h"
#import "Expeditions.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Inventory.h"
#import "Layout.h"
#import "Log.h"
#import "RpcClient.h"

// Pikmin come home holding things: fruit and seedlings they carried, gifts.
// Each is a PikminTask in the inventory, claimed with CompletePikminTask —
// the game's 수집 button. The task list is the right source: everything
// claimable is in it.
//
// An expedition is claimable only once the game's own state machine says
// Returned; its finish time passing is not enough (the Pikmin still have to
// walk home, and the server refuses until then).
static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:60 factor:2 max:600]; });   // a refused task waits longer each time
    return b;
}

NSString *pkCollectPass(void) {
    if (!pkInv() || !pkRpc()) return @"인벤토리/서버 준비 대기";
    void *list = pkInvList("GetPikminTaskList");
    if (!list) return @"태스크 목록 없음";
    if (pkListCount(list) == 0) return @"수집할 것 없음";

    NSSet<NSString *> *returned = pkReturnedExpeditionIds();
    long long nowMs = pkWallMs();        // compared with server timestamps in the task protos

    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    NSMutableArray<NSString *> *claimable = [NSMutableArray array];
    NSCountedSet *kinds = [NSCountedSet set];
    __block int running = 0, idle = 0, other = 0;
    pkListEach(list, ^(void *item) {
        NSString *tid = pkItemId(item);
        void *proto = pkItemProto(item);
        if (!tid.length || !proto) return;
        [alive addObject:tid];
        int kase = pkGetInt(proto, &F_Task_case);
        long long start = pkGetI64(proto, &F_Task_start), finish = pkGetI64(proto, &F_Task_finish);
        [kinds addObject:@(kase)];
        if (kase == PK_TASK_EXPEDITION) {
            // Sent or not, an expedition is the 탐험 pass's business until the game says they are home.
            if (start == 0) { idle++; return; }
            if (![returned containsObject:tid]) { running++; return; }
        } else if (kase == PK_TASK_CARRY || kase == PK_TASK_GIFT) {
            if (finish > nowMs) { running++; return; }          // still being carried home
        } else {
            other++; return;                                    // mushroom challenges etc. are not ours to claim
        }
        [claimable addObject:tid];
    });
    [backoff() pruneKeeping:alive];

    int sent = 0;
    for (NSString *tid in claimable) {
        if (![backoff() ready:tid]) continue;
        int tries = [backoff() tries:tid];
        if (pkRpcCompleteTask(tid)) {
            [backoff() recordSend:tid];
            sent++;
            PALOG(@"[collect] 수집 요청 task=%@%@", tid, tries ? [NSString stringWithFormat:@" (%d번째)", tries + 1] : @"");
        }
        if (sent >= 5) break;                                   // a handful per pass
    }

    NSMutableArray *cen = [NSMutableArray array];
    for (NSNumber *k in [kinds.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        int v = k.intValue;
        NSString *name = v == PK_TASK_CARRY ? @"운반" : v == PK_TASK_EXPEDITION ? @"탐험" :
                         v == PK_TASK_GIFT ? @"선물" : v == PK_TASK_POICHALLENGE ? @"버섯" :
                         [NSString stringWithFormat:@"종류%@", k];
        [cen addObject:[NSString stringWithFormat:@"%@ %lu", name, (unsigned long)[kinds countForObject:k]]];
    }
    return [NSString stringWithFormat:@"📦 수집 요청 %d건 / 수령가능 %lu, 진행중 %d, 미출발 %d, 제외 %d [%@]",
            sent, (unsigned long)claimable.count, running, idle, other, [cen componentsJoinedByString:@", "]];
}
