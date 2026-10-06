// The feed pass's decisions, as pure functions over plain values: which nectar
// stacks the buds may take, and how a group of Pikmin is handed out to stacks
// without ever spending more than a stack holds. The pass reads the game, calls
// these, and sends what they return.
#pragma once
#import <Foundation/Foundation.h>
#import "Nectar.h"

extern const int kFeedIdsPerRequest;            // the shape the game's own feed uses: five ids a request

@interface PKFeedBatch : NSObject               // one request: these Pikmin, one item each, from this stack
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, copy) NSArray<NSString *> *pids;
@end

// Most held first, the id as the tie-break so the order is stable.
void pkSortByBalls(NSMutableArray<PKNectar *> *stacks);

// Which special nectar to spend first. The game keeps the reel choice in the UI
// only, so the pinned stack — else the pinned flower name or kind number — goes
// first; otherwise the kind we hold most of (the order given).
void pkPromotePinned(NSMutableArray<PKNectar *> *special, NSString *pinnedId, NSString *pinnedKind);

// The stacks buds and leaves may take: special nectar, except a stack whose
// flower's petals are at the cap (the harvest would only overflow); plain when
// no special stack is left — which also covers holding none. `bucketOf` names a
// stack's petal bucket (nil = none to be capped). `held` lists what was held
// back, `plainInstead` says plain stands in because special was held back.
NSArray<PKNectar *> *pkBudStacks(NSArray<PKNectar *> *special, NSArray<PKNectar *> *plain, NSSet<NSString *> *cappedBuckets,
                                 NSString *(^bucketOf)(PKNectar *), NSArray<NSString *> **held, BOOL *plainInstead);

// Hand `targetPids` out to `stacks` in order, five a request, one item each,
// spending from `remaining` (itemId -> count left; shared by every group fed in a
// pass, so a stack is never spent twice). Fewer targets or less nectar than there
// are of the other simply ends the list.
NSArray<PKFeedBatch *> *pkFeedAllocate(NSArray<NSString *> *targetPids, NSArray<PKNectar *> *stacks,
                                       NSMutableDictionary<NSString *, NSNumber *> *remaining);
