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

// Requests that tend to arrive in a burst (a harvest of 90 Pikmin is 18 of them
// in one tick) go through here instead of being sent on the spot. They are
// queued and released one at a time, a quarter of a second apart, and only while
// the gate says the main thread is keeping up; a request that has waited too
// long is sent anyway. The game handles each request's answer on the main
// thread, and a burst of them was what froze it.
// `send` runs on the main thread, later, and builds and sends the request itself
// (so it must capture ids as text, never game pointers).
void pkRpcDefer(void (^send)(void));
void pkRpcSetGate(BOOL (^calm)(void));
NSString *pkRpcQueueStats(void);       // "예약 n · 강제 n · 대기 n (최대 n)" since the previous call

BOOL pkRpcFeed(NSArray<NSString *> *pikminIds, NSString *nectarItemId, int numItems);
BOOL pkRpcRename(NSString *pikminId, NSString *name);
BOOL pkRpcCompleteTask(NSString *taskId);
BOOL pkRpcPickFlowers(NSArray<NSString *> *pikminIds);
BOOL pkRpcClaimBigFlower(NSString *mapObjectId);
BOOL pkRpcSetSeed(NSString *seedId, double lat, double lng);   // server picks the slot
BOOL pkRpcPullSeeds(NSArray<NSString *> *seedIds);
BOOL pkRpcArrangeTroop(NSArray<NSString *> *moveIn, NSArray<NSString *> *moveOut);
