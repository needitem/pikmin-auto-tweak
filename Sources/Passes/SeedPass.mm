#import "Passes.h"
#import "Backoff.h"
#import "GameContext.h"
#import "Inventory.h"
#import "Layout.h"
#import "Location.h"
#import "Log.h"
#import "Roster.h"
#import "SeedReader.h"
#import "SeedValue.h"
#import "TroopPlan.h"
#import "RpcClient.h"

// Plant seedlings into free planter slots and pluck the ripe ones.
//   PikminSeedProto: requiredSteps_, currentSteps_, currentBonusSteps_, plantedTimeMs_, birthPlacePoint_
//   PlanterProto.slot_ -> SlotProto: pikminSeedId_, remainingUse_, index_, slotType_ (1 = disposable)

@interface PKSeed : NSObject
@property (nonatomic, copy) NSString *sid;
@property (nonatomic) int req, cur, bonus;
@property (nonatomic) double blat, blng;
@property (nonatomic) PKSeedTraits traits;
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

// ---------- the pass, one step at a time ----------

typedef struct { int seeds, planted; } PKSeedCounts;

// Read every seedling in the inventory: planted and ripe (ready to pluck), or
// waiting for a slot. Also the ids that still exist (the backoff forgets the others).
static PKSeedCounts scanSeeds(NSMutableArray<PKSeed *> *ripe, NSMutableArray<PKSeed *> *waiting, NSMutableSet<NSString *> *alive) {
    __block PKSeedCounts n = {0, 0};
    pkListEach(pkInvList("GetPikminSeedList"), ^(void *item) {
        void *proto = pkItemProto(item);
        NSString *sid = pkItemId(item);
        if (!proto || !sid.length) return;
        n.seeds++;
        [alive addObject:sid];
        PKSeed *s = [PKSeed new];
        s.sid = sid;
        s.traits = pkSeedTraits(proto);
        s.req = pkGetInt(proto, &F_Seed_req);
        s.bonus = (int)pkGetF32(proto, &F_Seed_bonus);
        s.cur = pkGetInt(proto, &F_Seed_cur) + s.bonus;
        void *birth = pkGetPtr(proto, &F_Seed_birth);
        s.blat = pkGetF64(birth, &F_Pt_lat);
        s.blng = pkGetF64(birth, &F_Pt_lng);
        if (pkGetI64(proto, &F_Seed_planted) > 0) {
            n.planted++;
            if (s.req > 0 && s.cur >= s.req) [ripe addObject:s];
        } else {
            [waiting addObject:s];
        }
    });
    return n;
}

// Pluck ripe seedlings — one PullPikmin request, up to 5 ids. Returns how many.
static int pluckRipe(NSArray<PKSeed *> *ripe) {
    NSMutableArray<NSString *> *pull = [NSMutableArray array], *detail = [NSMutableArray array];
    for (PKSeed *s in ripe) {
        if (![backoff() ready:s.sid]) continue;
        [pull addObject:s.sid];
        [detail addObject:[NSString stringWithFormat:@"%@ %d/%d(+%d) %d번째", s.sid, s.cur, s.req, s.bonus, [backoff() tries:s.sid] + 1]];
        if (pull.count >= 5) break;
    }
    if (!pull.count || !pkRpcPullSeeds(pull)) return 0;
    for (NSString *sid in pull) [backoff() recordSend:sid];
    PALOG(@"[모종] 뽑기 %@", [detail componentsJoinedByString:@" | "]);
    return (int)pull.count;
}

// How many planter slots are free: not occupied, and not a used-up disposable one.
static int freePlanterSlots(void) {
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
    return nFree;
}

// Fill free slots, best seedlings first (every pass: planting is reliable now,
// and one-per-pass starved the pluck→drain cycle). What "best" means is in
// Model/SeedValue.h: special, then large, then ordinary ones of a colour the
// roster still wants, and within that the soonest to ripen. Returns how many.
static int plantWaiting(NSMutableArray<PKSeed *> *waiting, int nFree) {
    NSDictionary<NSNumber *, NSNumber *> *need = pkColorNeed(pkRoster());
    [waiting sortUsingComparator:^NSComparisonResult(PKSeed *a, PKSeed *b) {
        NSComparisonResult r = pkSeedCompare(a.traits, b.traits, need);
        return r != NSOrderedSame ? r : [a.sid compare:b.sid];
    }];
    int nSpecial = 0, nLarge = 0;
    for (PKSeed *s in waiting) { if (s.traits.tier == PKSeedTierSpecial) nSpecial++; else if (s.traits.tier == PKSeedTierLarge) nLarge++; }
    PKLOGC(@"seed.rank", ([NSString stringWithFormat:@"[모종] 심을 후보 %lu (특수 %d · 큰 %d · 일반 %lu), 슬롯 %d", (unsigned long)waiting.count,
                           nSpecial, nLarge, (unsigned long)waiting.count - nSpecial - nLarge, nFree]));
    double clat = 0, clng = 0;
    BOOL haveLoc = pkLocationGet(&clat, &clng);
    int set = 0;
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
            PALOG(@"[모종] 심기 id=%@ 종류=%d(%@) 색=%d req=%d point=(%.6f,%.6f)", s.sid, s.traits.seedType,
                  s.traits.tier == PKSeedTierSpecial ? @"특수" : s.traits.tier == PKSeedTierLarge ? @"큰" : @"일반", s.traits.color, s.req, lat, lng);
            set++;
        }
    }
    return set;
}

NSString *pkSeedPass(void) {
    if (!pkRpc() || !pkInv()) return @"서버 준비 대기";

    NSMutableArray<PKSeed *> *ripe = [NSMutableArray array], *waiting = [NSMutableArray array];
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    PKSeedCounts n = scanSeeds(ripe, waiting, alive);
    [backoff() pruneKeeping:alive];

    int pulled = pluckRipe(ripe);
    int nFree = freePlanterSlots();
    int set = (nFree && waiting.count) ? plantWaiting(waiting, nFree) : 0;
    return [NSString stringWithFormat:@"🌰 모종 %d (화분 %d, 익음 %lu, 대기 %lu) / 빈칸 %d / 뽑기 %d 심기 %d",
            n.seeds, n.planted, (unsigned long)ripe.count, (unsigned long)waiting.count, nFree, pulled, set];
}
