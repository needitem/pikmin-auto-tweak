// Reads a seedling from the game into the plain traits SeedValue ranks.
// Large seedlings come from the catalog (PikminSeedCatalog.seedInfoList, found
// once through Resources.FindObjectsOfTypeAll); until it can be read, the types it
// reported on this build stand in. Main thread; the proto is a pass-scoped pointer.
#pragma once
#import <Foundation/Foundation.h>
#import "SeedValue.h"

// A PikminSeedProto: from an inventory seedling or an expedition's reward.
PKSeedTraits pkSeedTraits(void *seedProto);
