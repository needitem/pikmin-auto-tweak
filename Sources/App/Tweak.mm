// Entry point. Everything else is a module; see the layer map in README.md.
#import "Overlay.h"
#import "Scheduler.h"
#import <pthread.h>
#import <unistd.h>

// The constructor runs long before the game has a scene. Wait for one off the
// main thread, then do the UI work on it. The scheduler starts on the first
// pass so automation does not depend on the overlay ever appearing.
static void *waitForGame(void *unused) {
    dispatch_sync(dispatch_get_main_queue(), ^{ pkSchedulerStart(); });
    for (int i = 0; i < 14400; i++) {                 // an hour of quarter-seconds
        __block BOOL done = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ done = pkOverlayEnsure(); });
        if (done) return NULL;
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
