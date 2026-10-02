// One-shot discovery logging. The roster strategy needs to know, per seedling,
// whether it is golden / large / worth its decor, and, per expedition, what it
// pays out — none of which the code can read yet. These dump the relevant game
// classes (fields and method signatures) into pa.log so the readers can be
// written against what is really there instead of against guesses.
//
// Each probe runs once after an install (a flag in the defaults, named after the
// probe version) so it never bloats the log again. Main thread only.
#pragma once
#import <Foundation/Foundation.h>

void pkProbeSeedItem(void *seedInventoryItem);   // first seedling the seed pass sees
void pkProbeExpedition(void *expeditionItemData); // first expedition the expedition pass sees
