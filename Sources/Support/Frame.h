// A "frame" is one synchronous stretch of automation work on the main thread
// (a scheduler tick, or a pass run from a switch). Readers of game state may
// cache their result for the length of a frame so that several passes in the
// same tick share one scan, and MUST drop it when the frame ends: anything
// holding game pointers is valid only inside the frame that produced it.
//
// Outside a frame nothing is cached. Frames nest; the outermost end resets.
#pragma once
#import <Foundation/Foundation.h>

void pkFrameBegin(void);
void pkFrameEnd(void);
BOOL pkFrameActive(void);

// Register a reset block (call once per cache, e.g. from dispatch_once).
void pkFrameOnReset(void (^reset)(void));
