#import "Petals.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Frame.h"
#import "Inventory.h"
#import "Layout.h"
#import "Log.h"
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
        if (!pc) return;
        int cur = pkGetInt(pc, &F_Cap_cur), pur = pkGetInt(pc, &F_Cap_pur);
        // Stacks stop at exactly currentCount_ (six different stacks sit at 400
        // while currentCount_ + purchasedCount_ reads 500), so purchasedCount_ is
        // not extra room per stack: the cap is currentCount_ alone.
        cap = cur > 0 ? cur : cur + pur;
        PKLOGC(@"petal.cap", ([NSString stringWithFormat:@"[꽃잎상한] currentCount_=%d purchasedCount_=%d → 상한 %d", cur, pur, cap]));
    });
    return cap;
}

int pkPetalCapacity(void) {
    registerReset();
    if (!pkFrameActive()) return scanCapacity();
    if (gCapFrame == -2) gCapFrame = scanCapacity();
    return gCapFrame;
}

// A bucket is "petals of this colour and flower kind". Petals and a Pikmin's
// bloom both carry the game's FlowerKind number (lisianthus is 55 on both), so
// it is compared as a number; plain (kind 0 or COMMON 5) is normalised to 0.
// Nectar carries a differently-encoded kind, so it is matched through the
// flower NAME, looked up in the petals we hold.
static int normKind(int kind) { return pkNectarIsSpecial(nil, kind) ? kind : 0; }
static NSString *bucketKey(int color, int kind) { return [NSString stringWithFormat:@"c%d|k%d", color, normKind(kind)]; }

NSString *pkBucketOfPetal(PKPetal *p) { return bucketKey(p.color, p.kind); }

NSString *pkBucketOfNectar(PKNectar *n) {
    if (!n.special) return bucketKey(n.type, 0);
    if (!n.kindName.length) return nil;
    for (PKPetal *p in pkPetalList())                     // same colour and flower name -> its kind number
        if (p.color == n.type && [p.flowerName caseInsensitiveCompare:n.kindName] == NSOrderedSame) return bucketKey(p.color, p.kind);
    return nil;                                           // no stack of that flower held: nothing to be capped
}

NSString *pkBucketOfBloom(PKPikmin *p) { return p.hasBloom ? bucketKey(p.bloomColor, p.bloomKind) : nil; }
