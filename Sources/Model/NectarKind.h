// What counts as special nectar. Pure: the rule is shared by the nectar
// inventory, the petals and the feed pass.
#pragma once
#import <Foundation/Foundation.h>

// A named flower (rose, canna, …) is the special sort that decides what a bud
// opens into; kind 5 (the game's COMMON) and 0 are ordinary nectar.
BOOL pkNectarIsSpecial(NSString *flowerName, int honeyFlowerKind);
