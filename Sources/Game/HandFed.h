// The nectar the player just fed by hand, as the feed hook saw it. The hook runs
// inside the game on any thread, so it only copies the item id's UTF-16 into a
// fixed buffer under a short lock — no allocation, no il2cpp call. The string
// object is made later, on the main thread, by whoever takes it.
#pragma once
#import <Foundation/Foundation.h>

void pkNoteHandFedRaw(void *il2cppItemIdString);      // from a hook (any thread)
NSString *pkTakeHandFed(void);                        // main thread: the last noted id, once; nil if none
