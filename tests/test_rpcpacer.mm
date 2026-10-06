#import "TestKit.h"
#import "RpcPacer.h"

extern NSTimeInterval gPkTestNow;

static NSMutableArray<NSString *> *gSentLog;
static void defer(NSString *name) { pkRpcDefer(^{ [gSentLog addObject:name]; }); }

// One request per pump, in the order they were queued.
void test_pacer_one_at_a_time_in_order(void) {
    gSentLog = [NSMutableArray array];
    pkRpcSetGate(nil);
    gPkTestNow = 0;
    defer(@"a"); defer(@"b"); defer(@"c");
    CHECK(pkRpcPump(0));                         // released one
    CHECK_EQ(gSentLog.count, 1);
    CHECK([gSentLog.lastObject isEqualToString:@"a"]);
    pkRpcPump(0.25); pkRpcPump(0.5);
    CHECK([gSentLog isEqualToArray:(@[ @"a", @"b", @"c" ])]);
    CHECK(!pkRpcPump(0.75));                     // empty: nothing to do
}

// While the main thread is busy the queue holds; it resumes when the gate opens.
void test_pacer_holds_while_busy(void) {
    gSentLog = [NSMutableArray array];
    __block BOOL calm = NO;
    pkRpcSetGate(^BOOL{ return calm; });
    gPkTestNow = 0;
    defer(@"x");
    CHECK(!pkRpcPump(1));
    CHECK(!pkRpcPump(10));
    CHECK_EQ(gSentLog.count, 0);
    calm = YES;
    CHECK(pkRpcPump(11));
    CHECK_EQ(gSentLog.count, 1);
}

// A request is never held for ever: after 20 s it goes out even though the gate stays shut.
void test_pacer_stale_request_is_forced(void) {
    gSentLog = [NSMutableArray array];
    pkRpcSetGate(^BOOL{ return NO; });
    gPkTestNow = 100;
    defer(@"old");
    CHECK(!pkRpcPump(119.9));
    CHECK(pkRpcPump(120.1));
    CHECK_EQ(gSentLog.count, 1);
    NSString *stats = pkRpcQueueStats();
    CHECK([stats containsString:@"강제 1"]);
}

// The stats line counts what was queued since the last read and resets.
void test_pacer_stats(void) {
    gSentLog = [NSMutableArray array];
    pkRpcSetGate(nil);
    gPkTestNow = 0;
    pkRpcQueueStats();                           // clear
    defer(@"1"); defer(@"2"); defer(@"3");
    pkRpcPump(0);
    NSString *s = pkRpcQueueStats();
    CHECK([s containsString:@"예약 3"]);
    CHECK([s containsString:@"대기 2"]);
    CHECK([s containsString:@"최대 3"]);
    pkRpcPump(1); pkRpcPump(2);
    NSString *s2 = pkRpcQueueStats();
    CHECK([s2 containsString:@"예약 0"]);
    CHECK([s2 containsString:@"대기 0"]);
}
