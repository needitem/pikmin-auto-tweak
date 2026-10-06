#import "Bisect.h"

NSUInteger pkSmallestPassing(NSUInteger count, BOOL (^pass)(NSUInteger n)) {
    if (count == 0) return 0;
    NSUInteger lo = 1, hi = count;                 // the answer is in [lo, hi]; hi is known to pass
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (pass(mid)) hi = mid; else lo = mid + 1;
    }
    return lo;
}
