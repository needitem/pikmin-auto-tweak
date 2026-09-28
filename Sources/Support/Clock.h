// Two clocks, never mixed:
//  - pkMono(): monotonic seconds, for every throttle/cooldown. Immune to the
//    user (or NTP) moving the wall clock, which used to freeze passes.
//  - pkWallMs(): wall-clock milliseconds, only for comparing against server
//    timestamps carried in game protos.
#pragma once
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

static inline NSTimeInterval pkMono(void) { return CACurrentMediaTime(); }
static inline long long pkWallMs(void) { return (long long)([NSDate date].timeIntervalSince1970 * 1000.0); }
