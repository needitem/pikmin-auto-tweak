// Which nectar stack the player means to spend: a hand feed reveals it, and so
// does the nectar reel's current pick. The feed pass reads the result as a pinned
// stack in the settings.
#pragma once
#import <Foundation/Foundation.h>

// From a hook (any thread): the nectar item id the player just fed by hand, copied
// as raw UTF-16 — no allocation, no il2cpp call. The feed pass picks it up.
void pkNoteHandFedRaw(void *il2cppItemIdString);

// Pin the special nectar to spend from the player's own choices (hand feed +
// the reel selection). Main thread; call before reading the pin.
void pkNectarSyncSelection(void);
