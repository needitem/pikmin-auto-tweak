// How much a seedling is worth, from what the game tells us about it.
//
// Strategy (see Model/TroopPlan.h): the roster needs depth in a few colours,
// not another ordinary Pikmin of a colour it already has, so
//   1. SPECIAL seedlings come first — a fixed decor (treasureType_) or an event
//      seedling (eventId_): golden seedlings and the like;
//   2. then LARGE ones (the catalog's Size.Large: the special-colour seedlings,
//      silver, ...);
//   3. then ordinary ones, those of a colour the troop plan still wants more of
//      before those of a colour it has enough of.
// Ordinary seedlings are never skipped — a free slot costs nothing; this only
// decides what goes first when slots or expedition parties are contended.
//
// Not covered: whether a decor category is already complete (the grey/yellow
// icon). The picture-book object could not be found in the game yet.
//
// Pure (no game access). Reading the game's seedlings into PKSeedTraits is
// SeedReader's job.
#pragma once
#import <Foundation/Foundation.h>

enum { PKSeedTierSpecial = 0, PKSeedTierLarge = 1, PKSeedTierPlain = 2 };

typedef struct {
    int tier;           // PKSeedTier*
    int color;          // the colour of the Pikmin it grows into
    int seedType;
    int req;            // steps to ripen
} PKSeedTraits;

// Which tier a seedling belongs to, from three facts about it:
//   treasureType  the decor it is fixed to (0 = none) — golden and the like
//   hasEvent      it carries an event id
//   large         the catalog calls its type Large
int pkSeedTier(int treasureType, BOOL hasEvent, BOOL large);

// `need`: colour -> how much the roster still wants it (pkColorNeed).
// Lower value = plant / fetch first.
NSComparisonResult pkSeedCompare(PKSeedTraits a, PKSeedTraits b, NSDictionary<NSNumber *, NSNumber *> *need);
