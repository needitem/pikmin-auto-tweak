// How long each unit of work actually takes; without it, tuning cadences is
// guesswork. The heartbeat reports "name total-ms/calls" and resets.
#pragma once
#import <Foundation/Foundation.h>

void pkTimingNote(NSString *name, NSTimeInterval seconds);
NSString *pkTimed(NSString *name, NSString *(^body)(void));   // runs `body`, notes its duration, returns its result
NSString *pkTimingsTake(void);                                 // "a 12/3 b 4/1" since the previous call; "-" if none
