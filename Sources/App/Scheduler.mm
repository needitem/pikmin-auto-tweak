#import "Scheduler.h"
#import "Clock.h"
#import "Frame.h"
#import "SingletonFinder.h"
#import "FrameRate.h"
#import "GameContext.h"
#import "Hooks.h"
#import "Layout.h"
#import "Location.h"
#import "Log.h"
#import "Passes.h"
#import "Settings.h"
#import <UIKit/UIKit.h>

NSString * const PKFeaturesChangedNotification = @"PKFeaturesChanged";

static const NSTimeInterval kTickGap = 0.7;        // the 1 s timer and 1 Hz location fixes must not double-fire
static const NSTimeInterval kMapPace = 30.0;       // mapobjects.json refresh
static const NSTimeInterval kRosterPace = 30.0;    // roster.json/.txt refresh
static const NSTimeInterval kFpsPace = 20.0;
static const NSTimeInterval kBgNotePace = 300.0;

// ---------- pass timing ----------
// How long each pass actually takes; without it, tuning cadences is guesswork.
// Reported by the heartbeat as total-ms/calls.
static NSMutableDictionary<NSString *, NSNumber *> *gPassMs, *gPassN;
static NSString *timed(NSString *name, NSString *(^body)(void)) {
    if (!gPassMs) { gPassMs = [NSMutableDictionary dictionary]; gPassN = [NSMutableDictionary dictionary]; }
    NSTimeInterval t0 = pkMono();
    NSString *r = body();
    gPassMs[name] = @(gPassMs[name].doubleValue + (pkMono() - t0) * 1000.0);
    gPassN[name] = @(gPassN[name].intValue + 1);
    return r;
}
static NSString *takeTimings(void) {
    if (!gPassN.count) return @"-";
    NSMutableArray *bits = [NSMutableArray array];
    for (NSString *k in [gPassN.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [bits addObject:[NSString stringWithFormat:@"%@ %.0f/%d", k, gPassMs[k].doubleValue, gPassN[k].intValue]];
    [gPassMs removeAllObjects]; [gPassN removeAllObjects];
    return [bits componentsJoinedByString:@" "];
}

// ---------- running a feature ----------
static void runFeature(PKFeature *f) {
    f.lastRun = pkMono();
    pkFrameBegin();                                   // state reads are shared until the frame ends
    NSString *status = timed(f.tag, f.run);
    pkFrameEnd();
    PKLOGC([@"pass." stringByAppendingString:f.tag], [NSString stringWithFormat:@"[%@] %@", f.tag, status]);
}

// ---------- shared switches ----------
static void syncSideEffects(void) {
    BOOL camera = NO, throttle = NO;
    for (PKFeature *f in pkFeatures()) {
        if (!f.enabled) continue;
        camera |= f.suppressCamera;
    }
    // Rendering a map nobody watches is the heat source: cap the frame rate
    // while the pipeline that needs the phone awake is running.
    throttle = [PKSettings boolForKey:kKeyFeed] || [PKSettings boolForKey:kKeyExpedition];
    pkSetCameraSuppress(camera);
    pkApplyFrameRate(throttle);
}

static void changed(void) {
    syncSideEffects();
    [[NSNotificationCenter defaultCenter] postNotificationName:PKFeaturesChangedNotification object:nil];
}

void pkFeatureSetEnabled(PKFeature *f, BOOL on) {
    [PKSettings setBool:on forKey:f.key];
    changed();
    PALOG(@"[%@] %@", f.tag, on ? @"ON" : @"OFF");
    // Run once right away — and stamp lastRun, so the next tick does not run it again.
    if (on) runFeature(f);
}

BOOL pkAutoEnabled(void) {
    for (PKFeature *f in pkFeatures()) if (f.inAuto && !f.enabled) return NO;
    return YES;
}

void pkAutoSetEnabled(BOOL on) {
    for (PKFeature *f in pkFeatures()) if (f.inAuto) [PKSettings setBool:on forKey:f.key];
    changed();
    PALOG(@"[자동성장] %@", on ? @"ON — 정수/수확/수집/탐험/심기/큰꽃/모종/부대 전부" : @"OFF");
    if (on) { pkSchedulerTick(); }
}

// ---------- the tick ----------
void pkSchedulerTick(void) {
    static NSTimeInterval last = 0, lastMap = 0, lastRoster = 0, lastFps = 0, lastBg = 0;
    NSTimeInterval now = pkMono();
    if (now - last < kTickGap) return;
    last = now;

    // Screen off, Unity draws nothing: full speed is fine, the app stays alive
    // on the location session.
    BOOL background = [UIApplication sharedApplication].applicationState != UIApplicationStateActive;
    if (background && now - lastBg >= kBgNotePace) { lastBg = now; PALOG(@"[bg] 백그라운드에서 계속 동작 중"); }
    if (!background && now - lastFps >= kFpsPace) { lastFps = now; syncSideEffects(); }   // the game resets the cap across scenes

    // A game update that moved fields we cannot find by name pauses everything
    // rather than acting on garbage.
    if (!pkLayoutHealthy()) {
        PKLOGC(@"layout.paused", @"[layout] 해석 실패한 필드가 있어 자동화 일시정지 — 로그의 [layout] 줄 확인");
        return;
    }
    // One frame for the whole tick: every pass that runs now shares one roster
    // / squad / nectar / petal scan (runFeature nests inside it).
    pkFrameBegin();
    for (PKFeature *f in pkFeatures()) {
        if (!f.enabled || (f.foregroundOnly && background)) continue;
        if (now - f.lastRun >= f.pace) runFeature(f);
    }
    if (pkMapObj() && now - lastMap >= kMapPace) { lastMap = now; timed(@"map", ^{ pkMapDumpPass(); return @""; }); }
    if (pkMgr() && now - lastRoster >= kRosterPace) { lastRoster = now; timed(@"로스터", ^{ pkRosterDumpPass(); return @""; }); }
    pkFrameEnd();
}

// ---------- maintenance ----------
static void maintenance(void) {
    static int beat = 0;
    pkInstallHooks();
    pkResolveSingletons();                             // adopt what the hooks have not caught
    if (++beat % 60) return;
    static NSArray *therm = @[ @"정상", @"주의", @"높음", @"위험" ];
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    NSProcessInfoThermalState ts = NSProcessInfo.processInfo.thermalState;
    PALOG(@"[hb] rpc=%d mgr=%d inv=%d 위치 %lu회, 마지막 %.0f초 전 | 발열 %@, 배터리 %.0f%% | 패스 %@",
          pkRpc() != NULL, pkMgr() != NULL, pkInv() != NULL, pkLocationCount(), MIN(pkLocationAge(), 9999.0),
          therm[MIN((int)ts, 3)], UIDevice.currentDevice.batteryLevel * 100.0, takeTimings());
}

void pkSchedulerStart(void) {
    static BOOL started = NO;
    if (started) return;
    started = YES;
    [PKSettings registerDefaults];
    pkLayoutInit();
    pkLocationStart(^{ pkSchedulerTick(); });             // fixes keep arriving in the background too
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { pkSchedulerTick(); }];
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { maintenance(); }];
    syncSideEffects();
    if (!pkAutoEnabled()) PALOG(@"[ui] 자동성장 OFF — 버튼으로 켜면 전 파이프라인 가동");
}
