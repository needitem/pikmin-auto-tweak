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

// Nectar.mm owns the real implementation (it reads the game); the tests need the class itself.
#import "Nectar.h"
@implementation PKNectar
@end

PKNectar *nectar(NSString *itemId, int balls, int type, NSString *kindName, int hkind) {
    PKNectar *n = [PKNectar new];
    n.itemId = itemId; n.balls = balls; n.type = type; n.kindName = kindName ?: @""; n.hkind = hkind;
    n.special = kindName.length > 0;
    return n;
}
