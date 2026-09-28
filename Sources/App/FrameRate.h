// Keep the game from cooking the phone while it plays itself.
//
// The automation's own cost is negligible (~50 ms of CPU a minute across
// every pass); the heat is Unity rendering a map nobody is watching at the
// platform frame rate. Application.targetFrameRate caps that, and vSyncCount
// must be 0 or the cap is ignored.
//
// While automating: cap at `pa_fps` (default 20, clamped 5..60) and turn vSync
// off, remembering the game's vSync. When automation stops: targetFrameRate
// back to the platform default (-1) and vSync restored. Safe to call often —
// the game resets the cap across scene changes, so it is re-asserted.
#pragma once
#import <Foundation/Foundation.h>

void pkApplyFrameRate(BOOL automating);
