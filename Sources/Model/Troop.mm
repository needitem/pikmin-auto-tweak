#import "Troop.h"
#import "Reflection.h"
#import "Clock.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Layout.h"
#import "Log.h"

#define NS_PIKMINS "Niantic.Ichigo.Game.Pikmins"

// PikminUtils declares IsPikminInTroop twice — (PikminProto, InventoryManager)
// and the [Extension] (InventoryManager, PikminProto) — and name+arity cannot
// tell them apart. runtime_invoke does not type-check, so calling the wrong
// order runs game code on mismatched objects. Read the parameter types once
// and remember which order the method we got expects.
static void *gInTroop = NULL;
static int gOrder = 0;           // 1 = (InventoryManager, proto), 2 = (proto, InventoryManager), -1 = unavailable

static void resolveInTroop(void) {
    if (gOrder) return;
    void *cls = pkClass(NS_PIKMINS, "PikminUtils");
    if (!cls) return;            // not loaded yet — try again next time
    pkEachMethod(cls, ^(void *m, const char *name, int argc) {
        if (gOrder || strcmp(name, "IsPikminInTroop") || argc != 2) return;
        NSString *first = pkParamTypeName(m, 0);
        if (!first) return;
        gInTroop = m;
        gOrder = [first containsString:@"InventoryManager"] ? 1 : 2;
    });
    if (!gOrder) gOrder = -1;
    PALOG(@"[부대] IsPikminInTroop 인자 순서 = %@", gOrder == 1 ? @"(inventory, proto)" : gOrder == 2 ? @"(proto, inventory)" : @"판별 불가 → 동행 상태로 대체");
}

PKTroopCounts pkTroopCounts(void) {
    PKTroopCounts c = {0, 0};
    void *inv = pkInv();
    void *cls = pkClass(NS_PIKMINS, "PikminUtils");
    if (!inv || !cls) return c;
    void *a[1] = { inv };
    c.max = pkUnboxInt(pkInvoke(pkMethod(cls, "GetPikminInTroopCountMax", 1), NULL, a));
    c.total = pkUnboxInt(pkInvoke(pkMethod(cls, "GetPikminInTroopCount", 1), NULL, a));
    return c;
}

static NSSet<NSString *> *gCache = nil;
static NSTimeInterval gCacheAt = 0;
static NSUInteger gCacheRosterN = 0;
static const NSTimeInterval kTroopTtl = 20.0;

void pkTroopInvalidate(void) { gCache = nil; }

NSSet<NSString *> *pkTroopMembers(NSArray<PKPikmin *> *roster) {
    NSTimeInterval now = pkMono();
    if (gCache && now - gCacheAt < kTroopTtl && gCacheRosterN == roster.count) return gCache;
    resolveInTroop();
    void *inv = pkInv();
    NSMutableSet<NSString *> *members = [NSMutableSet set];
    for (PKPikmin *p in roster) {
        BOOL in;
        if (gOrder > 0 && inv && gInTroop) {
            void *a[2] = { gOrder == 1 ? inv : p.proto, gOrder == 1 ? p.proto : inv };
            in = pkUnboxBool(pkInvoke(gInTroop, NULL, a));
        } else {
            in = p.status == PK_STATUS_ENTOURAGE;
        }
        if (in) [members addObject:p.pid];
    }
    gCache = members; gCacheAt = now; gCacheRosterN = roster.count;
    return members;
}

// ClientSettingsProto.pikmin_ -> PikminSettingsProto.minTroopPikminCount_ (the game defaults it to 1).
int pkMinTroop(void) {
    void *tools = pkTools();
    if (!tools || !pkRuntimeReady()) return 1;
    void *cache = pkGetPtr(tools, &F_Tools_settings);
    void *settings = cache ? pkCall0(cache, "get_CurrentSettings") : NULL;
    void *ps = pkGetPtr(settings, &F_CS_pikmin);
    int v = pkGetInt(ps, &F_PS_minTroop);
    return v > 0 ? v : 1;
}
