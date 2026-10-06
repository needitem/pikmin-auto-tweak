// The roster as files for the GPS Wander tweak and the user: roster.json (every
// Pikmin) and roster.txt (counts by colour, status and decor). Pure formatting
// over snapshots, no game access and no file access — the pass that owns the
// files decides when to write.
#pragma once
#import <Foundation/Foundation.h>
#import "Roster.h"

// What the files show, steps excluded (walking changes them constantly), so the
// caller can skip a rewrite when nothing it displays moved.
uint64_t pkRosterSignature(NSArray<PKPikmin *> *roster);

// {"t":…,"total":n,"starred":n,"pikmin":[{…},…]} — valid JSON, names escaped.
NSData *pkRosterJson(NSArray<PKPikmin *> *roster, NSTimeInterval stamp);

NSData *pkRosterSummary(NSArray<PKPikmin *> *roster);
