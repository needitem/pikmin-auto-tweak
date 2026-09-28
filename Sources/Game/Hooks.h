// Method hooks. Production hooks only CAPTURE singletons (and note two
// user actions); they never call back into il2cpp from inside a game callback.
// Request-logging hooks exist for debugging and are installed only when
// `defaults write ... pa_debug -bool YES` is set.
#pragma once
#import <Foundation/Foundation.h>

// Install every hook that is not yet installed. Cheap once finished; called
// from the maintenance tick until the game's classes have loaded.
void pkInstallHooks(void);

// While set, PikminCameraController.SetTarget is swallowed so automated
// feeds/harvests do not yank the camera.
void pkSetCameraSuppress(BOOL suppress);
