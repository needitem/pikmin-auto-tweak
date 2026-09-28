// One function per automation pass. Each reads game state, decides, sends
// requests, and returns a one-line status for the log. A pass never keeps a
// game pointer beyond its own return, and never schedules anything itself:
// pacing belongs to the scheduler (App/Features.mm, App/Scheduler.mm).
#pragma once
#import <Foundation/Foundation.h>

NSString *pkFeedPass(void);         // 정수  — feed nectar to the squad
NSString *pkHarvestPass(void);      // 수확  — pick fallen petals
NSString *pkCollectPass(void);      // 수집  — claim finished carries/gifts/expeditions
NSString *pkExpeditionPass(void);   // 탐험  — send Pikmin on waiting expeditions
NSString *pkPlantPass(void);        // 심기  — keep a flower-planting session running
NSString *pkBigFlowerPass(void);    // 큰꽃  — claim nectar from bloomed big flowers
NSString *pkSeedPass(void);         // 모종  — plant seedlings, pluck ripe ones
NSString *pkTroopPass(void);        // 부대  — keep the walking troop optimal
NSString *pkNumberingPass(void);    // 번호  — rename every Pikmin to its pluck-order number

// Side outputs for the GPS Wander tweak and the user (not toggled).
void pkMapDumpPass(void);
void pkRosterDumpPass(void);
