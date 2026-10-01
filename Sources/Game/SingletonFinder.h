// Finds game singletons the hooks have not caught yet.
//
// A hook only captures an instance when the game happens to call the hooked
// method — a PikminManager that nobody touches after the map loads is never
// seen, and every pass that needs it stays idle. The game's objects, though,
// are wired together by dependency injection, so an instance we already hold
// usually references the ones we are missing. This walks the reference fields
// of the captured singletons (two levels deep) and adopts any object whose class
// is one we still lack.
#pragma once
#import <Foundation/Foundation.h>

// Cheap when nothing is missing. Main thread; needs the il2cpp bridge armed.
// Returns YES when a walk actually ran (the caller times those).
BOOL pkResolveSingletons(void);
