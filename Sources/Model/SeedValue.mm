#import "SeedValue.h"

int pkSeedTier(int treasureType, BOOL hasEvent, BOOL large) {
    if (treasureType != 0 || hasEvent) return PKSeedTierSpecial;
    return large ? PKSeedTierLarge : PKSeedTierPlain;
}

NSComparisonResult pkSeedCompare(PKSeedTraits a, PKSeedTraits b, NSDictionary<NSNumber *, NSNumber *> *need) {
    if (a.tier != b.tier) return a.tier < b.tier ? NSOrderedAscending : NSOrderedDescending;
    double na = need[@(a.color)].doubleValue, nb = need[@(b.color)].doubleValue;
    if (na != nb) return na > nb ? NSOrderedAscending : NSOrderedDescending;          // the colour the roster wants more first
    if (a.req != b.req) return a.req < b.req ? NSOrderedAscending : NSOrderedDescending;   // then the soonest to ripen
    return NSOrderedSame;
}
