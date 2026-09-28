// Files handed to the GPS Wander tweak (and the user): written to its shared
// directory when the sandbox allows it, otherwise into the app's Documents.
#pragma once
#import <Foundation/Foundation.h>

// Returns YES when the shared location took the write.
BOOL pkWriteShared(NSString *fileName, NSData *data);
