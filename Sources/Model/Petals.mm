#import "Petals.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Frame.h"
#import "Inventory.h"
#import "Layout.h"
#import "Nectar.h"

@implementation PKPetal
@end

static NSArray<PKPetal *> *scanPetals(void) {
    NSMutableArray<PKPetal *> *out = [NSMutableArray array];
    pkListEach(pkInvList("GetFlowerPetalList"), ^(void *item) {
        void *proto = pkItemProto(item);
        NSString *iid = pkItemId(item);
        if (!proto || !iid.length) return;
        PKPetal *p = [PKPetal new];
        p.itemId = iid;
        p.color = pkGetInt(proto, &F_Petal_color);
        p.kind = pkGetInt(proto, &F_Petal_kind);
        p.num = pkGetInt(proto, &F_Petal_num);
        p.flowerName = pkGetStr(proto, &F_Petal_fkind) ?: @"";
        // Same rule as nectar: kind 5 is COMMON (the four colours x kind 5 are the
        // ordinary stacks; confirmed against the in-game plain-petal total); only a
        // named flower is special.
        p.special = pkNectarIsSpecial(p.flowerName, p.kind);
        if (p.num > 0) [out addObject:p];
    });
    return out;
}

static NSArray<PKPetal *> *gPetalsFrame = nil;
static int gCapFrame = -2;                                   // -2 = not read this frame
static void registerReset(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pkFrameOnReset(^{ gPetalsFrame = nil; gCapFrame = -2; }); });
}
NSArray<PKPetal *> *pkPetalList(void) {
    registerReset();
    if (!pkFrameActive()) return scanPetals();
    if (!gPetalsFrame) gPetalsFrame = scanPetals();
    return gPetalsFrame;
}

// InventoryManager.itemCapacityInventoryItemStorage -> Items -> first item's
// proto (ItemCapacityProto) -> petal_ (CapacityProto): current + purchased.
static int scanCapacity(void) {
    void *inv = pkInv();
    if (!inv || !pkRuntimeReady()) return -1;
    void *items = pkGetPtr(pkGetPtr(inv, &F_Inv_capacity), &F_Stor_items);
    __block int cap = -1;
    pkListEach(items, ^(void *pred) {
        if (cap >= 0) return;                               // first element only
        void *item = pkGetPtr(pred, &F_Pred_conf) ?: pkGetPtr(pred, &F_Pred_pred);
        void *proto = item ? pkItemProto(item) : NULL;
        void *pc = pkGetPtr(proto, &F_Cap_petal);
        if (pc) cap = pkGetInt(pc, &F_Cap_cur) + pkGetInt(pc, &F_Cap_pur);
    });
    return cap;
}

int pkPetalCapacity(void) {
    registerReset();
    if (!pkFrameActive()) return scanCapacity();
    if (gCapFrame == -2) gCapFrame = scanCapacity();
    return gCapFrame;
}

static NSString *plainKey(int color) { return [NSString stringWithFormat:@"c%d|", color]; }
static NSString *namedKey(int color, NSString *name) {
    return [NSString stringWithFormat:@"c%d|%@", color, name.lowercaseString];
}

NSString *pkBucketOfPetal(PKPetal *p) {
    if (p.flowerName.length) return namedKey(p.color, p.flowerName);
    if (!p.special) return plainKey(p.color);
    return [NSString stringWithFormat:@"c%d|k%d", p.color, p.kind];   // unnamed special: matches nothing else
}

NSString *pkBucketOfNectar(PKNectar *n) {
    if (n.kindName.length) return namedKey(n.type, n.kindName);
    return n.special ? nil : plainKey(n.type);
}

// A bloom carries only a kind NUMBER, which is not comparable with a name —
// so only the plain flower (kind 0 or COMMON) is nameable.
NSString *pkBucketOfBloom(PKPikmin *p) {
    if (!p.hasBloom) return nil;
    return pkNectarIsSpecial(nil, p.bloomKind) ? nil : plainKey(p.bloomColor);
}
