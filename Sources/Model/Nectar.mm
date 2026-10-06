#import "Nectar.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Frame.h"
#import "Inventory.h"
#import "Layout.h"
#import "Log.h"

@implementation PKNectar
@end

// One row per stack in the honeyBall storage (Items: List<Predicted<InventoryItem>>);
// the confirmed side is what the server holds, the predicted side is what the
// player sees after their own pending actions. Plain values only.
@interface PKNectarRow : NSObject
@property (nonatomic, copy) NSString *itemId, *flowerName;
@property (nonatomic) int confirmed, predicted, type, hkind;
@end
@implementation PKNectarRow
@end

static NSArray<PKNectarRow *> *scanRows(void) {
    void *inv = pkInv();
    if (!inv || !pkRuntimeReady()) return @[];
    NSMutableArray<PKNectarRow *> *rows = [NSMutableArray array];
    void *items = pkGetPtr(pkGetPtr(inv, &F_Inv_honey), &F_Stor_items);
    pkListEach(items, ^(void *pred) {
        void *conf = pkGetPtr(pred, &F_Pred_conf), *prd = pkGetPtr(pred, &F_Pred_pred);
        void *item = conf ?: prd;
        void *proto = item ? pkItemProto(item) : NULL;
        if (!proto) return;
        PKNectarRow *r = [PKNectarRow new];
        r.itemId = pkItemId(item);
        r.confirmed = pkGetInt(proto, &F_HB_balls);
        r.predicted = r.confirmed;
        if (prd) { void *pp = pkItemProto(prd); r.predicted = pp ? pkGetInt(pp, &F_HB_balls) : 0; }
        r.type = pkGetInt(proto, &F_HB_type);
        r.hkind = pkGetInt(proto, &F_HB_hkind);
        r.flowerName = pkGetStr(proto, &F_HB_fkind);
        [rows addObject:r];
    });
    return rows;
}

// The feed, plant and selection code all read the nectar within one tick:
// scan once per frame.
static NSArray<PKNectarRow *> *gRowsFrame = nil;
static NSArray<PKNectarRow *> *rows(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pkFrameOnReset(^{ gRowsFrame = nil; }); });
    if (!pkFrameActive()) return scanRows();
    if (!gRowsFrame) gRowsFrame = scanRows();
    return gRowsFrame;
}

// Colours we may spend: the four common ones. HAPPY (rainbow, 5) and UNKNOWN (0) are kept.
static BOOL spendable(int honeyType) { return honeyType >= 1 && honeyType <= 4; }

NSArray<PKNectar *> *pkNectarList(void) {
    NSMutableArray<PKNectar *> *out = [NSMutableArray array];
    long long conf[8] = {0}, pred[8] = {0};
    for (PKNectarRow *r in rows()) {
        if (r.type >= 0 && r.type < 8) { conf[r.type] += MAX(r.confirmed, 0); pred[r.type] += MAX(r.predicted, 0); }
        if (!r.itemId.length || r.predicted <= 0 || r.predicted >= 100000 || !spendable(r.type)) continue;
        PKNectar *h = [PKNectar new];
        h.itemId = r.itemId; h.balls = r.predicted; h.type = r.type; h.hkind = r.hkind;
        h.kindName = r.flowerName ?: @"";
        h.special = pkNectarIsSpecial(r.flowerName, r.hkind);
        [out addObject:h];
    }
    PKLOGC(@"nectar.hist", ([NSString stringWithFormat:@"[nectar] conf W%lld R%lld B%lld Y%lld H%lld | pred W%lld R%lld B%lld Y%lld H%lld",
                             conf[1], conf[2], conf[3], conf[4], conf[5], pred[1], pred[2], pred[3], pred[4], pred[5]]));
    return out;
}

void pkNectarPlainByColor(long long out[8]) {
    memset(out, 0, 8 * sizeof(long long));
    for (PKNectarRow *r in rows())
        if (r.type >= 0 && r.type < 8 && r.predicted > 0 && r.flowerName.length == 0) out[r.type] += r.predicted;
}
