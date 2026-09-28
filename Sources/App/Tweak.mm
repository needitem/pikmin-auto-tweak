// Entry point. Everything else is a module; see the layer map in README.md.
#import "Overlay.h"
#import "Runtime.h"
#import "Scheduler.h"
#import <pthread.h>
#import <unistd.h>

// The constructor runs long before the game has a scene, and Unity's il2cpp
// is not initialised until well after. Everything that only reads settings or
// starts location (the scheduler) may start at once; the il2cpp bridge is armed
// only after the game has created its scene, with a little grace on top —
// touching il2cpp earlier crashes inside UnityFramework at launch.
static const useconds_t kArmGraceUs = 3 * 1000 * 1000;

static void *waitForGame(void *unused) {
    dispatch_sync(dispatch_get_main_queue(), ^{ pkSchedulerStart(); });
    for (int i = 0; i < 14400; i++) {                 // an hour of quarter-seconds
        __block BOOL done = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ done = pkOverlayEnsure(); });
        if (done) {
            usleep(kArmGraceUs);
            dispatch_sync(dispatch_get_main_queue(), ^{ pkRuntimeArm(); });
            return NULL;
        }
        usleep(250000);
    }
    return NULL;
}

__attribute__((constructor)) static void pikminAutoInit(void) {
    @autoreleasepool {
        pthread_t th;
        pthread_create(&th, NULL, waitForGame, NULL);
        pthread_detach(th);
    }
}
