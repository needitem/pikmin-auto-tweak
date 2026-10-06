#import "Settings.h"
#import <os/lock.h>


NSString * const kSettingDebug       = @"pa_debug";
NSString * const kSettingCamSuppress = @"pa_camsuppress";
NSString * const kSettingFps         = @"pa_fps";
NSString * const kSettingSpecial     = @"pa_special";
NSString * const kSettingSpecialId   = @"pa_special_id";

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *gBools;

@implementation PKSettings

+ (void)registerDefaults {
    os_unfair_lock_lock(&gLock);
    [gBools removeAllObjects];        // anything read before the defaults existed is stale
    os_unfair_lock_unlock(&gLock);
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kSettingCamSuppress: @YES,
    }];
}

+ (BOOL)boolForKey:(NSString *)key {
    os_unfair_lock_lock(&gLock);
    if (!gBools) gBools = [NSMutableDictionary dictionary];
    NSNumber *n = gBools[key];
    if (!n) { n = @([[NSUserDefaults standardUserDefaults] boolForKey:key]); gBools[key] = n; }
    os_unfair_lock_unlock(&gLock);
    return n.boolValue;
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    os_unfair_lock_lock(&gLock);
    if (!gBools) gBools = [NSMutableDictionary dictionary];
    gBools[key] = @(value);
    os_unfair_lock_unlock(&gLock);
}

+ (NSString *)stringForKey:(NSString *)key { return [[NSUserDefaults standardUserDefaults] stringForKey:key]; }

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    if (value) [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

+ (NSInteger)integerForKey:(NSString *)key { return [[NSUserDefaults standardUserDefaults] integerForKey:key]; }

@end
