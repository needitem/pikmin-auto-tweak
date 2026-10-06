#import "Governor.h"

static const NSTimeInterval kStartupQuiet = 75.0;
static const double kStallThreshold = 0.2;
static const NSTimeInterval kCalmHold = 3.0, kMaxHold = 15.0;

static NSTimeInterval gStartedAt, gCalmAfter, gLastFire, gHeldSince;
static BOOL gRestagger;
static double gLateMax;
static int gOver100, gOver500, gHeld;

void pkGovernorStart(NSTimeInterval now) {
    gStartedAt = now; gCalmAfter = 0; gLastFire = 0; gHeldSince = 0;
    gRestagger = YES;
    gLateMax = 0; gOver100 = gOver500 = gHeld = 0;
}

void pkGovernorNoteTimer(NSTimeInterval now) {
    if (gLastFire > 0) {
        double late = now - gLastFire - 1.0;               // the timer repeats every 1 s
        if (late < 30) {                                   // a resume from the background is not a stall
            gLateMax = MAX(gLateMax, late);
            if (late > kStallThreshold) gCalmAfter = now + kCalmHold;
            if (late > 0.1) gOver100++;
            if (late > 0.5) gOver500++;
        }
    }
    gLastFire = now;
}

void pkGovernorNoteInactive(void) { gLastFire = 0; }
void pkGovernorRequestRestagger(void) { gRestagger = YES; }
BOOL pkGovernorCalm(NSTimeInterval now) { return now >= gCalmAfter; }

BOOL pkGovernorAllowWork(NSTimeInterval now) {
    if (now - gStartedAt < kStartupQuiet) return NO;
    if (!pkGovernorCalm(now)) {
        if (!gHeldSince) gHeldSince = now;
        if (now - gHeldSince < kMaxHold) { gHeld++; return NO; }
    }
    gHeldSince = 0;
    return YES;
}

BOOL pkGovernorTakeRestagger(void) {
    BOOL r = gRestagger;
    gRestagger = NO;
    return r;
}

PKGovernorStats pkGovernorTakeStats(void) {
    PKGovernorStats s = { MAX(gLateMax, 0.0) * 1000.0, gOver100, gOver500, gHeld };
    gLateMax = 0; gOver100 = gOver500 = gHeld = 0;
    return s;
}
