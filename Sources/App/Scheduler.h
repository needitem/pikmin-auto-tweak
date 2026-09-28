// Decides WHEN each pass runs. Nothing else in the tweak owns a timer for
// automation (the numbering queue's rename pacing aside).
#pragma once
#import <Foundation/Foundation.h>
#import "Feature.h"

// Posted (main thread) whenever a switch changes, so the UI can redraw.
extern NSString * const PKFeaturesChangedNotification;

// Main thread only. Idempotent.
void pkSchedulerStart(void);

// Run whatever is due. Throttled, so any number of drivers (timer, location
// fixes) may call it without double-firing.
void pkSchedulerTick(void);

void pkFeatureSetEnabled(PKFeature *feature, BOOL on);
BOOL pkAutoEnabled(void);                 // every 자동성장 feature is on
void pkAutoSetEnabled(BOOL on);
