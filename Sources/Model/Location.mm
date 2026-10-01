#import "Location.h"
#import "Clock.h"
#import "Log.h"
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

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
    PKLOGC(@"loc.fail", [NSString stringWithFormat:@"[위치] 오류: %@", e.localizedDescription]);
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)m {
    PALOG(@"[위치] 권한 변경 -> %d", (int)m.authorizationStatus);
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
    // fix would only heat the phone.
    gManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    gManager.distanceFilter = kCLDistanceFilterNone;
    [gManager startUpdatingLocation];
    // Not a keep-alive: the session is released while the app is in the
    // background, so the game is left to the system like any other app.
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *n) { [gManager stopUpdatingLocation]; }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *n) { [gManager startUpdatingLocation]; }];
    PALOG(@"[위치] 수신 시작 (포그라운드 전용)");
}

BOOL pkLocationGet(double *lat, double *lng) {
    if (!gLast) return NO;
    if (lat) *lat = gLast.coordinate.latitude;
    if (lng) *lng = gLast.coordinate.longitude;
    return YES;
}
NSTimeInterval pkLocationAge(void) { return gLast ? pkMono() - gLastAt : 1e9; }
unsigned long pkLocationCount(void) { return gCount; }
