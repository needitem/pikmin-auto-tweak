#import "HandFed.h"
#import "Runtime.h"
#import <os/lock.h>

static const int kFedCap = 96;
static os_unfair_lock gFedLock = OS_UNFAIR_LOCK_INIT;
static unichar gFedChars[kFedCap];
static int gFedLen = 0;

void pkNoteHandFedRaw(void *il2cppItemIdString) {
    unichar tmp[kFedCap];
    int n = pkStrCopy(il2cppItemIdString, tmp, kFedCap);
    if (n <= 0) return;
    os_unfair_lock_lock(&gFedLock);
    memcpy(gFedChars, tmp, (size_t)n * sizeof(unichar));
    gFedLen = n;
    os_unfair_lock_unlock(&gFedLock);
}

NSString *pkTakeHandFed(void) {
    unichar tmp[kFedCap];
    os_unfair_lock_lock(&gFedLock);
    int n = gFedLen;
    memcpy(tmp, gFedChars, (size_t)n * sizeof(unichar));
    gFedLen = 0;
    os_unfair_lock_unlock(&gFedLock);
    return n > 0 ? [NSString stringWithCharacters:tmp length:(NSUInteger)n] : nil;
}
