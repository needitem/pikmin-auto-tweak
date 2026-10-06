#import "TestKit.h"
#import "FeedPlan.h"

static NSArray<NSString *> *pids(int n) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < n; i++) [a addObject:[NSString stringWithFormat:@"p%02d", i]];
    return a;
}

void test_feed_sort_by_balls(void) {
    NSMutableArray *a = [NSMutableArray arrayWithObjects:nectar(@"b", 10, 1, nil, 5), nectar(@"a", 10, 1, nil, 5), nectar(@"c", 50, 1, nil, 5), nil];
    pkSortByBalls(a);
    CHECK([[a valueForKey:@"itemId"] isEqualToArray:(@[ @"c", @"a", @"b" ])]);      // most first, id breaks the tie
}

void test_feed_promote_pinned(void) {
    PKNectar *rose = nectar(@"rose1", 5, 1, @"rose", 12), *canna = nectar(@"canna1", 9, 2, @"canna", 54), *lily = nectar(@"lily1", 20, 3, @"lily", 7);
    NSMutableArray *s = [NSMutableArray arrayWithObjects:lily, canna, rose, nil];
    pkPromotePinned(s, @"rose1", nil);                                              // by stack id
    CHECK([s[0] isEqual:rose]);
    s = [NSMutableArray arrayWithObjects:lily, canna, rose, nil];
    pkPromotePinned(s, nil, @"CANNA");                                              // by flower name, any case
    CHECK([s[0] isEqual:canna]);
    s = [NSMutableArray arrayWithObjects:lily, canna, rose, nil];
    pkPromotePinned(s, nil, @"12");                                                 // by kind number
    CHECK([s[0] isEqual:rose]);
    s = [NSMutableArray arrayWithObjects:lily, canna, rose, nil];
    pkPromotePinned(s, @"missing", @"canna");                                       // an id is pinned but absent: the name is ignored
    CHECK([s[0] isEqual:lily]);
    s = [NSMutableArray arrayWithObjects:lily, canna, rose, nil];
    pkPromotePinned(s, nil, nil);                                                   // nothing pinned: the order stays
    CHECK([[s valueForKey:@"itemId"] isEqualToArray:(@[ @"lily1", @"canna1", @"rose1" ])]);
}

// Buds take special nectar, except stacks whose petals are at the cap.
void test_feed_bud_stacks(void) {
    PKNectar *ok = nectar(@"ok", 5, 1, @"rose", 12), *full = nectar(@"full", 9, 2, @"canna", 54), *plainA = nectar(@"plainA", 100, 1, nil, 5);
    NSString *(^bucket)(PKNectar *) = ^NSString *(PKNectar *n) { return n.type == 2 ? @"canna-bucket" : @"rose-bucket"; };
    NSSet *capped = [NSSet setWithObject:@"canna-bucket"];
    NSArray *held = nil; BOOL instead = YES;
    NSArray *stacks = pkBudStacks(@[ ok, full ], @[ plainA ], capped, bucket, &held, &instead);
    CHECK([stacks isEqualToArray:@[ ok ]]);
    CHECK_EQ(held.count, 1);
    CHECK([held[0] isEqualToString:@"canna(색2)"]);
    CHECK(!instead);
}

// Every special stack capped: plain nectar stands in (this fallback is what unblocked 55 unfed buds).
void test_feed_bud_stacks_fallback_to_plain(void) {
    PKNectar *full1 = nectar(@"f1", 9, 2, @"canna", 54), *full2 = nectar(@"f2", 4, 4, @"lisianthus", 55), *plainA = nectar(@"plainA", 100, 1, nil, 5);
    NSSet *capped = [NSSet setWithObjects:@"b2", @"b4", nil];
    NSString *(^bucket)(PKNectar *) = ^NSString *(PKNectar *n) { return n.type == 2 ? @"b2" : n.type == 4 ? @"b4" : @"b1"; };
    NSArray *held = nil; BOOL instead = NO;
    NSArray *stacks = pkBudStacks(@[ full1, full2 ], @[ plainA ], capped, bucket, &held, &instead);
    CHECK([stacks isEqualToArray:@[ plainA ]]);
    CHECK(instead);
    CHECK_EQ(held.count, 2);
    // plain stacks are capped too: nothing left, but still told that plain stood in
    PKNectar *plainFull = nectar(@"plainFull", 100, 2, nil, 5);
    NSArray *none = pkBudStacks(@[ full1 ], @[ plainFull ], capped, bucket, &held, &instead);
    CHECK_EQ(none.count, 0);
    CHECK(instead);
    // no special nectar at all: plain is the normal choice, not a substitute
    NSArray *normal = pkBudStacks(@[], @[ plainA ], capped, bucket, &held, &instead);
    CHECK([normal isEqualToArray:@[ plainA ]]);
    CHECK(!instead);
}

// Five a request, never more than a stack holds.
void test_feed_allocate_respects_budget_and_batch_size(void) {
    PKNectar *a = nectar(@"A", 7, 1, nil, 5), *b = nectar(@"B", 100, 1, nil, 5);
    NSMutableDictionary *rem = [@{ @"A": @7, @"B": @100 } mutableCopy];
    NSArray<PKFeedBatch *> *batches = pkFeedAllocate(pids(12), @[ a, b ], rem);
    NSMutableArray *shape = [NSMutableArray array];
    for (PKFeedBatch *x : batches) [shape addObject:[NSString stringWithFormat:@"%@%lu", x.itemId, (unsigned long)x.pids.count]];
    CHECK([shape isEqualToArray:(@[ @"A5", @"A2", @"B5" ])]);                       // A has 7: 5 then 2; the rest from B
    CHECK_EQ([rem[@"A"] intValue], 0);
    CHECK_EQ([rem[@"B"] intValue], 95);
    // every Pikmin once, in order
    NSMutableArray *all = [NSMutableArray array]; for (PKFeedBatch *x in batches) [all addObjectsFromArray:x.pids];
    CHECK([all isEqualToArray:pids(12)]);
}

// The budget is shared by every group fed in one pass: what the buds took is gone for the flowers.
void test_feed_allocate_shared_budget(void) {
    PKNectar *a = nectar(@"A", 8, 1, nil, 5);
    NSMutableDictionary *rem = [@{ @"A": @8 } mutableCopy];
    NSArray *first = pkFeedAllocate(pids(6), @[ a ], rem);                          // buds: 5 + 1
    NSUInteger n1 = 0; for (PKFeedBatch *x in first) n1 += x.pids.count;
    CHECK_EQ(n1, 6);
    NSArray *second = pkFeedAllocate(pids(6), @[ a ], rem);                         // flowers: only 2 left
    NSUInteger n2 = 0; for (PKFeedBatch *x in second) n2 += x.pids.count;
    CHECK_EQ(n2, 2);
    CHECK_EQ([rem[@"A"] intValue], 0);
}

void test_feed_allocate_edges(void) {
    PKNectar *empty = nectar(@"E", 0, 1, nil, 5), *a = nectar(@"A", 3, 1, nil, 5);
    NSMutableDictionary *rem = [@{ @"E": @0, @"A": @3 } mutableCopy];
    NSArray *b = pkFeedAllocate(pids(10), @[ empty, a ], rem);                      // an empty stack is skipped
    CHECK_EQ(b.count, 1);
    CHECK([[b[0] itemId] isEqualToString:@"A"]);
    CHECK_EQ([[b[0] pids] count], 3);
    CHECK_EQ(pkFeedAllocate(@[], @[ a ], [@{ @"A": @3 } mutableCopy]).count, 0);   // nobody to feed
    CHECK_EQ(pkFeedAllocate(pids(3), @[], [NSMutableDictionary dictionary]).count, 0);   // nothing to feed with
}
