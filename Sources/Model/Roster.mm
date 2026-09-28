#import "Roster.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Inventory.h"
#import "Frame.h"
#import "Layout.h"
#import <limits.h>

@implementation PKPikmin
- (BOOL)isDecor { return _asset >= 2; }
@end

static PKPikmin *readPikmin(void *proto, void *item) {
    NSString *pid = pkGetStr(proto, &F_PP_id);
    if (!pid.length) return nil;
    PKPikmin *p = [PKPikmin new];
    p.pid = pid;
    p.name = pkGetStr(proto, &F_PP_name);
    void *pluck = pkGetPtr(proto, &F_PP_pluck);
    p.pluckMs = pluck ? pkGetI64(pluck, &F_Ts_ms) : LLONG_MAX;
    p.steps = pkGetI64(proto, &F_PP_steps);
    p.status = pkGetInt(proto, &F_PP_status);
    p.flowerState = pkGetInt(proto, &F_PP_flowerState);
    // What can be picked right now is flowerStateFlowerCount_ plus wiltedCount_
    // once the flower has wilted. (numFlowers_ is a lifetime tally — not read.)
    p.flowerCount = pkGetInt(proto, &F_PP_flowerCount);
    p.wilted = pkGetInt(proto, &F_PP_wilted);
    void *bloom = pkGetPtr(proto, &F_PP_bloom);
    p.hasBloom = bloom != NULL;
    p.bloomColor = pkGetInt(bloom, &F_Fl_color);
    p.bloomKind = pkGetInt(bloom, &F_Fl_kind);
    p.starred = pkGetBool(proto, &F_PP_starred);
    void *friendship = pkGetPtr(proto, &F_PP_friend);
    p.hearts = pkGetF32(friendship, &F_Fr_hearts);
    p.heartPoints = pkGetInt(friendship, &F_Fr_points);
    void *type = pkGetPtr(proto, &F_PP_type);
    p.color = pkGetInt(type, &F_PT_type);
    p.category = pkGetInt(type, &F_PT_category);
    p.asset = pkGetInt(type, &F_PT_asset);
    p.proto = proto;
    p.item = item;
    return p;
}

static NSArray<PKPikmin *> *gRosterFrame = nil, *gSquadFrame = nil;

static void registerReset(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pkFrameOnReset(^{ gRosterFrame = nil; gSquadFrame = nil; }); });
}

void pkRosterInvalidate(void) { gRosterFrame = nil; }

static NSArray<PKPikmin *> *scanRoster(void);
NSArray<PKPikmin *> *pkRoster(void) {
    registerReset();
    if (!pkFrameActive()) return scanRoster();
    if (!gRosterFrame) gRosterFrame = scanRoster();
    return gRosterFrame;
}

static NSArray<PKPikmin *> *scanRoster(void) {
    if (!pkInv() || !pkRuntimeReady()) return nil;
    void *list = pkInvList("GetPikminList");
    if (!list) return nil;
    NSMutableArray<PKPikmin *> *out = [NSMutableArray array];
    pkListEach(list, ^(void *item) {
        PKPikmin *p = readPikmin(pkItemProto(item), item);
        if (p) [out addObject:p];
    });
    [out sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) {
        if (a.pluckMs != b.pluckMs) return a.pluckMs < b.pluckMs ? NSOrderedAscending : NSOrderedDescending;
        return [a.pid compare:b.pid];
    }];
    return out;
}

// Elements are declared List<IPlayerFollower>; only real Pikmin objects count,
// and the SERVER id comes from their proto — the runtime Pikmin.id gave ids the
// feed RPC choked on.
static NSArray<PKPikmin *> *scanSquad(void);
NSArray<PKPikmin *> *pkSquad(void) {
    registerReset();
    if (!pkFrameActive()) return scanSquad();
    if (!gSquadFrame) gSquadFrame = scanSquad();
    return gSquadFrame;
}

static NSArray<PKPikmin *> *scanSquad(void) {
    void *mgr = pkMgr();
    if (!mgr || !pkRuntimeReady()) return nil;
    void *list = pkGetPtr(mgr, &F_Mgr_squad);
    if (!list) return nil;
    void *pikCls = pkClass("Niantic.Ichigo.Game.Pikmins", "Pikmin");
    NSMutableArray<PKPikmin *> *out = [NSMutableArray array];
    pkListEach(list, ^(void *pk) {
        if (pikCls && pkClassOf(pk) != pikCls) return;
        PKPikmin *p = readPikmin(pkGetPtr(pk, &F_Pik_proto), NULL);
        if (p) [out addObject:p];
    });
    return out;
}
