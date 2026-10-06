#import "Scheduler.h"
#import "AppState.h"
#import "Clock.h"
#import "Feature.h"
#import "Frame.h"
#import "GameContext.h"
#import "Governor.h"
#import "Layout.h"
#import "Location.h"
#import "Log.h"
#import "Maintenance.h"
#import "PassTimings.h"
#import "Passes.h"
#import "RpcPacer.h"
#import "Settings.h"
#import "SideEffects.h"

static const NSTimeInterval kTickGap = 0.7;        // the 1 s timer and 1 Hz location fixes must not double-fire
static const NSTimeInterval kMapPace = 30.0;       // mapobjects.json refresh
static const NSTimeInterval kRosterPace = 60.0;    // roster.json/.txt refresh (planning data, not time-critical)
static const NSTimeInterval kSideEffectsPace = 20.0;
static const NSTimeInterval kResumeGap = 10.0;     // a longer silence between ticks counts as a return to the app

static NSTimeInterval gLastMap, gLastRoster;

static void runFeature(PKFeature *f) {
    f.lastRun = pkMono();
    pkFrameBegin();                                   // state reads are shared until the frame ends
    NSString *status = pkTimed(f.tag, f.run);
    pkFrameEnd();
    PKLOGC([@"pass." stringByAppendingString:f.tag], [NSString stringWithFormat:@"[%@] %@", f.tag, status]);
}

// Spread the periodic work so it does not all land on one tick: the dumps used
// to fire together with the 30 s passes.
static void restaggerDumps(NSTimeInterval now) {
    gLastMap = now - kMapPace + 11.0;
    gLastRoster = now - kRosterPace + 23.0;
}

void pkSchedulerTick(void) {
    static NSTimeInterval last = 0, lastSideEffects = 0;
    // Automation only runs while the app is in front.
    if (!pkAppActive()) return;
    NSTimeInterval now = pkMono();
    if (now - last < kTickGap) return;
    if (last > 0 && now - last > kResumeGap) pkGovernorRequestRestagger();
    last = now;
    if (pkRuntimeReady()) pkAdoptCaptured();
    if (now - lastSideEffects >= kSideEffectsPace) { lastSideEffects = now; pkSyncSideEffects(); }

    // A game update that moved fields we cannot find by name pauses everything
    // rather than acting on garbage.
    if (!pkLayoutHealthy()) {
        PKLOGC(@"layout.paused", @"[layout] 해석 실패한 필드가 있어 자동화 일시정지 — 로그의 [layout] 줄 확인");
        return;
    }
    if (!pkGovernorAllowWork(now)) return;                   // the game is loading, or its main thread is busy
    if (pkGovernorTakeRestagger()) { pkFeaturesRestagger(now); restaggerDumps(now); }

    // One frame for the whole tick: every pass that runs now shares one roster
    // / squad / nectar / petal scan (runFeature nests inside it).
    pkFrameBegin();
    for (PKFeature *f in pkFeatures()) {
        if (now - f.lastRun >= f.pace) runFeature(f);
    }
    if (pkMapObj() && now - gLastMap >= kMapPace) { gLastMap = now; pkTimed(@"map", ^{ pkMapDumpPass(); return @""; }); }
    if (pkMgr() && now - gLastRoster >= kRosterPace) { gLastRoster = now; pkTimed(@"로스터", ^{ pkRosterDumpPass(); return @""; }); }
    pkFrameEnd();
}

void pkSchedulerStart(void) {
    static BOOL started = NO;
    if (started) return;
    started = YES;
    [PKSettings registerDefaults];
    pkGovernorStart(pkMono());
    pkRpcSetGate(^BOOL{ return pkGovernorCalm(pkMono()); });
    pkLayoutInit();
    pkLocationStart(^{ pkSchedulerTick(); });
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { pkSchedulerTick(); }];
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { pkMaintenanceTick(); }];
    pkSyncSideEffects();
}
