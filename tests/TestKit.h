// A very small test harness: CHECK(cond) counts and reports, nothing aborts.
#pragma once
#import <Foundation/Foundation.h>
#import "Roster.h"

extern int gChecks, gFailures;
#define CHECK(cond) do { gChecks++; if (!(cond)) { gFailures++; fprintf(stderr, "  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { long long _a = (long long)(a), _b = (long long)(b); gChecks++; \
    if (_a != _b) { gFailures++; fprintf(stderr, "  FAIL %s:%d  %s == %s  (%lld vs %lld)\n", __FILE__, __LINE__, #a, #b, _a, _b); } } while (0)

// One Pikmin snapshot, the way the roster would hand it over.
PKPikmin *pikmin(NSString *pid, int color, float hearts, BOOL decor, int status);
