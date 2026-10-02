// The game's ExpeditionDataStore: every expedition the client knows about
// (available, in progress, returned), as the game's own ExpeditionItemData.
#pragma once
#import <Foundation/Foundation.h>

// Pass-scoped ExpeditionItemData pointers (NSValue-wrapped).
NSArray<NSValue *> *pkExpeditionItems(void);

int   pkExpeditionState(void *data);            // ExpeditionState: PK_EXP_*
NSString *pkExpeditionKey(void *data);          // ExpeditionItemData.Key
void *pkExpeditionTaskProto(void *data);        // its PikminTaskProto
NSString *pkExpeditionTaskId(void *data);

// Task ids the store marks Returned — claimable expeditions.
NSSet<NSString *> *pkReturnedExpeditionIds(void);

// The task's pikmin list, and replacing / extending it (local proto only; the
// game's Start builds its request from it).
NSArray<NSString *> *pkExpeditionParty(void *data);
void pkExpeditionSetParty(void *data, NSArray<NSString *> *pids);
