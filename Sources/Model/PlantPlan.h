// What the planting pass should do this time, decided from plain values: is a
// session live, whose is it, which plain petal stack is biggest, and when we last
// asked to start or stop. Pure — the pass does the asking.
//
// The strategy: keep a session running on the plain petal stack we hold the MOST
// of, and switch to a bigger one only when it is bigger by kPlantSwitchMargin
// (so near-equal stacks do not make the session flap on and off every petal). A
// session the player started by hand is left alone: we do not know which petal it
// spends. Special petals (named flowers) are kept for decor and never planted.
#pragma once
#import <Foundation/Foundation.h>
#import "Petals.h"

extern const int kPlantSwitchMargin;

typedef enum {
    PKPlantLeaveAlone,      // live, and not ours (started by hand)
    PKPlantKeep,            // live, ours, and still the best stack (or not worth switching)
    PKPlantSwitch,          // live, ours, a clearly bigger stack exists: stop it so it can restart on that
    PKPlantSwitchWait,      // ... but we asked to stop moments ago (stop is async)
    PKPlantNoPlain,         // not live; no plain petals at all
    PKPlantNoStack,         // not live; nothing plantable
    PKPlantStartWait,       // not live; we asked to start moments ago
    PKPlantStart,           // not live; start on the biggest plain stack
} PKPlantAction;

typedef struct {
    BOOL live;
    NSString *ourStackId;               // the stack our session spends; nil = not ours or not known
    NSTimeInterval now, lastStart, lastStop;
} PKPlantInputs;

typedef struct {
    PKPlantAction action;
    BOOL forgetOurStack;                // not live and long past our start request: it never went live, drop the id
} PKPlantDecision;

PKPlantDecision pkPlantDecide(NSArray<PKPetal *> *petals, PKPlantInputs in);

// Most petals first among the plain stacks; the id breaks ties so the choice is stable.
PKPetal *pkBiggestPlain(NSArray<PKPetal *> *petals);
PKPetal *pkStackById(NSArray<PKPetal *> *petals, NSString *itemId);
