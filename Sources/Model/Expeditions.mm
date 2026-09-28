#import "Expeditions.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Inventory.h"
#import "Layout.h"

#define NS_EXPEDITION "Niantic.Ichigo.Game.Expedition.Data"

NSArray<NSValue *> *pkExpeditionItems(void) {
    void *store = pkExpStore();
    if (!store || !pkRuntimeReady()) return nil;
    // The store also holds blockers (mushroom invites) and fakes: keep only the
    // real ExpeditionItemData.
    void *eidCls = pkClass(NS_EXPEDITION, "ExpeditionItemData");
    if (!eidCls) return nil;
    NSMutableArray<NSValue *> *out = [NSMutableArray array];
    pkDictEachValue(pkGetPtr(store, &F_ExpStore_cache), ^(void *v) {
        if (pkClassOf(v) == eidCls) [out addObject:[NSValue valueWithPointer:v]];
    });
    return out;
}

int pkExpeditionState(void *d) { return pkUnboxInt(pkCall0(d, "get_State")); }
NSString *pkExpeditionKey(void *d) { return pkStr(pkCall0(d, "get_Key")); }

void *pkExpeditionTaskProto(void *d) {
    void *item = pkGetPtr(d, &F_ExpItem_item);              // PikminTaskInventoryItem
    return item ? pkItemProto(item) : NULL;
}
NSString *pkExpeditionTaskId(void *d) {
    void *item = pkGetPtr(d, &F_ExpItem_item);
    return item ? pkItemId(item) : nil;
}

NSSet<NSString *> *pkReturnedExpeditionIds(void) {
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (NSValue *v in pkExpeditionItems()) {
        void *d = v.pointerValue;
        if (pkExpeditionState(d) != PK_EXP_RETURNED) continue;
        NSString *tid = pkExpeditionTaskId(d);
        if (tid.length) [ids addObject:tid];
    }
    return ids;
}

NSArray<NSString *> *pkExpeditionParty(void *d) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    pkRepeatedEach(pkGetPtr(pkExpeditionTaskProto(d), &F_Task_pikmin), ^(void *s) {
        NSString *pid = pkStr(s);
        if (pid) [out addObject:pid];
    });
    return out;
}

// The body of ExpeditionItemData.SetPikmins minus its "already started" guard
// (callers only touch tasks they have just confirmed are unstarted).
void pkExpeditionSetParty(void *d, NSArray<NSString *> *pids) {
    void *rf = pkGetPtr(pkExpeditionTaskProto(d), &F_Task_pikmin);
    if (!rf) return;
    pkRepeatedClear(rf);
    for (NSString *pid in pids) pkRepeatedAdd(rf, pkNewString(pid));
    pkInvoke(pkMethodOf(d, "InvalidateAllCachedValues", 0), d, NULL);
}

void pkExpeditionAddToParty(void *d, NSString *pid) {
    void *rf = pkGetPtr(pkExpeditionTaskProto(d), &F_Task_pikmin);
    if (!rf) return;
    pkRepeatedAdd(rf, pkNewString(pid));
    pkInvoke(pkMethodOf(d, "InvalidateAllCachedValues", 0), d, NULL);
}
