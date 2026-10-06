#import "Scheduler.h"
#import "Clock.h"
#import "CpuStats.h"
#import "Frame.h"
#import "SingletonFinder.h"
#import "FrameRate.h"
#import "GameContext.h"
#import "Hooks.h"
#import "Layout.h"
#import "Location.h"
#import "Log.h"
#import "Passes.h"
#import "RpcClient.h"
#import "Settings.h"
#import <UIKit/UIKit.h>

// Self-pacing. The game answers every request on its main thread, so when that
// thread is already late (the 1 s timer fires more than kStallThreshold behind)
// nothing more is piled on for kCalmHold, up to kMaxHold in a row — after that
// the passes run regardless, so a permanently busy game cannot starve them.
// The first kStartupQuiet seconds belong to the game loading.
static const NSTimeInterval kStartupQuiet = 75.0;
static const double kStallThreshold = 0.2;
static const NSTimeInterval kCalmHold = 3.0, kMaxHold = 15.0;
static NSTimeInterval gStartedAt = 0, gCalmAfter = 0;
static BOOL gRestagger = YES;                     // spread the passes' next runs (launch, and every return to the app)
static int gHeldTicks = 0;

BOOL pkMainThreadCalm(void) { return pkMono() >= gCalmAfter; }

static const NSTimeInterval kTickGap = 0.7;        // the 1 s timer and 1 Hz location fixes must not double-fire
static const NSTimeInterval kMapPace = 30.0;       // mapobjects.json refresh
static const NSTimeInterval kRosterPace = 60.0;    // roster.json/.txt refresh (planning data, not time-critical)
static const NSTimeInterval kFpsPace = 20.0;

// ---------- pass timing ----------
// How long each pass actually takes; without it, tuning cadences is guesswork.
// Reported by the heartbeat as total-ms/calls.
static NSMutableDictionary<NSString *, NSNumber *> *gPassMs, *gPassN;
static void noteMs(NSString *name, NSTimeInterval seconds) {
    if (!gPassMs) { gPassMs = [NSMutableDictionary dictionary]; gPassN = [NSMutableDictionary dictionary]; }
    gPassMs[name] = @(gPassMs[name].doubleValue + seconds * 1000.0);
    gPassN[name] = @(gPassN[name].intValue + 1);
}
static NSString *timed(NSString *name, NSString *(^body)(void)) {
    NSTimeInterval t0 = pkMono();
    NSString *r = body();
    noteMs(name, pkMono() - t0);
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
    BOOL camera = NO;
    for (PKFeature *f in pkFeatures()) camera |= f.suppressCamera;
    // Rendering the map is the heat source: cap the frame rate while any part of
    // the pipeline is running. The cap is constant on purpose — the phone is in
    // the player's hand most of the time, so a cap that lifts on touch would
    // never be on.
    pkSetCameraSuppress(camera && [PKSettings boolForKey:kSettingCamSuppress]);
    pkApplyFrameRate(YES);
}

// ---------- the tick ----------
static BOOL appActive(void) { return [UIApplication sharedApplication].applicationState == UIApplicationStateActive; }

void pkSchedulerTick(void) {
    static NSTimeInterval last = 0, lastMap = 0, lastRoster = 0, lastFps = 0;
    static BOOL started = NO;
    // Automation only runs while the app is in front. Nothing here keeps the
    // process alive in the background; if the system keeps the game running
    // anyway, the passes still stand down.
    if (!appActive()) return;
    NSTimeInterval now = pkMono();
    if (now - last < kTickGap) return;
    if (last > 0 && now - last > 10.0) gRestagger = YES;     // came back from the background / a long stall
    last = now;
    if (pkRuntimeReady()) pkAdoptCaptured();
    if (!started) {
        // Phase the periodic work so it does not all land on one tick: the two
        // dumps used to fire together with the 30 s passes.
        started = YES;
        lastMap = now - kMapPace + 11.0;
        lastRoster = now - kRosterPace + 23.0;
    }

    if (now - lastFps >= kFpsPace) { lastFps = now; syncSideEffects(); }   // the game resets the cap across scenes

    // A game update that moved fields we cannot find by name pauses everything
    // rather than acting on garbage.
    if (!pkLayoutHealthy()) {
        PKLOGC(@"layout.paused", @"[layout] 해석 실패한 필드가 있어 자동화 일시정지 — 로그의 [layout] 줄 확인");
        return;
    }
    if (now - gStartedAt < kStartupQuiet) return;           // the game is still loading
    static NSTimeInterval heldSince = 0;
    if (!pkMainThreadCalm()) {
        if (!heldSince) heldSince = now;
        if (now - heldSince < kMaxHold) { gHeldTicks++; return; }
    }
    heldSince = 0;

    if (gRestagger) {
        // Every pass is overdue after the quiet period or a stay in the background;
        // run them all in one tick and the game takes ninety requests at once.
        // Give each its own phase, as at first start.
        gRestagger = NO;
        NSUInteger i = 0;
        for (PKFeature *f in pkFeatures()) { f.lastRun = now - f.pace + fmod(1.0 + 2.0 * (double)i, f.pace); i++; }
        lastMap = now - kMapPace + 11.0;
        lastRoster = now - kRosterPace + 23.0;
    }

    // One frame for the whole tick: every pass that runs now shares one roster
    // / squad / nectar / petal scan (runFeature nests inside it).
    pkFrameBegin();
    for (PKFeature *f in pkFeatures()) {
        if (now - f.lastRun >= f.pace) runFeature(f);
    }
    if (pkMapObj() && now - lastMap >= kMapPace) { lastMap = now; timed(@"map", ^{ pkMapDumpPass(); return @""; }); }
    if (pkMgr() && now - lastRoster >= kRosterPace) { lastRoster = now; timed(@"로스터", ^{ pkRosterDumpPass(); return @""; }); }
    pkFrameEnd();
}

// ---------- maintenance ----------
// How late the 1 s timer fires: whatever kept the main thread busy (a heavy
// frame, our own passes, a game stall) shows up here. Reset by each heartbeat.
static double gLateMax = 0;
static int gLate100 = 0, gLate500 = 0;

static void maintenance(void) {
    static NSTimeInterval lastFire = 0;
    NSTimeInterval fired = pkMono();
    if (!appActive()) { lastFire = 0; return; }
    if (lastFire > 0) {
        double late = fired - lastFire - 1.0;
        if (late < 30) {                                   // a resume from the background is not a stall
            gLateMax = MAX(gLateMax, late);
            if (late > kStallThreshold) gCalmAfter = fired + kCalmHold;
            if (late > 0.1) gLate100++;
            if (late > 0.5) gLate500++;
        }
    }
    lastFire = fired;
    static int beat = 0;
    // Only runs that did real work are recorded, so the [hb] ms/calls reads as
    // the cost of one run.
    NSTimeInterval t0 = pkMono();
    if (pkRuntimeReady()) pkAdoptCaptured();
    pkInstallHooks();
    NSTimeInterval t1 = pkMono();
    if (t1 - t0 >= 0.001) noteMs(@"훅", t1 - t0);
    if (pkResolveSingletons()) noteMs(@"finder", pkMono() - t1);   // adopt what the hooks have not caught
    if (pkRuntimeReady()) pkAdoptCaptured();                        // ... and what the finder just found
    if (++beat % 60) return;
    static NSArray *therm = @[ @"정상", @"주의", @"높음", @"위험" ];
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    NSProcessInfoThermalState ts = NSProcessInfo.processInfo.thermalState;
    PALOG(@"[hb] rpc=%d mgr=%d inv=%d 위치 %lu회, 마지막 %.0f초 전 | 발열 %@, 배터리 %.0f%% | 패스 %@",
          pkRpc() != NULL, pkMgr() != NULL, pkInv() != NULL, pkLocationCount(), MIN(pkLocationAge(), 9999.0),
          therm[MIN((int)ts, 3)], UIDevice.currentDevice.batteryLevel * 100.0, takeTimings());
    PALOG(@"[hb2] %@ | 후킹 호출/분 %@ | RPC/분 %@ | 전송 큐 %@ | 보류 틱 %d | 메인 지연 최대 %.0fms (>100ms %d회, >500ms %d회)",
          pkCpuSummary(), pkHookStats(), pkRpcStats(), pkRpcQueueStats(), gHeldTicks, MAX(gLateMax, 0) * 1000.0, gLate100, gLate500);
    gLateMax = 0; gLate100 = gLate500 = 0; gHeldTicks = 0;
}

void pkSchedulerStart(void) {
    static BOOL started = NO;
    if (started) return;
    started = YES;
    [PKSettings registerDefaults];
    gStartedAt = pkMono();
    pkRpcSetGate(^BOOL{ return pkMainThreadCalm(); });
    pkLayoutInit();
    pkLocationStart(^{ pkSchedulerTick(); });
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { pkSchedulerTick(); }];
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { maintenance(); }];
    syncSideEffects();
}
