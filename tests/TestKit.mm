#import "TestKit.h"

int gChecks = 0, gFailures = 0;
NSTimeInterval gPkTestNow = 0;

// Roster.mm owns the real implementation (it needs the game); the one method the
// logic under test calls is reproduced here.
@implementation PKPikmin
- (BOOL)isDecor { return _asset >= 2; }
@end

PKPikmin *pikmin(NSString *pid, int color, float hearts, BOOL decor, int status) {
    PKPikmin *p = [PKPikmin new];
    p.pid = pid; p.color = color; p.hearts = hearts; p.asset = decor ? 2 : 1; p.status = status;
    return p;
}
