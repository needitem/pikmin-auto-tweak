#import "Location.h"
#import "Clock.h"
#import "Log.h"
#import <CoreLocation/CoreLocation.h>

static CLLocationManager *gManager = nil;
static CLLocation *gLast = nil;
static NSTimeInterval gLastAt = 0;
static unsigned long gCount = 0;
static void (^gOnFix)(void) = nil;

@interface PKLocationDelegate : NSObject <CLLocationManagerDelegate>
@end
@implementation PKLocationDelegate
// Fires in the background too while the session is alive.
- (void)locationManager:(CLLocationManager *)m didUpdateLocations:(NSArray<CLLocation *> *)locs {
    if (!locs.lastObject) return;
    gLast = locs.lastObject;
    gLastAt = pkMono();
    gCount++;
    if (gOnFix) gOnFix();
}
- (void)locationManager:(CLLocationManager *)m didFailWithError:(NSError *)e {
    PKLOGC(@"loc.fail", [NSString stringWithFormat:@"[keepalive] 위치 오류: %@", e.localizedDescription]);
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)m {
    PALOG(@"[keepalive] auth changed -> %d", (int)m.authorizationStatus);
}
@end

static PKLocationDelegate *gDelegate = nil;

void pkLocationStart(void (^onFix)(void)) {
    if (gManager) return;
    gOnFix = [onFix copy];
    gDelegate = [PKLocationDelegate new];
    gManager = [CLLocationManager new];
    gManager.delegate = gDelegate;
    // Whatever position consumers see is substituted anyway, so a best-accuracy
    // fix would only heat the phone; wifi/cell accuracy still counts as an
    // active session.
    gManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    gManager.distanceFilter = kCLDistanceFilterNone;
    gManager.pausesLocationUpdatesAutomatically = NO;
    @try { gManager.allowsBackgroundLocationUpdates = YES; }
    @catch (NSException *e) { PALOG(@"[keepalive] no background location: %@", e); }
    [gManager startUpdatingLocation];
    PALOG(@"[keepalive] location session started (bg=%d)", (int)gManager.allowsBackgroundLocationUpdates);
}

BOOL pkLocationGet(double *lat, double *lng) {
    if (!gLast) return NO;
    if (lat) *lat = gLast.coordinate.latitude;
    if (lng) *lng = gLast.coordinate.longitude;
    return YES;
}
NSTimeInterval pkLocationAge(void) { return gLast ? pkMono() - gLastAt : 1e9; }
unsigned long pkLocationCount(void) { return gCount; }
