#import "Feature.h"
#import "Clock.h"
#import "Passes.h"
#import "Settings.h"

@implementation PKFeature
- (BOOL)enabled { return [PKSettings boolForKey:_key]; }
@end

// Paces: each pass runs on its own cadence. The old driver ran every pass
// every second — dozens of RPCs a second while feeding, a request pattern no
// real player produces. These keep the pipeline at an ordinary rate.
static PKFeature *make(NSString *key, NSString *title, NSString *tag, NSTimeInterval pace,
                       BOOL inAuto, BOOL camera, BOOL fgOnly, NSString *(*run)(void)) {
    PKFeature *f = [PKFeature new];
    f.key = key; f.title = title; f.tag = tag; f.pace = pace;
    f.inAuto = inAuto; f.suppressCamera = camera; f.foregroundOnly = fgOnly;
    f.run = ^NSString *{ return run(); };
    return f;
}

NSArray<PKFeature *> *pkFeatures(void) {
    static NSArray<PKFeature *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        //           key            title   tag        pace  auto  cam   fgOnly  pass
        all = @[
            make(kKeyFeed,       @"정수", @"feed",     15,   YES,  YES,  NO,  pkFeedPass),        // whole squad, five ids per request
            make(kKeyHarvest,    @"수확", @"harvest",   8,   YES,  YES,  NO,  pkHarvestPass),     // only Pikmin holding petals
            make(kKeyCollect,    @"수집", @"collect",  10,   YES,  YES,  NO,  pkCollectPass),     // complete returned expeditions
            make(kKeyExpedition, @"탐험", @"탐험",      8,   YES,  YES,  NO,  pkExpeditionPass),  // up to four send-offs per pass
            make(kKeyPlant,      @"심기", @"심기",     30,   YES,  YES,  NO,  pkPlantPass),       // planting session check
            make(kKeyPoi,        @"큰꽃", @"큰꽃",      6,   YES,  YES,  NO,  pkBigFlowerPass),   // big-flower scan
            make(kKeySeed,       @"모종", @"모종",     10,   YES,  YES,  NO,  pkSeedPass),        // seedling plant/pluck
            make(kKeyTroop,      @"부대", @"부대",     30,   YES,  NO,   NO,  pkTroopPass),       // an arrange RPC never moves the camera
            make(kKeyNumber,     @"번호", @"번호",     15,   NO,   NO,   YES, pkNumberingPass),   // not part of 자동성장
        ];
        // Stagger the first runs. Every feature used to start at lastRun = 0, so
        // equal paces (harvest/탐험 at 8 s, 모종/수집 at 10 s, 심기/부대 at 30 s)
        // stayed on the same tick forever and their scans stacked into one long
        // main-thread stall. A distinct phase per feature keeps them apart.
        NSTimeInterval now = pkMono();
        [all enumerateObjectsUsingBlock:^(PKFeature *f, NSUInteger i, BOOL *stop) {
            f.lastRun = now - f.pace + fmod(1.0 + 2.0 * (double)i, f.pace);
        }];
    });
    return all;
}
