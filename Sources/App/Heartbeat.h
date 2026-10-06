// The once-a-minute status lines in pa.log:
//   [hb]   what is captured, location, thermal state, battery, time per pass
//   [hb2]  CPU per thread, hook call rates, requests per minute, the send queue,
//          and how late the main thread ran
// Everything it prints is read from the module that owns it; it keeps no state
// of its own beyond counting calls.
#pragma once
#import <Foundation/Foundation.h>

// Call once a second; every 60th call writes the lines.
void pkHeartbeatBeat(void);
