// The flower-petal inventory, its capacity, and the "bucket" a flower's
// petals land in.
#pragma once
#import <Foundation/Foundation.h>
#import "Nectar.h"
#import "Roster.h"

@interface PKPetal : NSObject
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, copy) NSString *flowerName;  // "" for plain petals
@property (nonatomic) int color, kind, num;
@property (nonatomic) BOOL special;                // kept for decor — never planted automatically
@end

NSArray<PKPetal *> *pkPetalList(void);             // held stacks (num > 0)
int pkPetalCapacity(void);                         // per-bucket stock cap, -1 if unknown

// A bucket key names "petals of this colour and flower". Petals and a Pikmin's
// bloom share the FlowerKind number; nectar is matched through the flower name.
// nil means that side cannot be named, and the caller assumes nothing.
NSString *pkBucketOfPetal(PKPetal *p);
NSString *pkBucketOfNectar(PKNectar *n);           // what nectar of this stack blooms into
NSString *pkBucketOfBloom(PKPikmin *p);            // what a bloomed Pikmin's petals fill
