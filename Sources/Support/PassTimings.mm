#import "PassTimings.h"
#import "Clock.h"

static NSMutableDictionary<NSString *, NSNumber *> *gMs, *gCalls;

void pkTimingNote(NSString *name, NSTimeInterval seconds) {
    if (!gMs) { gMs = [NSMutableDictionary dictionary]; gCalls = [NSMutableDictionary dictionary]; }
    gMs[name] = @(gMs[name].doubleValue + seconds * 1000.0);
    gCalls[name] = @(gCalls[name].intValue + 1);
}

NSString *pkTimed(NSString *name, NSString *(^body)(void)) {
    NSTimeInterval t0 = pkMono();
    NSString *r = body();
    pkTimingNote(name, pkMono() - t0);
    return r;
}

NSString *pkTimingsTake(void) {
    if (!gCalls.count) return @"-";
    NSMutableArray *bits = [NSMutableArray array];
    for (NSString *k in [gCalls.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [bits addObject:[NSString stringWithFormat:@"%@ %.0f/%d", k, gMs[k].doubleValue, gCalls[k].intValue]];
    [gMs removeAllObjects]; [gCalls removeAllObjects];
    return [bits componentsJoinedByString:@" "];
}
