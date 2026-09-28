#import "Frame.h"

static int gDepth = 0;
static NSMutableArray<void (^)(void)> *gResets = nil;

void pkFrameOnReset(void (^reset)(void)) {
    if (!gResets) gResets = [NSMutableArray array];
    [gResets addObject:[reset copy]];
}
void pkFrameBegin(void) { gDepth++; }
BOOL pkFrameActive(void) { return gDepth > 0; }
void pkFrameEnd(void) {
    if (gDepth <= 0) return;
    if (--gDepth == 0) for (void (^r)(void) in gResets) r();
}
