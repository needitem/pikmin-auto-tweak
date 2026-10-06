// Builds and sends the game's own request protos through its RpcManager.
// This is the only module that knows request shapes. Every call is
// fire-and-forget: reading back the returned Task from a timer tick wedged
// the whole app twice, so results are judged from state the game keeps and the
// passes already read (a claimed flower gets visitRewardReceived_, a planted
// seedling gets plantedTimeMs_, a started expedition leaves Available).
//
// Ids are passed as text; managed strings are created here, at the moment of
// use, so no caller ever holds a game pointer across a pass.
#pragma once
#import <Foundation/Foundation.h>

// "Name n, …" of the requests sent since the previous call (main thread), then reset.
NSString *pkRpcStats(void);

BOOL pkRpcFeed(NSArray<NSString *> *pikminIds, NSString *nectarItemId, int numItems);
BOOL pkRpcRename(NSString *pikminId, NSString *name);
BOOL pkRpcCompleteTask(NSString *taskId);
BOOL pkRpcPickFlowers(NSArray<NSString *> *pikminIds);
BOOL pkRpcClaimBigFlower(NSString *mapObjectId);
BOOL pkRpcSetSeed(NSString *seedId, double lat, double lng);   // server picks the slot
BOOL pkRpcPullSeeds(NSArray<NSString *> *seedIds);
BOOL pkRpcArrangeTroop(NSArray<NSString *> *moveIn, NSArray<NSString *> *moveOut);
