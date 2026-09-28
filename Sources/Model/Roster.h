// Snapshots of the player's Pikmin. Plain values plus two pass-scoped
// pointers (`item`, `proto`) that are valid only within the pass that built
// the snapshot — never cache a PKPikmin across passes.
#pragma once
#import <Foundation/Foundation.h>

@interface PKPikmin : NSObject
@property (nonatomic, copy) NSString *pid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) long long pluckMs;          // LLONG_MAX when the game has none
@property (nonatomic) long long steps;
@property (nonatomic) int status;                 // PK_STATUS_*
@property (nonatomic) int flowerState;            // PK_PF_*
@property (nonatomic) int flowerCount;            // petals on the current flower
@property (nonatomic) int wilted;                 // fallen petals waiting to be picked
@property (nonatomic) BOOL hasBloom;
@property (nonatomic) int bloomColor, bloomKind;  // the flower it currently wears
@property (nonatomic) BOOL starred;
@property (nonatomic) float hearts;               // 0..8
@property (nonatomic) int heartPoints;
@property (nonatomic) int color, category, asset; // asset >= 2 means a costume (decor)
@property (nonatomic) void *item;                 // PikminInventoryItem (roster only)
@property (nonatomic) void *proto;                // PikminProto
@property (nonatomic, readonly) BOOL isDecor;
@end

// Every owned Pikmin, sorted by pluck time then id (deterministic even when
// the game reports equal or missing pluck times). Within a frame (Frame.h) the
// scan is shared; call pkRosterInvalidate() after an action that changes
// statuses so later passes in the same tick re-read.
NSArray<PKPikmin *> *pkRoster(void);
void pkRosterInvalidate(void);

// The deployed squad (PikminManager.playerFollowingPikmins). Frame-shared too.
NSArray<PKPikmin *> *pkSquad(void);
