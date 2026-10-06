// The smallest n in 1…count for which `pass(n)` holds, when passing is monotonic
// (once it holds for n it holds for every larger n). `pass(count)` is assumed to
// hold already — the caller knows that — so it is never asked.
//
// ceil(log2(count)) probes instead of up to `count`: matters when every probe is
// a write to live game state (a party of Pikmin, one more at a time).
#pragma once
#import <Foundation/Foundation.h>

NSUInteger pkSmallestPassing(NSUInteger count, BOOL (^pass)(NSUInteger n));
