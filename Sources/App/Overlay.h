// The on-screen handle and switch panel. Presentation only: it reads the
// feature registry, calls the scheduler's setters, and redraws when told.
#pragma once
#import <Foundation/Foundation.h>

// Creates the overlay window once a scene exists. Main thread. Returns
// whether it exists now.
BOOL pkOverlayEnsure(void);
