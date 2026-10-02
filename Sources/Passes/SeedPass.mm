#import "Passes.h"
#import "Backoff.h"
#import "GameContext.h"
#import "Inventory.h"
#import "Layout.h"
#import "Location.h"
#import "Log.h"
#import "Probe.h"
#import "RpcClient.h"

// Plant seedlings into free planter slots and pluck the ripe ones.
//   PikminSeedProto: requiredSteps_, currentSteps_, currentBonusSteps_, plantedTimeMs_, birthPlacePoint_
//   PlanterProto.slot_ -> SlotProto: pikminSeedId_, remainingUse_, index_, slotType_ (1 = disposable)

@interface PKSeed : NSObject
@property (nonatomic, copy) NSString *sid;
@property (nonatomic) int req, cur, bonus;
@property (nonatomic) double blat, blng;
@end
@implementation PKSeed
@end

// The per-seed guard stops the same seed being re-sent before the server has
// answered. A refused request (the client's step count can run ahead of the
// server's) is retried after 30 s, then 60, 120, 240 — a flat two minutes made a
// single refusal cost two minutes.
static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:30 factor:2 max:240]; });
    return b;
}

NSString *pkSeedPass(void) {
    if (!pkRpc() || !pkInv()) return @"서버 준비 대기";

    NSMutableArray<PKSeed *> *ripe = [NSMutableArray array], *waiting = [NSMutableArray array];
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    __block int nPlanted = 0, nSeeds = 0;
    NSMutableArray<NSValue *> *protos = [NSMutableArray array];
    pkListEach(pkInvList("GetPikminSeedList"), ^(void *item) {
        void *proto = pkItemProto(item);
        NSString *sid = pkItemId(item);
        if (!proto || !sid.length) return;
        nSeeds++;
        [alive addObject:sid];
        if (nSeeds == 1) pkProbeSeedItem(item);
        [protos addObject:[NSValue valueWithPointer:proto]];
        PKSeed *s = [PKSeed new];
        s.sid = sid;
        s.req = pkGetInt(proto, &F_Seed_req);
        s.bonus = (int)pkGetF32(proto, &F_Seed_bonus);
        s.cur = pkGetInt(proto, &F_Seed_cur) + s.bonus;
        void *birth = pkGetPtr(proto, &F_Seed_birth);
        s.blat = pkGetF64(birth, &F_Pt_lat);
        s.blng = pkGetF64(birth, &F_Pt_lng);
        if (pkGetI64(proto, &F_Seed_planted) > 0) {
            nPlanted++;
            if (s.req > 0 && s.cur >= s.req) [ripe addObject:s];
        } else {
            [waiting addObject:s];
        }
    });
    [backoff() pruneKeeping:alive];
    pkProbeSeedTable(protos);

    // 1) Pluck ripe seedlings — one PullPikmin request, up to 5 ids.
    int pulled = 0;
    NSMutableArray<NSString *> *pull = [NSMutableArray array];
    NSMutableArray<NSString *> *detail = [NSMutableArray array];
    for (PKSeed *s in ripe) {
        if (![backoff() ready:s.sid]) continue;
        [pull addObject:s.sid];
        [detail addObject:[NSString stringWithFormat:@"%@ %d/%d(+%d) %d번째", s.sid, s.cur, s.req, s.bonus, [backoff() tries:s.sid] + 1]];
        if (pull.count >= 5) break;
    }
    if (pull.count && pkRpcPullSeeds(pull)) {
        for (NSString *sid in pull) [backoff() recordSend:sid];
        pulled = (int)pull.count;
        PALOG(@"[모종] 뽑기 %@", [detail componentsJoinedByString:@" | "]);
    }

    // 2) Count free planter slots.
    __block int nSlots = 0, nPlanters = 0, nFree = 0;
    NSMutableString *dbg = [NSMutableString string];
    pkListEach(pkInvList("GetPlanterList"), ^(void *planter) {
        void *proto = pkItemProto(planter);
        if (!proto) return;
        nPlanters++;
        [dbg appendFormat:@"P%d[", nPlanters];
        pkRepeatedEach(pkGetPtr(proto, &F_Planter_slots), ^(void *slot) {
            nSlots++;
            NSString *occupant = pkGetStr(slot, &F_Slot_seed);
            int remaining = pkGetInt(slot, &F_Slot_remain), idx = pkGetInt(slot, &F_Slot_index), type = pkGetInt(slot, &F_Slot_type);
            [dbg appendFormat:@"{i%d t%d r%d %@}", idx, type, remaining, occupant.length ? @"점유" : @"빈"];
            if (occupant.length) return;
            if (type == 1 && remaining <= 0) return;         // used-up disposable slot
            nFree++;
        });
        [dbg appendString:@"] "];
    });
    PKLOGC(@"seed.planters", ([NSString stringWithFormat:@"[모종] 화분%d 슬롯%d 빈%d | %@", nPlanters, nSlots, nFree, dbg]));

    // 3) Fill free slots with the seedlings that ripen soonest (every pass:
    // planting is reliable now, and one-per-pass starved the pluck→drain cycle).
    int set = 0;
    if (nFree && waiting.count) {
        [waiting sortUsingComparator:^NSComparisonResult(PKSeed *a, PKSeed *b) {
            if (a.req != b.req) return a.req < b.req ? NSOrderedAscending : NSOrderedDescending;
            return [a.sid compare:b.sid];
        }];
        double clat = 0, clng = 0;
        BOOL haveLoc = pkLocationGet(&clat, &clng);
        for (PKSeed *s in waiting) {
            if (set >= nFree) break;
            if (![backoff() ready:s.sid]) continue;
            double lat = s.blat, lng = s.blng;
            if (lat == 0 && lng == 0) {                       // no birth place: fall back to where we are
                if (!haveLoc) continue;
                lat = clat; lng = clng;
            }
            if (pkRpcSetSeed(s.sid, lat, lng)) {
                [backoff() recordSend:s.sid];
                PALOG(@"[모종] 심기 id=%@ req=%d point=(%.6f,%.6f)", s.sid, s.req, lat, lng);
                set++;
            }
        }
    }
    return [NSString stringWithFormat:@"🌰 모종 %d (화분 %d, 익음 %lu, 대기 %lu) / 빈칸 %d / 뽑기 %d 심기 %d",
            nSeeds, nPlanted, (unsigned long)ripe.count, (unsigned long)waiting.count, nFree, pulled, set];
}
