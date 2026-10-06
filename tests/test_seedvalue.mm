#import "TestKit.h"
#import "SeedValue.h"

static PKSeedTraits traits(int tier, int color, int req) { PKSeedTraits t = { tier, color, 0, req }; return t; }

void test_seed_tier(void) {
    CHECK_EQ(pkSeedTier(0, NO, NO), PKSeedTierPlain);
    CHECK_EQ(pkSeedTier(0, NO, YES), PKSeedTierLarge);
    CHECK_EQ(pkSeedTier(59, NO, NO), PKSeedTierSpecial);      // a fixed decor: golden and the like
    CHECK_EQ(pkSeedTier(0, YES, NO), PKSeedTierSpecial);      // an event seedling
    CHECK_EQ(pkSeedTier(59, YES, YES), PKSeedTierSpecial);    // special wins over large
}

// Special, then large, then plain; inside a tier the colour the roster wants first; then the quicker one.
void test_seed_compare(void) {
    NSDictionary *need = @{ @1: @0.0, @2: @0.4 };             // colour 2 is short, colour 1 is full
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierSpecial, 1, 5000), traits(PKSeedTierLarge, 2, 100), need), NSOrderedAscending);
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierLarge, 1, 5000), traits(PKSeedTierPlain, 2, 100), need), NSOrderedAscending);
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierPlain, 2, 5000), traits(PKSeedTierPlain, 1, 100), need), NSOrderedAscending);   // needed colour beats the quicker seed
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierPlain, 1, 1000), traits(PKSeedTierPlain, 1, 3000), need), NSOrderedAscending);  // same colour: quicker first
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierPlain, 1, 3000), traits(PKSeedTierPlain, 1, 3000), need), NSOrderedSame);
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierPlain, 1, 3000), traits(PKSeedTierSpecial, 2, 1), need), NSOrderedDescending);
}

// A colour missing from the need table counts as 0 (nothing wanted), never as an error.
void test_seed_compare_unknown_colour(void) {
    NSDictionary *need = @{ @2: @0.5 };
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierPlain, 9, 100), traits(PKSeedTierPlain, 2, 100), need), NSOrderedDescending);
    CHECK_EQ(pkSeedCompare(traits(PKSeedTierPlain, 9, 100), traits(PKSeedTierPlain, 8, 100), need), NSOrderedSame);
}

// A sort with it is deterministic and puts the best first.
void test_seed_sort(void) {
    NSDictionary *need = @{ @1: @0.0, @2: @0.3 };
    NSMutableArray *seeds = [NSMutableArray array];
    PKSeedTraits all[] = { traits(PKSeedTierPlain, 1, 1000), traits(PKSeedTierPlain, 2, 5000), traits(PKSeedTierLarge, 1, 5000),
                           traits(PKSeedTierSpecial, 1, 5000), traits(PKSeedTierPlain, 2, 1000) };
    for (auto &t : all) [seeds addObject:[NSValue valueWithBytes:&t objCType:@encode(PKSeedTraits)]];
    [seeds sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        PKSeedTraits x, y; [a getValue:&x]; [b getValue:&y]; return pkSeedCompare(x, y, need);
    }];
    int order[5]; for (int i = 0; i < 5; i++) { PKSeedTraits t; [seeds[i] getValue:&t]; order[i] = t.tier * 10 + t.color; }
    CHECK_EQ(order[0], 1);        // special
    CHECK_EQ(order[1], 11);       // large
    CHECK_EQ(order[2], 22);       // plain, needed colour, quicker (1000)...
    CHECK_EQ(order[3], 22);       // ...then the slower one
    CHECK_EQ(order[4], 21);       // plain of the full colour last
}
