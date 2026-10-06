#import "TestKit.h"
#import "PassTimings.h"

extern NSTimeInterval gPkTestNow;

void test_passtimings(void) {
    pkTimingsTake();                                       // clear
    CHECK([pkTimingsTake() isEqualToString:@"-"]);
    gPkTestNow = 0;
    NSString *r = pkTimed(@"feed", ^NSString *{ gPkTestNow = 0.012; return @"done"; });   // 12 ms
    CHECK([r isEqualToString:@"done"]);
    pkTimingNote(@"feed", 0.008);
    pkTimingNote(@"harvest", 0.005);
    NSString *line = pkTimingsTake();
    CHECK([line containsString:@"feed 20/2"]);
    CHECK([line containsString:@"harvest 5/1"]);
    CHECK([pkTimingsTake() isEqualToString:@"-"]);         // reset by the read
}
