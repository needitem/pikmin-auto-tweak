// Decides WHEN each pass runs: the tick that walks the feature registry and runs
// what is due. Whether work is allowed at all right now is the Governor's call;
// the one-second housekeeping is Maintenance; the status lines are Heartbeat.
#pragma once
#import <Foundation/Foundation.h>
#import "Feature.h"

// Main thread only. Idempotent.
void pkSchedulerStart(void);

// Run whatever is due. Throttled, so any number of drivers (timer, location
// fixes) may call it without double-firing.
void pkSchedulerTick(void);
