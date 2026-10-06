#import "Maintenance.h"
#import "AppState.h"
#import "Clock.h"
#import "GameContext.h"
#import "Governor.h"
#import "Heartbeat.h"
#import "Hooks.h"
#import "PassTimings.h"
#import "Runtime.h"
#import "SingletonFinder.h"

void pkMaintenanceTick(void) {
    NSTimeInterval now = pkMono();
    if (!pkAppActive()) { pkGovernorNoteInactive(); return; }
    pkGovernorNoteTimer(now);

    // Only runs that did real work are recorded, so the heartbeat's ms/calls reads
    // as the cost of one run.
    NSTimeInterval t0 = pkMono();
    if (pkRuntimeReady()) pkAdoptCaptured();
    pkInstallHooks();
    NSTimeInterval t1 = pkMono();
    if (t1 - t0 >= 0.001) pkTimingNote(@"훅", t1 - t0);
    if (pkResolveSingletons()) pkTimingNote(@"finder", pkMono() - t1);   // adopt what the hooks have not caught
    if (pkRuntimeReady()) pkAdoptCaptured();                              // ... and what the finder just found

    pkHeartbeatBeat();
}
