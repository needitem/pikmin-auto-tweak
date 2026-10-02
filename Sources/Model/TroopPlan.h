// Who should walk in the troop. Only walking Pikmin gain friendship, so the
// troop is where hearts get made; this decides which ones get that chance.
//
// Pure logic over plain snapshots (no game access), so it can be run offline
// against a roster dump (tools/troop_sim.mm).
//
// Strategy, in priority order:
//  1. DECOR first: a costume Pikmin still under 4 hearts, whatever its colour.
//  2. Then the ELITE of every colour — its top kTroopEliteQuota Pikmin by
//     hearts. Inside a colour, the elite still under 4 hearts come first (so
//     the colour really has a full quota at 4+), then the others toward 8
//     hearts; each part closest-to-goal first. Colours are served evenly (a
//     place goes to the colour that has received the fewest so far, a colour
//     short of its quota at 4 hearts counting up to double), so every colour
//     builds its quota instead of one colour racing ahead.
//  3. Anyone else only fills places nobody above wants (maxed Pikmin last).
#pragma once
#import <Foundation/Foundation.h>
#import "Roster.h"

extern const int kTroopEliteQuota;     // elite per colour

// Per colour, how much the roster still wants more Pikmin of it, 0..1: the share
// of its elite quota still missing at 4 hearts. A colour already at its quota
// wants none — more ordinary Pikmin of it add nothing. (Used to rank seedlings.)
NSDictionary<NSNumber *, NSNumber *> *pkColorNeed(NSArray<PKPikmin *> *roster);

// Ids of each colour's elite (top kTroopEliteQuota by hearts).
NSSet<NSString *> *pkTroopElite(NSArray<PKPikmin *> *roster);

// `roster`: every Pikmin owned (it defines each colour's standing).
// `movable`: the ones that may be moved right now (not on a task).
// `slots`: troop places available to them.
// Returns at most `slots` Pikmin from `movable`, most wanted first.
// `summary` (optional): one line, "색 데코a·정예b …", for the log.
NSArray<PKPikmin *> *pkTroopPlan(NSArray<PKPikmin *> *roster, NSArray<PKPikmin *> *movable,
                                 NSUInteger slots, NSString **summary);
