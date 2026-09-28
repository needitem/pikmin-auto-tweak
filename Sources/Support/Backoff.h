// Per-key resend gate. Every pass that fires-and-forgets an RPC must not
// re-send the same target before the game has had time to answer, and must
// back off when the answer is "no". One implementation for all of them.
//
//   wait after the n-th send = min(base * factor^(n-1), max)
//
// A send recorded with a `signature` resets the attempt counter whenever the
// signature differs from the previous send's — i.e. whenever the target's
// observable state moved, meaning the last request had an effect.
#pragma once
#import <Foundation/Foundation.h>

@interface PKBackoff : NSObject
- (instancetype)initWithBase:(NSTimeInterval)base factor:(double)factor max:(NSTimeInterval)max;
- (BOOL)ready:(NSString *)key;
- (void)recordSend:(NSString *)key;
- (void)recordSend:(NSString *)key signature:(NSString *)signature;
- (int)tries:(NSString *)key;
- (NSTimeInterval)waitFor:(NSString *)key;
// Forget every key not in `alive` (targets that no longer exist).
- (void)pruneKeeping:(NSSet<NSString *> *)alive;
@end
