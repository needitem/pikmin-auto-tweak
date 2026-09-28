#import "Passes.h"
#import "Backoff.h"
#import "GameContext.h"
#import "Log.h"
#import "Roster.h"
#import "RpcClient.h"
#import "Settings.h"

// Renames every Pikmin to its pluck-order number (1..N). Idempotent: only
// Pikmin whose name is already wrong are queued, so it converges and a new
// Pikmin simply takes the next number.
//
// The queue holds only ids and text (never game pointers), and is drained by
// a paced timer — 0.4 s per rename keeps the request rate ordinary. A Pikmin
// whose name did not change after we renamed it (the server refused) backs off
// instead of being re-sent every pass.
static const NSUInteger kMaxPerPass = 100;
static const NSTimeInterval kRenameGap = 0.4;

static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:60 factor:2 max:3600]; });
    return b;
}

static NSTimer *gTimer = nil;
static NSMutableArray<NSArray<NSString *> *> *gQueue = nil;   // @[ pikminId, wantedName, nameAtQueueTime ]

static void drainOne(NSTimer *t) {
    // Switched off mid-run: drop what is left.
    if (![PKSettings boolForKey:kKeyNumber]) [gQueue removeAllObjects];
    if (!gQueue.count) { [t invalidate]; gTimer = nil; return; }
    NSArray<NSString *> *e = gQueue.firstObject;
    [gQueue removeObjectAtIndex:0];
    if (pkRpcRename(e[0], e[1])) [backoff() recordSend:e[0] signature:e[2]];
}

NSString *pkNumberingPass(void) {
    if (gTimer) return [NSString stringWithFormat:@"이름 변경 진행 중 (남은 %lu)", (unsigned long)gQueue.count];
    if (!pkMgr() || !pkRpc()) return @"게임/서버 준비 대기";
    NSArray<PKPikmin *> *roster = pkRoster();
    if (!roster.count) return @"로스터 대기";

    NSMutableArray<NSArray<NSString *> *> *todo = [NSMutableArray array];
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    NSUInteger mismatches = 0;
    for (NSUInteger i = 0; i < roster.count; i++) {
        PKPikmin *p = roster[i];
        [alive addObject:p.pid];
        NSString *want = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
        if ([p.name isEqualToString:want]) continue;
        mismatches++;
        if (todo.count < kMaxPerPass && [backoff() ready:p.pid]) [todo addObject:@[ p.pid, want, p.name ?: @"" ]];
    }
    [backoff() pruneKeeping:alive];
    NSString *msg = [NSString stringWithFormat:@"total=%lu mismatches=%lu queued=%lu",
                     (unsigned long)roster.count, (unsigned long)mismatches, (unsigned long)todo.count];
    if (!todo.count) return [NSString stringWithFormat:@"번호 %@", msg];

    gQueue = todo;
    gTimer = [NSTimer scheduledTimerWithTimeInterval:kRenameGap repeats:YES block:^(NSTimer *t) { drainOne(t); }];
    return [NSString stringWithFormat:@"번호 %@", msg];
}
