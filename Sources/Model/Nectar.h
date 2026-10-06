// The nectar (HoneyBall) inventory. Which stack the player has chosen is
// NectarSelection's business; what counts as special is NectarKind's.
#pragma once
#import <Foundation/Foundation.h>
#import "NectarKind.h"

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

