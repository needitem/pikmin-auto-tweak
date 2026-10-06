#import "TestKit.h"
#import "Backoff.h"

extern NSTimeInterval gPkTestNow;

void test_backoff(void) {
    PKBackoff *b = [[PKBackoff alloc] initWithBase:10 factor:2 max:100];

    gPkTestNow = 0;
    CHECK([b ready:@"a"]);                       // never sent: ready
    CHECK_EQ([b tries:@"a"], 0);

    [b recordSend:@"a"];
    CHECK(![b ready:@"a"]);
    gPkTestNow = 9.9;  CHECK(![b ready:@"a"]);
    gPkTestNow = 10.0; CHECK([b ready:@"a"]);    // waits base after the first send
    CHECK_EQ([b waitFor:@"a"], 10);

    [b recordSend:@"a"];                          // second send at t=10 waits 20
    CHECK_EQ([b waitFor:@"a"], 20);
    gPkTestNow = 29.9; CHECK(![b ready:@"a"]);
    gPkTestNow = 30.0; CHECK([b ready:@"a"]);

    // growth is capped
    for (int i = 0; i < 8; i++) [b recordSend:@"a"];
    CHECK_EQ([b waitFor:@"a"], 100);

    // another key is independent
    CHECK([b ready:@"other"]);
}

void test_backoff_signature(void) {
    PKBackoff *b = [[PKBackoff alloc] initWithBase:10 factor:2 max:100];
    gPkTestNow = 0;
    [b recordSend:@"p" signature:@"1/2/3"];
    [b recordSend:@"p" signature:@"1/2/3"];       // nothing moved: the wait keeps growing
    CHECK_EQ([b tries:@"p"], 2);
    CHECK_EQ([b waitFor:@"p"], 20);
    [b recordSend:@"p" signature:@"1/3/3"];       // state moved: the last request had an effect
    CHECK_EQ([b tries:@"p"], 1);
    CHECK_EQ([b waitFor:@"p"], 10);
}

void test_backoff_prune(void) {
    PKBackoff *b = [[PKBackoff alloc] initWithBase:10 factor:2 max:100];
    gPkTestNow = 0;
    [b recordSend:@"keep"]; [b recordSend:@"drop"];
    [b pruneKeeping:[NSSet setWithObject:@"keep"]];
    CHECK_EQ([b tries:@"keep"], 1);
    CHECK_EQ([b tries:@"drop"], 0);
    CHECK([b ready:@"drop"]);
}
