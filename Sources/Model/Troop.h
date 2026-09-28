// The walking troop, decided by the game's own PikminUtils.
#pragma once
#import <Foundation/Foundation.h>
#import "Roster.h"

typedef struct { int total; int max; } PKTroopCounts;

PKTroopCounts pkTroopCounts(void);                                   // current / capacity
// Ids of roster members in the troop. Cached ~20 s (the game's answer barely
// changes); `roster` must be from this pass.
NSSet<NSString *> *pkTroopMembers(NSArray<PKPikmin *> *roster);
void pkTroopInvalidate(void);                                        // roster just changed
int pkMinTroop(void);                                                // troop size the game keeps back from expeditions
