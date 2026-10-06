// The tweak's persisted switches and pins (NSUserDefaults). Bools are cached
// in memory: the scheduler asks ten times a second.
#pragma once
#import <Foundation/Foundation.h>

@interface PKSettings : NSObject
+ (void)registerDefaults;
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;   // nil removes
+ (NSInteger)integerForKey:(NSString *)key;
@end

// Keys. Every automation pass always runs; these only tune behaviour.
extern NSString * const kSettingDebug;        // pa_debug: install request-logging hooks
extern NSString * const kSettingCamSuppress;  // pa_camsuppress: keep the camera still while automating
extern NSString * const kSettingFps;          // pa_fps: frame-rate cap while automating (0/unset = none)
extern NSString * const kSettingSpecial;      // pa_special: pinned special-nectar flower name
extern NSString * const kSettingSpecialId;    // pa_special_id: pinned special-nectar stack id
