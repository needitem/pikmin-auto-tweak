// One automation feature: how often it runs and the pass that does the work.
// The registry (Features.mm) is the single place to add one; every feature
// listed there always runs.
#pragma once
#import <Foundation/Foundation.h>

@interface PKFeature : NSObject
@property (nonatomic, copy) NSString *tag;              // log tag
@property (nonatomic) NSTimeInterval pace;              // seconds between runs
@property (nonatomic) BOOL suppressCamera;              // keep the camera still while on
@property (nonatomic, copy) NSString *(^run)(void);
@property (nonatomic) NSTimeInterval lastRun;           // monotonic; scheduler-owned
@end

NSArray<PKFeature *> *pkFeatures(void);
