#import "Passes.h"
#import "Backoff.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Log.h"
#import "Nectar.h"
#import "Petals.h"
#import "Roster.h"
#import "RpcClient.h"
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

// Sort by held count (most first), id as the tie-break so the order is stable.
static void sortByBalls(NSMutableArray<PKNectar *> *a) {
    [a sortUsingComparator:^NSComparisonResult(PKNectar *x, PKNectar *y) {
        if (x.balls != y.balls) return x.balls > y.balls ? NSOrderedAscending : NSOrderedDescending;
        return [x.itemId compare:y.itemId];
    }];
}

// Which special nectar to spend. The game keeps the reel choice in the UI only
// (not in the server prefs or a stored key), so the pinned stack — else the
// pinned flower name — goes first; otherwise the kind we hold most of.
static void promotePinned(NSMutableArray<PKNectar *> *special) {
    NSString *wantId = [PKSettings stringForKey:kSettingSpecialId];
    NSString *want = [PKSettings stringForKey:kSettingSpecial];
    for (PKNectar *h in [special copy]) {
        BOOL hit = wantId.length && [h.itemId isEqualToString:wantId];
        if (!hit && want.length && !wantId.length)
            hit = [h.kindName caseInsensitiveCompare:want] == NSOrderedSame || [@(h.hkind).stringValue isEqualToString:want];
        if (hit) { [special removeObject:h]; [special insertObject:h atIndex:0]; break; }
    }
    if (special.count) {
        NSMutableArray *bits = [NSMutableArray array];
        for (PKNectar *h in special)
            [bits addObject:[NSString stringWithFormat:@"%@ %d", h.kindName.length ? h.kindName : [NSString stringWithFormat:@"kind%d", h.hkind], h.balls]];
        PKLOGC(@"feed.special", ([NSString stringWithFormat:@"[feed] 특수정수 보유: %@%@", [bits componentsJoinedByString:@", "],
                                 want.length ? [NSString stringWithFormat:@" (지정: %@)", want] : @" (지정 없음 — 많은 것부터)"]));
    }
}

NSString *pkFeedPass(void) {
    if (!pkMgr() || !pkRpc()) return @"게임/서버 준비 대기";
    pkNectarSyncSelection();                          // whatever is picked right now

    NSMutableArray<PKNectar *> *plain = [NSMutableArray array], *special = [NSMutableArray array];
    long long totPlain = 0, totSpecial = 0;
    for (PKNectar *h in pkNectarList()) {
        if (h.special) { [special addObject:h]; totSpecial += h.balls; }
        else           { [plain addObject:h];   totPlain += h.balls; }
    }
    if (!totPlain && !totSpecial) return @"🍯 정수 없음";
    sortByBalls(plain); sortByBalls(special);
    promotePinned(special);

    NSArray<PKPikmin *> *squad = pkSquad();
    if (!squad.count) return @"🍯 대열에 피크민 없음 (배치/출격 필요)";
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    {
        int byState[8] = {0}; long long petals = 0;
        for (PKPikmin *p in squad) {
            [alive addObject:p.pid];
            if (p.flowerState >= 0 && p.flowerState < 8) byState[p.flowerState]++;
            petals += p.flowerCount + p.wilted;
        }
        PKLOGC(@"feed.census", ([NSString stringWithFormat:@"[feed] 대열 %lu: 잎%d 봉오리%d 꽃%d 수확가능%d 시듦%d 기타%d / 지금 딸 수 있는 꽃잎 %lld",
                                 (unsigned long)squad.count, byState[PK_PF_LEAF], byState[PK_PF_BUD], byState[PK_PF_FLOWER],
                                 byState[PK_PF_PICK], byState[PK_PF_WILTED], byState[0] + byState[2] + byState[7], petals]));
    }
    [backoff() pruneKeeping:alive];

    // A bucket whose petal stock is at the cap wastes the nectar (the harvest overflows).
    int petalCap = pkPetalCapacity();
    NSMutableSet<NSString *> *capped = [NSMutableSet set];
    if (petalCap > 0)
        for (PKPetal *p in pkPetalList())
            if (p.num >= petalCap) { NSString *k = pkBucketOfPetal(p); if (k) [capped addObject:k]; }

    NSMutableArray<PKPikmin *> *buds = [NSMutableArray array], *flowers = [NSMutableArray array];
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

    // One budget per stack, shared by both groups, so a stack is never spent twice.
    NSMutableDictionary<NSString *, NSNumber *> *remaining = [NSMutableDictionary dictionary];
    for (PKNectar *h in [plain arrayByAddingObjectsFromArray:special]) remaining[h.itemId] = @(h.balls);

    // Feed `targets` from `stacks` in order, five ids per request, one item each.
    int (^feed)(NSArray<PKPikmin *> *, NSArray<PKNectar *> *) = ^int(NSArray<PKPikmin *> *targets, NSArray<PKNectar *> *stacks) {
        int done = 0;
        NSUInteger next = 0;
        for (PKNectar *stack in stacks) {
            while (next < targets.count && remaining[stack.itemId].intValue > 0) {
                NSUInteger n = MIN((NSUInteger)5, MIN(targets.count - next, (NSUInteger)remaining[stack.itemId].intValue));
                NSArray<PKPikmin *> *chunk = [targets subarrayWithRange:NSMakeRange(next, n)];
                NSMutableArray<NSString *> *pids = [NSMutableArray array];
                for (PKPikmin *p in chunk) [pids addObject:p.pid];
                if (!pkRpcFeed(pids, stack.itemId, 1)) return done;
                for (PKPikmin *p in chunk) [backoff() recordSend:p.pid signature:signatureOf(p)];
                remaining[stack.itemId] = @(remaining[stack.itemId].intValue - (int)n);
                done += (int)n; next += n;
            }
        }
        return done;
    };

    // Buds/leaves take special nectar; plain when we hold none — or when every
    // special stack is held back because its flower's petals are at the cap
    // (that nectar would only overflow the harvest). Without that fallback a
    // squad of buds sat unfed beside hundreds of plain nectar.
    NSMutableArray<PKNectar *> *budStacks = [NSMutableArray array];
    NSMutableArray<NSString *> *held = [NSMutableArray array];
    void (^addUsable)(NSArray<PKNectar *> *) = ^(NSArray<PKNectar *> *stacks) {
        for (PKNectar *h in stacks) {
            NSString *bk = pkBucketOfNectar(h);
            if (bk && [capped containsObject:bk]) {
                [held addObject:[NSString stringWithFormat:@"%@(색%d)", h.kindName.length ? h.kindName : @"일반", h.type]];
                continue;
            }
            [budStacks addObject:h];
        }
    };
    addUsable(special);
    BOOL plainForBuds = NO;
    if (!budStacks.count) { plainForBuds = special.count > 0; addUsable(plain); }
    if (held.count)
        PKLOGC(@"feed.budcap", ([NSString stringWithFormat:@"[feed] 버킷 상한이라 봉오리에 안 쓰는 정수 %lu종: %@%@", (unsigned long)held.count,
                                 [held componentsJoinedByString:@", "], plainForBuds ? @" → 일반 정수로 대체" : @""]));
    int fedBud = feed(buds, budStacks);
    int fedFlower = feed(flowers, plain);
    PKNectar *sp = special.firstObject;
    return [NSString stringWithFormat:@"🍯 봉오리/잎 %d마리%@ · 꽃 %d마리(일반) / 일반 %lld 특수 %lld",
            fedBud,
            sp && !plainForBuds ? [NSString stringWithFormat:@"(특수 %@)", sp.kindName.length ? sp.kindName : [NSString stringWithFormat:@"kind%d", sp.hkind]] : @"(일반)",
            fedFlower, totPlain, totSpecial];
}
