// The one-second housekeeping that keeps the tweak attached to the game:
// notes how late the timer fired (for the Governor), installs hooks whose classes
// have loaded since, adopts the singletons the hooks saw, finds the ones they
// have not, and lets the heartbeat count. Does nothing while the app is not in
// front.
#pragma once
#import <Foundation/Foundation.h>

void pkMaintenanceTick(void);
