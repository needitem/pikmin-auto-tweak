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

// Feature switches (one per automation pass).
extern NSString * const kKeyFeed;        // pa_feed        정수
extern NSString * const kKeyHarvest;     // pa_harvest     수확
extern NSString * const kKeyCollect;     // pa_collect     수집
extern NSString * const kKeyExpedition;  // pa_expedition  탐험
extern NSString * const kKeyPlant;       // pa_plant       심기
extern NSString * const kKeyPoi;         // pa_poi         큰꽃
extern NSString * const kKeySeed;        // pa_seed        모종
extern NSString * const kKeyTroop;       // pa_troop       부대
extern NSString * const kKeyNumber;      // pa_number      번호

// Non-feature keys.
extern NSString * const kSettingDebug;        // pa_debug: install request-logging hooks
extern NSString * const kSettingCamSuppress;  // pa_camsuppress: keep the camera still while automating
extern NSString * const kSettingFps;          // pa_fps: frame-rate cap while automating
extern NSString * const kSettingSpecial;      // pa_special: pinned special-nectar flower name
extern NSString * const kSettingSpecialId;    // pa_special_id: pinned special-nectar stack id
