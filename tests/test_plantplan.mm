#import "TestKit.h"
#import "PlantPlan.h"

static PKPlantInputs inputs(BOOL live, NSString *ours, NSTimeInterval now, NSTimeInterval lastStart, NSTimeInterval lastStop) {
    PKPlantInputs in = { live, ours, now, lastStart, lastStop };
    return in;
}

void test_plant_biggest_plain(void) {
    NSArray *petals = @[ petal(@"b", 100, NO), petal(@"a", 100, NO), petal(@"big-special", 999, YES), petal(@"c", 40, NO) ];
    CHECK([pkBiggestPlain(petals).itemId isEqualToString:@"a"]);       // special never counts; the lower id breaks the tie
    CHECK(pkBiggestPlain(@[ petal(@"s", 50, YES) ]) == nil);
    CHECK(pkBiggestPlain(@[]) == nil);
    CHECK([pkStackById(petals, @"c").itemId isEqualToString:@"c"]);
    CHECK(pkStackById(petals, @"nope") == nil);
}

// A session we did not start is left alone.
void test_plant_leave_hand_started(void) {
    NSArray *petals = @[ petal(@"a", 100, NO) ];
    CHECK_EQ(pkPlantDecide(petals, inputs(YES, nil, 1000, -1e9, -1e9)).action, PKPlantLeaveAlone);
    CHECK_EQ(pkPlantDecide(petals, inputs(YES, @"", 1000, -1e9, -1e9)).action, PKPlantLeaveAlone);
}

// Our session stays on its stack until another is bigger by the margin.
void test_plant_keep_and_switch(void) {
    NSArray *near = @[ petal(@"a", 100, NO), petal(@"b", 109, NO) ];             // 9 more: not enough
    CHECK_EQ(pkPlantDecide(near, inputs(YES, @"a", 1000, 0, -1e9)).action, PKPlantKeep);
    NSArray *far = @[ petal(@"a", 100, NO), petal(@"b", 110, NO) ];              // exactly the margin
    CHECK_EQ(pkPlantDecide(far, inputs(YES, @"a", 1000, 0, -1e9)).action, PKPlantSwitch);
    CHECK_EQ(kPlantSwitchMargin, 10);
    // already on the biggest: keep
    CHECK_EQ(pkPlantDecide(far, inputs(YES, @"b", 1000, 0, -1e9)).action, PKPlantKeep);
    // our stack is gone from the inventory (all spent): keep, nothing to compare
    CHECK_EQ(pkPlantDecide(@[ petal(@"b", 500, NO) ], inputs(YES, @"a", 1000, 0, -1e9)).action, PKPlantKeep);
}

// Stop is asynchronous: do not repeat the request for 20 s.
void test_plant_switch_waits_after_stop(void) {
    NSArray *far = @[ petal(@"a", 100, NO), petal(@"b", 200, NO) ];
    CHECK_EQ(pkPlantDecide(far, inputs(YES, @"a", 1010, 0, 1000)).action, PKPlantSwitchWait);     // 10 s after
    CHECK_EQ(pkPlantDecide(far, inputs(YES, @"a", 1019.9, 0, 1000)).action, PKPlantSwitchWait);
    CHECK_EQ(pkPlantDecide(far, inputs(YES, @"a", 1020, 0, 1000)).action, PKPlantSwitch);
}

// Not live: nothing plain / nothing plantable / just asked / start.
void test_plant_start_rules(void) {
    NSArray *petals = @[ petal(@"a", 100, NO), petal(@"x", 900, YES) ];
    CHECK_EQ(pkPlantDecide(petals, inputs(NO, nil, 1000, -1e9, -1e9)).action, PKPlantStart);
    CHECK_EQ(pkPlantDecide(petals, inputs(NO, nil, 1000, 950, -1e9)).action, PKPlantStartWait);   // asked 50 s ago
    CHECK_EQ(pkPlantDecide(petals, inputs(NO, nil, 1010, 950, -1e9)).action, PKPlantStart);       // 60 s: free to ask again
    CHECK_EQ(pkPlantDecide(@[ petal(@"x", 900, YES) ], inputs(NO, nil, 1000, -1e9, -1e9)).action, PKPlantNoPlain);   // special is kept
    CHECK_EQ(pkPlantDecide(@[], inputs(NO, nil, 1000, -1e9, -1e9)).action, PKPlantNoPlain);
    CHECK_EQ(pkPlantDecide(@[ petal(@"z", 0, NO) ], inputs(NO, nil, 1000, -1e9, -1e9)).action, PKPlantNoPlain);
}

// A start that never went live is forgotten after 90 s, so its stack id stops counting as "ours".
void test_plant_forget_stale_start(void) {
    NSArray *petals = @[ petal(@"a", 100, NO) ];
    CHECK(!pkPlantDecide(petals, inputs(NO, @"a", 1000, 920, -1e9)).forgetOurStack);              // 80 s: still waiting
    CHECK(pkPlantDecide(petals, inputs(NO, @"a", 1000, 909, -1e9)).forgetOurStack);               // 91 s
    CHECK(!pkPlantDecide(petals, inputs(YES, @"a", 1000, 0, -1e9)).forgetOurStack);               // live: never forgotten
}
