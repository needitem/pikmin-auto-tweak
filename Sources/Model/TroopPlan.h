// Who should walk in the troop. Only walking Pikmin gain friendship, so the
// troop is where hearts get made; this decides which ones get that chance.
//
// Pure logic over plain snapshots (no game access), so it can be run offline
// against a roster dump (tools/troop_sim.mm).
//
// Strategy — build a few strong Pikmin per colour, not many middling ones:
//  * Each colour's ELITE are its top kTroopEliteQuota Pikmin by hearts.
//  * A colour with fewer than a quota's worth at 4 hearts is in BUILD mode:
//    its elite still under 4 hearts want troop slots, closest to 4 first.
//  * A colour whose elite are all at 4+ is in MASTER mode: its elite under 8
//    hearts want slots, closest to 8 first.
//  * The slots are shared out between colours by weight (D'Hondt): a colour
//    far short of its quota weighs up to twice a colour that is only mastering,
//    and a colour with nobody left to train gets nothing.
//  * Pikmin outside every elite group (the 0-1 heart mass) only fill slots
//    nobody above them wants.
#pragma once
#import <Foundation/Foundation.h>
#import "Roster.h"

extern const int kTroopEliteQuota;     // elite per colour

// Who is elite, and which of the elite still want troop slots (the ones the
// plan would train), irrespective of who can be moved right now. Other passes
// use it to leave those Pikmin alone.
void pkTroopStanding(NSArray<PKPikmin *> *roster, NSSet<NSString *> **elite, NSSet<NSString *> **training);

// Per colour, how much the roster still wants more Pikmin of it, 0..1: the share
// of its elite quota still missing at 4 hearts. A colour already at its quota
// (training the elite to 8) wants none — more ordinary Pikmin of it add nothing.
NSDictionary<NSNumber *, NSNumber *> *pkColorNeed(NSArray<PKPikmin *> *roster);

// `roster`: every Pikmin owned (it defines each colour's standing).
// `movable`: the ones that may be moved right now (not on a task).
// `slots`: troop places available to them.
// Returns at most `slots` Pikmin from `movable`, most wanted first.
// `summary` (optional): one line, "색 배정수→목표하트 …", for the log.
NSArray<PKPikmin *> *pkTroopPlan(NSArray<PKPikmin *> *roster, NSArray<PKPikmin *> *movable,
                                 NSUInteger slots, NSString **summary);
