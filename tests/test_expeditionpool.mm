#import "TestKit.h"
#import "ExpeditionPool.h"
#import "TroopPlan.h"

static NSSet *ids(NSArray *a) { return [NSSet setWithArray:[a valueForKey:@"pid"]]; }
static PKPikmin *mk(NSString *pid, float hearts, int status, BOOL starred) {
    PKPikmin *p = pikmin(pid, 1, hearts, NO, status); p.starred = starred; return p;
}

// Busy and favourite Pikmin never go; the rest are ordered plain (strongest first), then elite (weakest first).
void test_pool_order_and_exclusions(void) {
    NSArray *roster = @[ mk(@"busy", 3, 2, NO), mk(@"zero", 3, 0, NO), mk(@"fav", 3, 1, YES),
                         mk(@"p1", 1, 1, NO), mk(@"p3", 3, 1, NO), mk(@"p2", 2, 1, NO),
                         mk(@"e6", 6, 1, NO), mk(@"e5", 5, 1, NO) ];
    NSSet *elite = [NSSet setWithObjects:@"e6", @"e5", nil];
    PKPoolStats st;
    NSArray *pool = pkExpeditionPool(roster, [NSSet set], 0, 0, [NSSet set], elite, &st);
    NSArray *order = [pool valueForKey:@"pid"];
    CHECK([order isEqualToArray:(@[ @"p3", @"p2", @"p1", @"e5", @"e6" ])]);
    CHECK_EQ(st.busy, 2);                                   // status TASK and status 0
    CHECK_EQ(st.starred, 1);
    CHECK_EQ(st.plain, 3); CHECK_EQ(st.spare, 2);
    CHECK(!st.onlyTroop);
}

// Whoever the troop plan wants stays out of the pool.
void test_pool_excludes_troop_plan(void) {
    NSArray *roster = @[ mk(@"w", 2, 1, NO), mk(@"a", 1, 1, NO) ];
    NSArray *pool = pkExpeditionPool(roster, [NSSet set], 0, 0, [NSSet setWithObject:@"w"], [NSSet set], NULL);
    CHECK_EQ(pool.count, 1);
    CHECK([[pool[0] pid] isEqualToString:@"a"]);
}

// Never stall: with nothing else, the troop's own are sent.
void test_pool_falls_back_to_troop(void) {
    NSArray *roster = @[ mk(@"w1", 2, 1, NO), mk(@"w2", 3, 1, NO) ];
    PKPoolStats st;
    NSArray *pool = pkExpeditionPool(roster, [NSSet set], 0, 0, [NSSet setWithObjects:@"w1", @"w2", nil], [NSSet set], &st);
    CHECK_EQ(pool.count, 2);
    CHECK(st.onlyTroop);
}

// The game keeps the troop at its minimum: need = (pool members in the troop) - troop size + minimum.
void test_pool_troop_reservation(void) {
    NSArray *roster = @[ mk(@"t1", 5, 1, NO), mk(@"t2", 4, 1, NO), mk(@"t3", 3, 1, NO), mk(@"o1", 2, 1, NO) ];
    NSSet *members = [NSSet setWithObjects:@"t1", @"t2", @"t3", nil];
    PKPoolStats st;
    // troop of 3, minimum 2 -> all 3 are in the pool, need = 3 - 3 + 2 = 2: the first two troop members in order are held back
    NSArray *pool = pkExpeditionPool(roster, members, 3, 2, [NSSet set], [NSSet set], &st);
    CHECK_EQ(st.need, 2);
    CHECK_EQ(st.reserved, 2);
    NSSet *left = ids(pool);
    CHECK(![left containsObject:@"t1"] && ![left containsObject:@"t2"]);
    CHECK([left containsObject:@"t3"] && [left containsObject:@"o1"]);
    // a troop already above its minimum needs none held back
    PKPoolStats st2;
    NSArray *pool2 = pkExpeditionPool(roster, members, 3, 0, [NSSet set], [NSSet set], &st2);
    CHECK_EQ(st2.reserved, 0);
    CHECK_EQ(pool2.count, 4);
}

// pkTroopWanted: busy troop members keep their place, so fewer places remain for the plan.
void test_troop_wanted_busy_takes_a_place(void) {
    NSMutableArray *roster = [NSMutableArray array];
    for (int i = 0; i < 10; i++) [roster addObject:pikmin([NSString stringWithFormat:@"p%d", i], 1, 3.0f, NO, i < 3 ? 2 : 1)];   // p0..p2 busy
    NSSet *members = [NSSet setWithObjects:@"p0", @"p1", @"p5", nil];
    NSArray *movable = nil; int busy = 0;
    NSArray *wanted = pkTroopWanted(roster, members, 5, &movable, &busy, NULL);
    CHECK_EQ(busy, 2);                                       // p0, p1 are busy members
    CHECK_EQ(movable.count, 7);                              // everyone not on a task
    CHECK_EQ(wanted.count, 3);                               // 5 places - 2 held by busy members
    for (PKPikmin *p in wanted) CHECK(p.status != 2);
}
