// Who may be sent on an expedition, and in what order. The game's own rule
// (PikminInventoryTools.ReservingPikminForTroop): troop members ARE sendable; the
// game only holds back enough of them to keep the troop at its minimum size:
//   needToReserve = count(eligible in troop) - troopCount + minTroop
// Busy Pikmin (on a task, or status 0) and favourites never go.
//
// On top of that the roster strategy (TroopPlan) says WHO is expendable. A Pikmin
// away on an expedition is neither walking in the troop nor available for a
// mushroom, so
//  * whoever the troop plan wants in the troop right now is never sent;
//  * of the rest, ordinary Pikmin go first, strongest first (they carry more, so
//    the smallest party that can start is smaller);
//  * each colour's elite are the mushroom force and go last, weakest first, only
//    if the others cannot make the party.
// If nothing else is left, the troop's Pikmin are sent rather than nobody (the
// pass must never stall completely).
//
// Pure: plain snapshots in, an ordered list out.
#pragma once
#import <Foundation/Foundation.h>
#import "Roster.h"

typedef struct {
    NSUInteger plain, spare, heldForTroop;     // the three groups before the troop reservation
    int busy, starred;                         // excluded outright
    int reserved, need;                        // troop members held back, and how many had to be
    BOOL onlyTroop;                            // nothing else was left, so the troop's own were included
} PKPoolStats;

NSArray<PKPikmin *> *pkExpeditionPool(NSArray<PKPikmin *> *roster, NSSet<NSString *> *troopMembers,
                                      int troopTotal, int minTroop,
                                      NSSet<NSString *> *wanted, NSSet<NSString *> *elite, PKPoolStats *stats);
