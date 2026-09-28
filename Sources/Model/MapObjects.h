// Map objects the server streamed for the current viewport (big flowers,
// flower fields, mushrooms, campaigns). Value snapshots only.
#pragma once
#import <Foundation/Foundation.h>

@interface PKMapObject : NSObject
@property (nonatomic, copy) NSString *oid;
@property (nonatomic) int kind;                 // PK_MO_*
@property (nonatomic) double lat, lng;
@property (nonatomic) int state, color;
@property (nonatomic) long long bloomMs;
@property (nonatomic) BOOL visited;             // reward already claimed
@end

// One scan shared by every consumer, cached for a few seconds.
NSArray<PKMapObject *> *pkMapObjects(void);
