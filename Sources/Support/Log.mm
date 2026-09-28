#import "Log.h"
#import "Clock.h"
#import <fcntl.h>
#import <os/lock.h>
#import <sys/stat.h>
#import <unistd.h>

static const off_t kLogMaxBytes = 1024 * 1024;   // rotate to pa.log.1 past this

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static int gFd = -1;
static off_t gSize = 0;
static NSString *gPath = nil;

// All below: gLock held.
static void openLog(void) {
    if (!gPath)
        gPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                 stringByAppendingPathComponent:@"pa.log"];
    gFd = open(gPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    struct stat st;
    gSize = (gFd >= 0 && fstat(gFd, &st) == 0) ? st.st_size : 0;
}

static void emit(NSString *body) {
    if (gFd < 0) openLog();
    if (gFd < 0) return;
    if (gSize > kLogMaxBytes) {
        close(gFd); gFd = -1;
        NSString *old = [gPath stringByAppendingString:@".1"];
        rename(gPath.fileSystemRepresentation, old.fileSystemRepresentation);
        openLog();
        if (gFd < 0) return;
    }
    NSString *line = [NSString stringWithFormat:@"%.3f %@\n", [NSDate date].timeIntervalSince1970, body];
    const char *u = line.UTF8String;
    ssize_t w = write(gFd, u, strlen(u));
    if (w > 0) gSize += w;
}

void PALOG(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    os_unfair_lock_lock(&gLock);
    emit(body);
    os_unfair_lock_unlock(&gLock);
}

void pkLogEmitC(NSString *key, NSString *msg) {
    static NSMutableDictionary<NSString *, NSString *> *lastMsg;
    static NSMutableDictionary<NSString *, NSNumber *> *lastAt;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    os_unfair_lock_lock(&gLock);
    if (!lastMsg) { lastMsg = [NSMutableDictionary dictionary]; lastAt = [NSMutableDictionary dictionary]; }
    BOOL skip = [lastMsg[key] isEqualToString:msg] && now - lastAt[key].doubleValue < 180.0;
    if (!skip) {
        lastMsg[key] = msg; lastAt[key] = @(now);
        emit(msg);
    }
    os_unfair_lock_unlock(&gLock);
}

static const NSTimeInterval kMinEvalGap = 2.0;

BOOL pkLogAllow(NSString *key) {
    static NSMutableDictionary<NSString *, NSNumber *> *evalAt;
    NSTimeInterval now = pkMono();
    os_unfair_lock_lock(&gLock);
    if (!evalAt) evalAt = [NSMutableDictionary dictionary];
    BOOL ok = now - evalAt[key].doubleValue >= kMinEvalGap;
    if (ok) evalAt[key] = @(now);
    os_unfair_lock_unlock(&gLock);
    return ok;
}
