// The nectar (HoneyBall) inventory and which stack the player has chosen.
#pragma once
#import <Foundation/Foundation.h>

@interface PKNectar : NSObject
@property (nonatomic, copy) NSString *itemId;     // names one stack: colour AND flower kind
@property (nonatomic, copy) NSString *kindName;   // flower name for special nectar, "" for plain
@property (nonatomic) int balls;                  // predicted count — what the player sees
@property (nonatomic) int type;                   // honeyType: colour
@property (nonatomic) int hkind;                  // honeyFlowerKind
@property (nonatomic) BOOL special;
@end

// Colours we are allowed to spend (white/red/blue/yellow; rainbow is kept),
// with a positive held count.
NSArray<PKNectar *> *pkNectarList(void);

// Plain (no flower kind) predicted nectar by colour index 1..4.
void pkNectarPlainByColor(long long out[8]);

// A named flower (rose, canna, …) is the special sort that decides what a bud
// opens into; kind 5 is ordinary nectar.
BOOL pkNectarIsSpecial(NSString *flowerName, int honeyFlowerKind);

// The player's manual feed reveals which stack they mean. Any thread.
void pkNoteHandFed(NSString *itemId);
// Pin the special nectar to spend from the player's own choices (hand feed +
// the reel selection). Main thread; call before reading the pin.
void pkNectarSyncSelection(void);
