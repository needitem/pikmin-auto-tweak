// The two global switches the automation flips on the game: keep the camera
// still while passes act, and (optionally) cap the frame rate. Re-applied every
// so often because the game resets the frame cap across scenes.
#pragma once
#import <Foundation/Foundation.h>

void pkSyncSideEffects(void);
