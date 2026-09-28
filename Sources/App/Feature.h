// One automation feature: what it is called, how often it runs, and the pass
// that does the work. The registry (Features.mm) is the single place to add
// one; the scheduler and the overlay both derive everything from it.
#pragma once
#import <Foundation/Foundation.h>

@interface PKFeature : NSObject
@property (nonatomic, copy) NSString *key;              // NSUserDefaults key, e.g. pa_feed
@property (nonatomic, copy) NSString *title;            // button label
@property (nonatomic, copy) NSString *tag;              // log tag
@property (nonatomic) NSTimeInterval pace;              // seconds between runs
@property (nonatomic) BOOL inAuto;                      // part of the 자동성장 master switch
@property (nonatomic) BOOL suppressCamera;              // keep the camera still while on
@property (nonatomic) BOOL foregroundOnly;              // never runs while backgrounded
@property (nonatomic, copy) NSString *(^run)(void);
@property (nonatomic) NSTimeInterval lastRun;           // monotonic; scheduler-owned
@property (nonatomic, readonly) BOOL enabled;
@end

NSArray<PKFeature *> *pkFeatures(void);
