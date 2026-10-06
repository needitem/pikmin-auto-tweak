#import "Passes.h"
#import "Backoff.h"
#import "FeedPlan.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Log.h"
#import "Nectar.h"
#import "NectarSelection.h"
#import "Petals.h"
#import "Roster.h"
#import "RpcClient.h"
#import "RpcPacer.h"
#import "Settings.h"

// Feed the squad, matching the nectar to what each Pikmin's head is doing.
//
// PikminProto.flowerState_: 1 LEAF, 3 BUD, 4 FLOWER, 5 READY_TO_PICK, 6 WILTED.
// A leaf or a bud has not decided which flower it opens into, and that is the
// only window in which flower-specific ("special") nectar does anything —
// spend it there. An open flower takes plain colour nectar to add petals.
// Ready-to-pick / wilted heads are the harvest pass's business.
//
// Ids go five to a request, the shape the game's own feed uses. A Pikmin whose
// head did not change after we fed it (a flower already at its petal limit)
// backs off instead of being re-sent every pass.

static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:20 factor:2 max:600]; });
    return b;
}

static NSString *signatureOf(PKPikmin *p) {
    return [NSString stringWithFormat:@"%d/%d/%d", p.flowerState, p.flowerCount, p.wilted];
}

// ---------- the pass, one step at a time ----------

// Split the nectar we may spend into plain and special stacks, with totals.
typedef struct { long long plain, special; } PKStockTotals;
static PKStockTotals splitStock(NSMutableArray<PKNectar *> *plain, NSMutableArray<PKNectar *> *special) {
    PKStockTotals t = {0, 0};
    for (PKNectar *h in pkNectarList()) {
        if (h.special) { [special addObject:h]; t.special += h.balls; }
        else           { [plain addObject:h];   t.plain += h.balls; }
    }
    return t;
}

static void logSpecialStock(NSArray<PKNectar *> *special, NSString *pinnedKind) {
    if (!special.count) return;
    NSMutableArray *bits = [NSMutableArray array];
    for (PKNectar *h in special)
        [bits addObject:[NSString stringWithFormat:@"%@ %d", h.kindName.length ? h.kindName : [NSString stringWithFormat:@"kind%d", h.hkind], h.balls]];
    PKLOGC(@"feed.special", ([NSString stringWithFormat:@"[feed] 특수정수 보유: %@%@", [bits componentsJoinedByString:@", "],
                             pinnedKind.length ? [NSString stringWithFormat:@" (지정: %@)", pinnedKind] : @" (지정 없음 — 많은 것부터)"]));
}

// What the squad looks like, for the log, and the ids that still exist (the
// backoff forgets the others).
static NSSet<NSString *> *censusOfSquad(NSArray<PKPikmin *> *squad) {
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    int byState[8] = {0}; long long petals = 0;
    for (PKPikmin *p in squad) {
        [alive addObject:p.pid];
        if (p.flowerState >= 0 && p.flowerState < 8) byState[p.flowerState]++;
        petals += p.flowerCount + p.wilted;
    }
    PKLOGC(@"feed.census", ([NSString stringWithFormat:@"[feed] 대열 %lu: 잎%d 봉오리%d 꽃%d 수확가능%d 시듦%d 기타%d / 지금 딸 수 있는 꽃잎 %lld",
                             (unsigned long)squad.count, byState[PK_PF_LEAF], byState[PK_PF_BUD], byState[PK_PF_FLOWER],
                             byState[PK_PF_PICK], byState[PK_PF_WILTED], byState[0] + byState[2] + byState[7], petals]));
    return alive;
}

// A bucket whose petal stock is at the cap wastes the nectar (the harvest overflows).
static NSSet<NSString *> *cappedBuckets(int *petalCap) {
    *petalCap = pkPetalCapacity();
    NSMutableSet<NSString *> *capped = [NSMutableSet set];
    if (*petalCap > 0)
        for (PKPetal *p in pkPetalList())
            if (p.num >= *petalCap) { NSString *k = pkBucketOfPetal(p); if (k) [capped addObject:k]; }
    return capped;
}

// Who gets fed now: buds/leaves in one group, open flowers in the other.
// Skipped: heads the harvest pass handles, unknown heads, flowers whose petal
// bucket is at the cap, and anyone still waiting out a backoff.
static void classifySquad(NSArray<PKPikmin *> *squad, NSSet<NSString *> *capped, int petalCap,
                          NSMutableArray<PKPikmin *> *buds, NSMutableArray<PKPikmin *> *flowers) {
    int nCapped = 0, nWaiting = 0;
    for (PKPikmin *p in squad) {
        if (p.flowerState == PK_PF_PICK || p.flowerState == PK_PF_WILTED) continue;   // the harvest pass's business
        if (p.flowerState != PK_PF_LEAF && p.flowerState != PK_PF_BUD && p.flowerState != PK_PF_FLOWER) continue;   // unknown head: leave it
        if (p.flowerState == PK_PF_FLOWER) {
            NSString *bk = pkBucketOfBloom(p);
            if (bk && [capped containsObject:bk]) { nCapped++; continue; }
        }
        if (![backoff() ready:p.pid]) { nWaiting++; continue; }
        [(p.flowerState == PK_PF_FLOWER ? flowers : buds) addObject:p];
    }
    PKLOGC(@"feed.petalcap", ([NSString stringWithFormat:@"[feed] 꽃잎상한 %d · 꽉찬 버킷 %lu개 · 상한제외 %d마리 · 결과대기 %d (먹일 봉오리 %lu · 꽃 %lu)",
                               petalCap, (unsigned long)capped.count, nCapped, nWaiting, (unsigned long)buds.count, (unsigned long)flowers.count]));
}

// Queue the feeds for `targets` from `stacks` in order (the plan is FeedPlan's;
// the pacer sends) and note each fed Pikmin so it backs off if its head does not
// change. `remaining` is shared by every group fed in the pass.
static int feedGroup(NSArray<PKPikmin *> *targets, NSArray<PKNectar *> *stacks, NSMutableDictionary<NSString *, NSNumber *> *remaining) {
    NSMutableDictionary<NSString *, PKPikmin *> *byPid = [NSMutableDictionary dictionary];
    for (PKPikmin *p in targets) byPid[p.pid] = p;
    int done = 0;
    for (PKFeedBatch *batch in pkFeedAllocate([targets valueForKey:@"pid"], stacks, remaining)) {
        NSString *itemId = batch.itemId; NSArray<NSString *> *pids = batch.pids;
        pkRpcDefer(^{ pkRpcFeed(pids, itemId, 1); });              // queued and paced, see RpcPacer
        for (NSString *pid in pids) [backoff() recordSend:pid signature:signatureOf(byPid[pid])];
        done += (int)pids.count;
    }
    return done;
}

NSString *pkFeedPass(void) {
    if (!pkMgr() || !pkRpc()) return @"게임/서버 준비 대기";
    pkNectarSyncSelection();                          // whatever is picked right now

    NSMutableArray<PKNectar *> *plain = [NSMutableArray array], *special = [NSMutableArray array];
    PKStockTotals tot = splitStock(plain, special);
    if (!tot.plain && !tot.special) return @"🍯 정수 없음";
    pkSortByBalls(plain); pkSortByBalls(special);
    NSString *pinnedId = [PKSettings stringForKey:kSettingSpecialId], *pinnedKind = [PKSettings stringForKey:kSettingSpecial];
    pkPromotePinned(special, pinnedId, pinnedKind);
    logSpecialStock(special, pinnedKind);

    NSArray<PKPikmin *> *squad = pkSquad();
    if (!squad.count) return @"🍯 대열에 피크민 없음 (배치/출격 필요)";
    [backoff() pruneKeeping:censusOfSquad(squad)];

    int petalCap = 0;
    NSSet<NSString *> *capped = cappedBuckets(&petalCap);
    NSMutableArray<PKPikmin *> *buds = [NSMutableArray array], *flowers = [NSMutableArray array];
    classifySquad(squad, capped, petalCap, buds, flowers);

    // One budget per stack, shared by both groups, so a stack is never spent twice.
    NSMutableDictionary<NSString *, NSNumber *> *remaining = [NSMutableDictionary dictionary];
    for (PKNectar *h in [plain arrayByAddingObjectsFromArray:special]) remaining[h.itemId] = @(h.balls);

    // Buds/leaves take special nectar; plain when we hold none — or when every
    // special stack is held back because its flower's petals are at the cap
    // (that nectar would only overflow the harvest). Without that fallback a
    // squad of buds sat unfed beside hundreds of plain nectar.
    NSArray<NSString *> *held = nil;
    BOOL plainForBuds = NO;
    NSArray<PKNectar *> *budStacks = pkBudStacks(special, plain, capped, ^NSString *(PKNectar *h) { return pkBucketOfNectar(h); }, &held, &plainForBuds);
    if (held.count)
        PKLOGC(@"feed.budcap", ([NSString stringWithFormat:@"[feed] 버킷 상한이라 봉오리에 안 쓰는 정수 %lu종: %@%@", (unsigned long)held.count,
                                 [held componentsJoinedByString:@", "], plainForBuds ? @" → 일반 정수로 대체" : @""]));
    int fedBud = feedGroup(buds, budStacks, remaining);
    int fedFlower = feedGroup(flowers, plain, remaining);
    PKNectar *sp = special.firstObject;
    return [NSString stringWithFormat:@"🍯 봉오리/잎 %d마리%@ · 꽃 %d마리(일반) / 일반 %lld 특수 %lld",
            fedBud,
            sp && !plainForBuds ? [NSString stringWithFormat:@"(특수 %@)", sp.kindName.length ? sp.kindName : [NSString stringWithFormat:@"kind%d", sp.hkind]] : @"(일반)",
            fedFlower, tot.plain, tot.special];
}
