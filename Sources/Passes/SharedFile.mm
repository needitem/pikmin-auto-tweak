#import "SharedFile.h"

// Rootless jailbreak path shared with the GPS Wander tweak.
static NSString * const kSharedDir = @"/var/jb/var/mobile/Library/GPSWander";

BOOL pkWriteShared(NSString *fileName, NSData *data) {
    NSString *shared = [kSharedDir stringByAppendingPathComponent:fileName];
    if ([data writeToFile:shared options:NSDataWritingAtomic error:nil]) return YES;
    NSString *docs = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:fileName];
    [data writeToFile:docs options:NSDataWritingAtomic error:nil];
    return NO;
}
