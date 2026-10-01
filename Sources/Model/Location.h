// Where the game believes the player is: whatever CoreLocation (or a GPS
// spoofing tweak underneath it) reports. Foreground only: updates stop when the
// app goes to the background and resume when it returns, and nothing here keeps
// the process alive.
#pragma once
#import <Foundation/Foundation.h>

// Start the session. `onFix` runs on the main thread for every location fix.
void pkLocationStart(void (^onFix)(void));

BOOL pkLocationGet(double *lat, double *lng);   // last fix, NO if none yet
NSTimeInterval pkLocationAge(void);             // seconds since it, huge if none
unsigned long pkLocationCount(void);
