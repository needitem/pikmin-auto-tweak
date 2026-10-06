// Method hooks. A hook runs inside the game, on whatever thread made the call,
// so it does the least possible: remember a singleton's pointer (and note a hand
// feed, and swallow one camera move). No lock beyond a tiny one, no allocation, no
// il2cpp call, no logging; everything else happens later on the main thread.
#pragma once
#import <Foundation/Foundation.h>

// Install every hook that is not yet installed. Cheap once finished; called
// from the maintenance tick until the game's classes have loaded.
void pkInstallHooks(void);

// "name calls, …" per hook since the previous call, busiest first (heartbeat).
NSString *pkHookStats(void);

// While set, PikminCameraController.SetTarget is swallowed so automated
// feeds/harvests do not yank the camera.
void pkSetCameraSuppress(BOOL suppress);
