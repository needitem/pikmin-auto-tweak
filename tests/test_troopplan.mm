#import "TestKit.h"
#import "TroopPlan.h"

static NSArray<PKPikmin *> *colour(int c, int n, float hearts, NSString *tag) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < n; i++) [a addObject:pikmin([NSString stringWithFormat:@"%@%d_%d", tag, c, i], c, hearts, NO, 1)];
    return a;
}
static NSUInteger countColour(NSArray<PKPikmin *> *a, int c) { NSUInteger n = 0; for (PKPikmin *p in a) if (p.color == c) n++; return n; }

// 1. A costume Pikmin under 4 hearts is wanted before anyone else, whatever its colour.
void test_troop_decor_first(void) {
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:colour(1, 45, 5.0f, @"r")];
    [all addObjectsFromArray:colour(2, 45, 5.0f, @"b")];
    PKPikmin *d1 = pikmin(@"decorA", 2, 0.5f, YES, 1), *d2 = pikmin(@"decorB", 1, 3.9f, YES, 1);
    [all addObject:d1]; [all addObject:d2];
    NSArray *plan = pkTroopPlan(all, all, 10, NULL);
    CHECK_EQ(plan.count, 10);
    CHECK([plan containsObject:d1]);
    CHECK([plan containsObject:d2]);
    CHECK([[plan subarrayWithRange:NSMakeRange(0, 2)] containsObject:d1]);   // the first places
    // a decor Pikmin at 4+ hearts gets no special treatment
    PKPikmin *d3 = pikmin(@"decorC", 1, 4.0f, YES, 1);
    NSMutableArray *all2 = [all mutableCopy]; [all2 addObject:d3];
    CHECK(![[pkTroopPlan(all2, all2, 2, NULL) subarrayWithRange:NSMakeRange(0, 2)] containsObject:d3]);
}

// 2. 7 hearts or more is finished: it only fills places nobody else wants.
void test_troop_seven_hearts_done(void) {
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:colour(1, 40, 5.0f, @"r")];
    PKPikmin *done = pikmin(@"done", 1, 7.0f, NO, 1), *almost = pikmin(@"almost", 1, 6.9f, NO, 1);
    [all addObject:done]; [all addObject:almost];
    // elite of colour 1 = top 40 by hearts: both 'done' and 'almost' are in it (they have the most hearts)
    NSArray *plan = pkTroopPlan(all, all, 5, NULL);
    CHECK(![plan containsObject:done]);
    CHECK([plan containsObject:almost]);
    // with more places than anyone wants, the finished one comes last
    NSArray *big = pkTroopPlan(all, all, (NSUInteger)all.count, NULL);
    CHECK_EQ(big.count, all.count);
    CHECK([big.lastObject isEqual:done]);
}

// 3. Busy Pikmin (not in `movable`) are never handed out.
void test_troop_respects_movable(void) {
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:colour(1, 40, 5.0f, @"r")];
    NSMutableArray *movable = [all mutableCopy];
    PKPikmin *busy = movable.firstObject; [movable removeObject:busy];
    NSArray *plan = pkTroopPlan(all, movable, 40, NULL);
    CHECK(![plan containsObject:busy]);
    CHECK_EQ(plan.count, 39);
}

// 4. Colours are served evenly; one that is short of its quota at 4 hearts gets more.
void test_troop_colour_balance(void) {
    NSMutableArray *even = [NSMutableArray array];
    [even addObjectsFromArray:colour(1, 40, 5.0f, @"r")];
    [even addObjectsFromArray:colour(2, 40, 5.0f, @"b")];
    NSArray *plan = pkTroopPlan(even, even, 20, NULL);
    CHECK_EQ(countColour(plan, 1), 10);
    CHECK_EQ(countColour(plan, 2), 10);

    NSMutableArray *short4 = [NSMutableArray array];             // colour 1: 30 at 5 hearts, 10 at 2 (short by 10 of 40)
    [short4 addObjectsFromArray:colour(1, 30, 5.0f, @"r")];
    [short4 addObjectsFromArray:colour(1, 10, 2.0f, @"low")];
    [short4 addObjectsFromArray:colour(2, 40, 5.0f, @"b")];
    NSArray *plan2 = pkTroopPlan(short4, short4, 20, NULL);
    CHECK(countColour(plan2, 1) > countColour(plan2, 2));
}

// 5. Inside a colour the elite still under 4 hearts come before the ones heading for 7.
void test_troop_under4_first(void) {
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:colour(1, 30, 5.0f, @"hi")];
    [all addObjectsFromArray:colour(1, 10, 2.0f, @"lo")];
    NSArray *plan = pkTroopPlan(all, all, 10, NULL);
    NSUInteger lo = 0; for (PKPikmin *p in plan) if (p.hearts < 4) lo++;
    CHECK_EQ(lo, 10);
}

// 6. Colour need and the elite set.
void test_troop_need_and_elite(void) {
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:colour(1, 30, 5.0f, @"r")];
    [all addObjectsFromArray:colour(1, 20, 1.0f, @"rlow")];      // 50 of colour 1: quota 40, 30 at 4+
    [all addObjectsFromArray:colour(2, 45, 6.0f, @"b")];         // quota full
    NSDictionary *need = pkColorNeed(all);
    CHECK([need[@1] doubleValue] > 0.24 && [need[@1] doubleValue] < 0.26);   // (40-30)/40
    CHECK_EQ([need[@2] doubleValue] * 100, 0);
    NSSet *elite = pkTroopElite(all);
    NSUInteger e1 = 0, e2 = 0;
    for (PKPikmin *p in all) if ([elite containsObject:p.pid]) { if (p.color == 1) e1++; else e2++; }
    CHECK_EQ(e1, 40); CHECK_EQ(e2, 40);
    // the elite are the highest-heart ones: every 5-heart Pikmin of colour 1 is in
    for (PKPikmin *p in all) if (p.color == 1 && p.hearts == 5.0f) CHECK([elite containsObject:p.pid]);
}

// 7. The summary names what was served (it ends up in the log).
void test_troop_summary(void) {
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:colour(1, 40, 5.0f, @"r")];
    NSString *summary = nil;
    pkTroopPlan(all, all, 4, &summary);
    CHECK(summary != nil);
    CHECK([summary containsString:@"빨강"]);
    CHECK([summary containsString:@"정예4"]);
}
