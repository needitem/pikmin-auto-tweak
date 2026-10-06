#import "RpcClient.h"
#import "GameContext.h"
#import "Layout.h"
#import "Clock.h"
#import "Log.h"

// RpcManager.Send<Name>Rpc[ForResult]Async(request, CancellationToken.None, RpcRetryPolicy).
static NSMutableDictionary<NSString *, NSNumber *> *gSent;    // main thread only, like every pass

NSString *pkRpcStats(void) {
    if (!gSent.count) return @"-";
    NSMutableArray *bits = [NSMutableArray array];
    for (NSString *k in [gSent.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [bits addObject:[NSString stringWithFormat:@"%@ %@", k, gSent[k]]];
    [gSent removeAllObjects];
    return [bits componentsJoinedByString:@", "];
}

// ---------- paced sending ----------
static const NSTimeInterval kPaceGap = 0.25;       // between two deferred requests
static const NSTimeInterval kMaxWait = 20.0;       // a request never waits longer than this for a calm moment

static NSMutableArray<void (^)(void)> *gQueue;
static NSMutableArray<NSNumber *> *gQueuedAt;
static NSTimer *gPacer;
static BOOL (^gGate)(void);
static unsigned long gDeferred, gForced;
static NSUInteger gQueuePeak;

static void pump(void) {
    if (!gQueue.count) { [gPacer invalidate]; gPacer = nil; return; }
    BOOL calm = !gGate || gGate();
    BOOL stale = pkMono() - gQueuedAt.firstObject.doubleValue > kMaxWait;
    if (!calm && !stale) return;
    if (!calm) gForced++;
    void (^send)(void) = gQueue.firstObject;
    [gQueue removeObjectAtIndex:0]; [gQueuedAt removeObjectAtIndex:0];
    send();
}

void pkRpcSetGate(BOOL (^calm)(void)) { gGate = [calm copy]; }

void pkRpcDefer(void (^send)(void)) {
    if (!gQueue) { gQueue = [NSMutableArray array]; gQueuedAt = [NSMutableArray array]; }
    [gQueue addObject:[send copy]]; [gQueuedAt addObject:@(pkMono())];
    gDeferred++;
    gQueuePeak = MAX(gQueuePeak, gQueue.count);
    if (!gPacer) gPacer = [NSTimer scheduledTimerWithTimeInterval:kPaceGap repeats:YES block:^(NSTimer *t) { pump(); }];
}

NSString *pkRpcQueueStats(void) {
    NSString *s = [NSString stringWithFormat:@"예약 %lu · 강제 %lu · 대기 %lu (최대 %lu)", gDeferred, gForced,
                   (unsigned long)gQueue.count, (unsigned long)gQueuePeak];
    gDeferred = gForced = 0; gQueuePeak = gQueue.count;
    return s;
}

static BOOL sendRpc(const char *rpcMethod, void *req) {
    void *rpc = pkRpc();
    if (!rpc || !req) return NO;
    void *m = pkMethodOf(rpc, rpcMethod, 3);
    if (!m) { PKLOGC([@"rpc.missing." stringByAppendingString:@(rpcMethod)],
                     [NSString stringWithFormat:@"[rpc] %s 없음", rpcMethod]); return NO; }
    unsigned char ct[8] = {0};            // CancellationToken.None
    int retry = 2;                        // RpcRetryPolicy
    void *args[3] = { req, ct, &retry };
    BOOL ok = NO;
    pkInvokeEx(m, rpc, args, &ok);
    if (!gSent) gSent = [NSMutableDictionary dictionary];
    NSString *key = @(rpcMethod);
    gSent[key] = @(gSent[key].intValue + 1);
    return ok;
}

// A request's `pikminId_` repeated field, reached through its getter.
static BOOL addPikminIds(void *req, NSArray<NSString *> *ids) {
    void *rf = pkCall0(req, "get_PikminId");
    if (!rf) return NO;
    for (NSString *pid in ids) pkRepeatedAdd(rf, pkNewString(pid));
    return YES;
}

BOOL pkRpcFeed(NSArray<NSString *> *ids, NSString *itemId, int numItems) {
    if (!ids.count || !itemId.length) return NO;
    void *req = pkNewProto("FeedPikminsRequestProto", NULL);
    if (!req || !addPikminIds(req, ids)) return NO;
    void *a1[1] = { pkNewString(itemId) };
    pkInvoke(pkMethodOf(req, "set_ItemId", 1), req, a1);
    void *a2[1] = { &numItems };
    pkInvoke(pkMethodOf(req, "set_NumItems", 1), req, a2);
    return sendRpc("SendFeedPikminsRpcAsync", req);        // the plain variant, as the game uses
}

BOOL pkRpcRename(NSString *pid, NSString *name) {
    void *req = pkNewProto("RenamePikminRequestProto", NULL);
    if (!req) return NO;
    void *a1[1] = { pkNewString(pid) };
    pkInvoke(pkMethodOf(req, "set_PikminId", 1), req, a1);
    void *a2[1] = { pkNewString(name) };
    pkInvoke(pkMethodOf(req, "set_Name", 1), req, a2);
    return sendRpc("SendRenamePikminRpcForResultAsync", req);
}

BOOL pkRpcCompleteTask(NSString *taskId) {
    void *req = pkNewProto("CompletePikminTaskRequestProto", NULL);
    if (!req) return NO;
    pkSetRef(req, &F_Complete_taskId, pkNewString(taskId));
    return sendRpc("SendCompletePikminTaskRpcForResultAsync", req);
}

BOOL pkRpcPickFlowers(NSArray<NSString *> *ids) {
    if (!ids.count) return NO;
    void *req = pkNewProto("PickPikminFlowersRequestProto", NULL);
    if (!req || !addPikminIds(req, ids)) return NO;
    return sendRpc("SendPickPikminFlowersRpcAsync", req);  // the variant the game's batched harvest awaits
}

BOOL pkRpcClaimBigFlower(NSString *mapObjectId) {
    void *req = pkNewProto("ClaimPoiFlowerVisitRewardRequestProto", NULL);
    if (!req) return NO;
    pkSetRef(req, &F_Claim_id, pkNewString(mapObjectId));
    pkSetBool(req, &F_Claim_fail, YES);                    // includeFailedReason_
    return sendRpc("SendClaimPoiFlowerVisitRewardRpcAsync", req);
}

// Exactly the request the game's own planter sends: the seed id and its birth
// place as the point, NO slot option — the server picks the slot. (With a slot
// index and the current position it was silently refused.)
BOOL pkRpcSetSeed(NSString *seedId, double lat, double lng) {
    void *req = pkNewProto("SetPikminSeedRequestProto", NULL);
    void *pt = pkNewProto("PointProto", NULL);
    if (!req || !pt) return NO;
    pkSetF64(pt, &F_Pt_lat, lat);
    pkSetF64(pt, &F_Pt_lng, lng);
    pkSetRef(req, &F_SetSeed_id, pkNewString(seedId));
    pkSetRef(req, &F_SetSeed_point, pt);
    return sendRpc("SendSetPikminSeedRpcAsync", req);
}

BOOL pkRpcPullSeeds(NSArray<NSString *> *ids) {
    if (!ids.count) return NO;
    void *req = pkNewProto("PullPikminRequestProto", NULL);
    void *rf = req ? pkCall0(req, "get_SeedId") : NULL;
    if (!rf) return NO;
    for (NSString *sid in ids) pkRepeatedAdd(rf, pkNewString(sid));
    return sendRpc("SendPullPikminRpcForResultAsync", req);
}

// ArrangePikminTroopRequestProto.moveToTroop / moveToEntourage: repeated
// MoveToTroopProto / MoveToEntourageProto, each {pikminId}.
BOOL pkRpcArrangeTroop(NSArray<NSString *> *in, NSArray<NSString *> *out) {
    void *reqCls = NULL;
    void *req = pkNewProto("ArrangePikminTroopRequestProto", &reqCls);
    void *toTroop = req ? pkCall0(req, "get_MoveToTroop") : NULL;
    void *toEnt = req ? pkCall0(req, "get_MoveToEntourage") : NULL;
    void *tCls = pkNestedClass(reqCls, "MoveToTroopProto");
    void *eCls = pkNestedClass(reqCls, "MoveToEntourageProto");
    void *setT = tCls ? pkMethod(tCls, "set_PikminId", 1) : NULL;
    void *setE = eCls ? pkMethod(eCls, "set_PikminId", 1) : NULL;
    if (!toTroop || !toEnt || !setT || !setE) {
        PKLOGC(@"rpc.arrange", @"[부대] Arrange 요청 구성 요소를 못 찾음");
        return NO;
    }
    for (NSString *pid in in) {
        void *item = pkNewObj(tCls);
        void *a[1] = { pkNewString(pid) };
        if (item) { pkInvoke(setT, item, a); pkRepeatedAdd(toTroop, item); }
    }
    for (NSString *pid in out) {
        void *item = pkNewObj(eCls);
        void *a[1] = { pkNewString(pid) };
        if (item) { pkInvoke(setE, item, a); pkRepeatedAdd(toEnt, item); }
    }
    return sendRpc("SendArrangePikminTroopRpcForResultAsync", req);
}
