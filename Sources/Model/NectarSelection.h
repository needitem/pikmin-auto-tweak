// Which nectar stack the player means to spend: a hand feed reveals it (the hook
// notes it, see Game/HandFed), and so does the nectar reel's current pick. The feed pass reads the result as a pinned
// stack in the settings.
#pragma once
#import <Foundation/Foundation.h>

// Pin the special nectar to spend from the player's own choices (hand feed +
// the reel selection). Main thread; call before reading the pin.
void pkNectarSyncSelection(void);
