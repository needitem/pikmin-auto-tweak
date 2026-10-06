// Decides whether the automation may do work right now, from how the main
// thread has been behaving. The game answers every request on its main thread,
// so piling work onto a thread that is already late is what froze it.
//
//  * The first kStartupQuiet seconds after launch belong to the game loading.
//  * When the 1 s timer fires more than kStallThreshold late, the main thread
//    is busy: hold off for kCalmHold. Held ticks pile up for at most kMaxHold in
//    a row — after that work runs regardless, so a permanently busy game cannot
//    starve the passes.
//  * After the quiet period, and after a stay in the background, every pass is
//    overdue; the caller is told once (pkGovernorTakeRestagger) to spread their
//    next runs instead of running them all in one tick.
//
// Pure state machine: every call takes the time it happened at, so it is
// testable without a clock (tests/test_governor.mm). Main thread only.
#pragma once
#import <Foundation/Foundation.h>

void pkGovernorStart(NSTimeInterval now);
void pkGovernorNoteTimer(NSTimeInterval now);          // the 1 s timer fired
void pkGovernorNoteInactive(void);                     // the app is not in front: a later resume is not a stall
void pkGovernorRequestRestagger(void);                 // e.g. the scheduler saw a long gap between ticks

BOOL pkGovernorCalm(NSTimeInterval now);               // no stall seen in the last kCalmHold
BOOL pkGovernorAllowWork(NSTimeInterval now);          // startup quiet and hold-off; counts a held tick when it says NO
BOOL pkGovernorTakeRestagger(void);                    // YES once after start / a resume

typedef struct { double lateMaxMs; int over100, over500, heldTicks; } PKGovernorStats;
PKGovernorStats pkGovernorTakeStats(void);             // since the previous call, then reset
