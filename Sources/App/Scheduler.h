// Decides WHEN each pass runs. Nothing else in the tweak owns a timer for
// automation (the numbering queue's rename pacing aside).
#pragma once
#import <Foundation/Foundation.h>
#import "Feature.h"

// Main thread only. Idempotent.
void pkSchedulerStart(void);

// Run whatever is due. Throttled, so any number of drivers (timer, location
// fixes) may call it without double-firing.
void pkSchedulerTick(void);

// NO for a few seconds after the main thread was seen running late. Requests
// that would pile on top of a stall wait for it (see RpcClient's pacing).
BOOL pkMainThreadCalm(void);

