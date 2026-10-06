#import "FeedPlan.h"

const int kFeedIdsPerRequest = 5;

@implementation PKFeedBatch
@end

void pkSortByBalls(NSMutableArray<PKNectar *> *a) {
    [a sortUsingComparator:^NSComparisonResult(PKNectar *x, PKNectar *y) {
        if (x.balls != y.balls) return x.balls > y.balls ? NSOrderedAscending : NSOrderedDescending;
        return [x.itemId compare:y.itemId];
    }];
}

void pkPromotePinned(NSMutableArray<PKNectar *> *special, NSString *wantId, NSString *want) {
    for (PKNectar *h in [special copy]) {
        BOOL hit = wantId.length && [h.itemId isEqualToString:wantId];
        if (!hit && want.length && !wantId.length)
            hit = [h.kindName caseInsensitiveCompare:want] == NSOrderedSame || [@(h.hkind).stringValue isEqualToString:want];
        if (hit) { [special removeObject:h]; [special insertObject:h atIndex:0]; break; }
    }
}

NSArray<PKNectar *> *pkBudStacks(NSArray<PKNectar *> *special, NSArray<PKNectar *> *plain, NSSet<NSString *> *capped,
                                 NSString *(^bucketOf)(PKNectar *), NSArray<NSString *> **heldOut, BOOL *plainInstead) {
    NSMutableArray<PKNectar *> *stacks = [NSMutableArray array];
    NSMutableArray<NSString *> *held = [NSMutableArray array];
    void (^addUsable)(NSArray<PKNectar *> *) = ^(NSArray<PKNectar *> *candidates) {
        for (PKNectar *h in candidates) {
            NSString *bucket = bucketOf ? bucketOf(h) : nil;
            if (bucket && [capped containsObject:bucket]) {
                [held addObject:[NSString stringWithFormat:@"%@(색%d)", h.kindName.length ? h.kindName : @"일반", h.type]];
                continue;
            }
            [stacks addObject:h];
        }
    };
    addUsable(special);
    BOOL instead = NO;
    if (!stacks.count) { instead = special.count > 0; addUsable(plain); }
    if (heldOut) *heldOut = held;
    if (plainInstead) *plainInstead = instead;
    return stacks;
}

NSArray<PKFeedBatch *> *pkFeedAllocate(NSArray<NSString *> *targets, NSArray<PKNectar *> *stacks,
                                       NSMutableDictionary<NSString *, NSNumber *> *remaining) {
    NSMutableArray<PKFeedBatch *> *out = [NSMutableArray array];
    NSUInteger next = 0;
    for (PKNectar *stack in stacks) {
        while (next < targets.count && remaining[stack.itemId].intValue > 0) {
            NSUInteger n = MIN((NSUInteger)kFeedIdsPerRequest, MIN(targets.count - next, (NSUInteger)remaining[stack.itemId].intValue));
            PKFeedBatch *b = [PKFeedBatch new];
            b.itemId = stack.itemId;
            b.pids = [targets subarrayWithRange:NSMakeRange(next, n)];
            [out addObject:b];
            remaining[stack.itemId] = @(remaining[stack.itemId].intValue - (int)n);
            next += n;
        }
    }
    return out;
}
