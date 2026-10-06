#import "SideEffects.h"
#import "Feature.h"
#import "FrameRate.h"
#import "Hooks.h"
#import "Settings.h"

void pkSyncSideEffects(void) {
    BOOL camera = NO;
    for (PKFeature *f in pkFeatures()) camera |= f.suppressCamera;
    // The user setting is folded in here so the camera hook reads a single flag.
    pkSetCameraSuppress(camera && [PKSettings boolForKey:kSettingCamSuppress]);
    // The frame cap is constant on purpose (and off unless pa_fps is set): the
    // phone is in the player's hand most of the time, so a cap that lifts on
    // touch would never be on.
    pkApplyFrameRate(YES);
}
