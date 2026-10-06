#import "TestKit.h"
#import "Bisect.h"

// For every threshold the smallest passing n is found, and with at most ceil(log2 count) probes.
void test_bisect(void) {
    for (NSUInteger count = 1; count <= 16; count++) {
        for (NSUInteger threshold = 1; threshold <= count; threshold++) {
            __block int probes = 0;
            NSUInteger got = pkSmallestPassing(count, ^BOOL(NSUInteger n) { probes++; return n >= threshold; });
            if (got != threshold) { CHECK_EQ(got, threshold); }
            int bound = 0; for (NSUInteger c = count; c > 1; c = (c + 1) / 2) bound++;      // ceil(log2 count)
            if (probes > bound) { CHECK(probes <= bound); }
        }
    }
    gChecks++;                                         // the loops above only report failures
}

void test_bisect_edges(void) {
    CHECK_EQ(pkSmallestPassing(0, ^BOOL(NSUInteger n) { return YES; }), 0);
    __block int probes = 0;
    CHECK_EQ(pkSmallestPassing(1, ^BOOL(NSUInteger n) { probes++; return YES; }), 1);
    CHECK_EQ(probes, 0);                               // nothing to ask when only one is possible
    // the largest is assumed to pass and never asked
    __block BOOL askedLargest = NO;
    pkSmallestPassing(8, ^BOOL(NSUInteger n) { if (n == 8) askedLargest = YES; return n >= 3; });
    CHECK(!askedLargest);
}
