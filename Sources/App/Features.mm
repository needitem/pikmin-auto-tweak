#import "Feature.h"
#import "Clock.h"
#import "Passes.h"

@implementation PKFeature
@end

// Paces: each pass runs on its own cadence. The old driver ran every pass
// every second — dozens of RPCs a second while feeding, a request pattern no
// real player produces. These keep the pipeline at an ordinary rate.
static PKFeature *make(NSString *tag, NSTimeInterval pace, BOOL camera, NSString *(*run)(void)) {
    PKFeature *f = [PKFeature new];
    f.tag = tag; f.pace = pace; f.suppressCamera = camera;
    f.run = ^NSString *{ return run(); };
    return f;
}

static void stagger(NSArray<PKFeature *> *features, NSTimeInterval now) {
    [features enumerateObjectsUsingBlock:^(PKFeature *f, NSUInteger i, BOOL *stop) {
        f.lastRun = now - f.pace + fmod(1.0 + 2.0 * (double)i, f.pace);
    }];
}

void pkFeaturesRestagger(NSTimeInterval now) { stagger(pkFeatures(), now); }

NSArray<PKFeature *> *pkFeatures(void) {
    static NSArray<PKFeature *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        //           tag      pace  cam   pass
        all = @[
            make(@"feed",   15, YES, pkFeedPass),     // whole squad, five ids per request
            make(@"harvest",  8, YES, pkHarvestPass),  // only Pikmin holding petals
            make(@"collect", 10, YES, pkCollectPass),  // complete returned expeditions
            make(@"탐험",      8, YES, pkExpeditionPass), // up to four send-offs per pass
            make(@"심기",     30, YES, pkPlantPass),    // planting session check
            make(@"큰꽃",      6, YES, pkBigFlowerPass), // big-flower scan
            make(@"모종",     10, YES, pkSeedPass),     // seedling plant/pluck
            make(@"부대",     30, NO, pkTroopPass),    // an arrange RPC never moves the camera
            make(@"번호",     15, NO, pkNumberingPass), // rename every Pikmin to its pluck-order number
        ];
        stagger(all, pkMono());
    });
    return all;
}
