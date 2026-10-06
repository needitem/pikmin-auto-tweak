// Whether the app is in front. Automation runs only then; nothing keeps the
// process alive in the background.
#pragma once
#import <UIKit/UIKit.h>

static inline BOOL pkAppActive(void) { return [UIApplication sharedApplication].applicationState == UIApplicationStateActive; }
