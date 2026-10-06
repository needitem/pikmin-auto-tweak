#import "RpcPacer.h"
#import "Clock.h"

static const NSTimeInterval kPaceGap = 0.25;       // between two deferred requests
static const NSTimeInterval kMaxWait = 20.0;       // a request never waits longer than this for a calm moment

static NSMutableArray<void (^)(void)> *gQueue;
static NSMutableArray<NSNumber *> *gQueuedAt;
static NSTimer *gTimer;
static BOOL (^gGate)(void);
static unsigned long gDeferred, gForced;
static NSUInteger gPeak;

BOOL pkRpcPump(NSTimeInterval now) {
    if (!gQueue.count) return NO;
    BOOL calm = !gGate || gGate();
    BOOL stale = now - gQueuedAt.firstObject.doubleValue > kMaxWait;
    if (!calm && !stale) return NO;
    if (!calm) gForced++;
    void (^send)(void) = gQueue.firstObject;
    [gQueue removeObjectAtIndex:0]; [gQueuedAt removeObjectAtIndex:0];
    send();
    return YES;
}

static void tick(void) {
    pkRpcPump(pkMono());
    if (!gQueue.count) { [gTimer invalidate]; gTimer = nil; }
}

void pkRpcSetGate(BOOL (^calm)(void)) { gGate = [calm copy]; }

void pkRpcDefer(void (^send)(void)) {
    if (!gQueue) { gQueue = [NSMutableArray array]; gQueuedAt = [NSMutableArray array]; }
    [gQueue addObject:[send copy]]; [gQueuedAt addObject:@(pkMono())];
    gDeferred++;
    gPeak = MAX(gPeak, gQueue.count);
    if (!gTimer) gTimer = [NSTimer scheduledTimerWithTimeInterval:kPaceGap repeats:YES block:^(NSTimer *t) { tick(); }];
}

NSString *pkRpcQueueStats(void) {
    NSString *s = [NSString stringWithFormat:@"예약 %lu · 강제 %lu · 대기 %lu (최대 %lu)", gDeferred, gForced,
                   (unsigned long)gQueue.count, (unsigned long)gPeak];
    gDeferred = gForced = 0; gPeak = gQueue.count;
    return s;
}
