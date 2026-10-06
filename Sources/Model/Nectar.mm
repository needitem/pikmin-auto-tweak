#import "Nectar.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Frame.h"
#import "Inventory.h"
#import "Layout.h"
#import "Log.h"
#import "Settings.h"
#import <os/lock.h>

@implementation PKNectar
@end

BOOL pkNectarIsSpecial(NSString *flowerName, int hkind) {
    return flowerName.length > 0 || (hkind != 0 && hkind != PK_HONEY_COMMON_FLOWER_KIND);
}

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

// ---------- the player's choice ----------
// The hook that notices a hand feed runs inside the game, so it only copies the
// id's UTF-16 into a fixed buffer under a short lock; the string object is made
// here, on the main thread, when the feed pass asks.
static const int kFedCap = 96;
static os_unfair_lock gFedLock = OS_UNFAIR_LOCK_INIT;
static unichar gFedChars[kFedCap];
static int gFedLen = 0;

void pkNoteHandFedRaw(void *il2cppItemIdString) {
    unichar tmp[kFedCap];
    int n = pkStrCopy(il2cppItemIdString, tmp, kFedCap);
    if (n <= 0) return;
    os_unfair_lock_lock(&gFedLock);
    memcpy(gFedChars, tmp, (size_t)n * sizeof(unichar));
    gFedLen = n;
    os_unfair_lock_unlock(&gFedLock);
}
static NSString *takeHandFed(void) {
    unichar tmp[kFedCap];
    os_unfair_lock_lock(&gFedLock);
    int n = gFedLen;
    memcpy(tmp, gFedChars, (size_t)n * sizeof(unichar));
    gFedLen = 0;
    os_unfair_lock_unlock(&gFedLock);
    return n > 0 ? [NSString stringWithCharacters:tmp length:(NSUInteger)n] : nil;
}

// The chosen stack, however we came by it: its item id pins the exact stack
// (colour included). A plain colour nectar clears the pin.
static void pin(NSString *itemId, BOOL special, NSString *kindName, int hkind, int type, NSString *how) {
    if (!special) {
        if ([PKSettings stringForKey:kSettingSpecial] || [PKSettings stringForKey:kSettingSpecialId]) {
            [PKSettings setString:nil forKey:kSettingSpecial];
            [PKSettings setString:nil forKey:kSettingSpecialId];
            PALOG(@"[feed] 특수정수 지정 해제 — 일반 정수를 %@", how);
        }
        return;
    }
    if ([[PKSettings stringForKey:kSettingSpecialId] isEqualToString:itemId]) return;
    NSString *kind = kindName.length ? kindName : [NSString stringWithFormat:@"kind%d", hkind];
    [PKSettings setString:kind forKey:kSettingSpecial];
    [PKSettings setString:itemId forKey:kSettingSpecialId];
    PALOG(@"[feed] 특수정수 지정: %@ (색%d, id=%@) — %@", kind, type, itemId, how);
}

// The flower is on the Extract itself (flowerKind: id "lisianthus" + enum);
// honeyBallType carries a kind too but comes back empty for the reel's entries.
static void readExtract(void *ex, int *color, int *hkind, NSString **fkind) {
    *color = pkGetInt(ex, &F_Ex_color);
    void *fk = pkGetPtr(ex, &F_Ex_kind);
    if (fk) {
        *fkind = pkGetStr(fk, &F_FK_id);
        *hkind = pkGetInt(fk, &F_FK_kind);
    }
    if (!(*fkind).length) {
        void *hbt = pkGetPtr(ex, &F_Ex_hbt);
        if (hbt) {
            if (!*hkind) *hkind = pkGetInt(hbt, &F_HBT_hkind);
            *fkind = pkGetStr(hbt, &F_HBT_fkind);
        }
    }
}

static void pinFromExtract(void *ex) {
    int color = 0, hkind = 0; NSString *fkind = nil;
    readExtract(ex, &color, &hkind, &fkind);
    if (!pkNectarIsSpecial(fkind, hkind)) { pin(@"", NO, nil, 0, color, @"골랐음"); return; }
    // Match on colour and the flower's NAME: the catalog's FlowerKind number and
    // the inventory's honeyFlowerKind_ are different encodings.
    NSArray<PKNectar *> *held = pkNectarList();
    for (PKNectar *h in held) {
        if (h.type != color) continue;
        if (fkind.length && [h.kindName caseInsensitiveCompare:fkind] != NSOrderedSame) continue;
        if (!fkind.length && h.hkind != hkind) continue;
        pin(h.itemId, YES, h.kindName, h.hkind, color, @"골랐음");
        return;
    }
    for (PKNectar *h in held) {                                   // same flower, any colour
        if (!fkind.length || [h.kindName caseInsensitiveCompare:fkind] != NSOrderedSame) continue;
        pin(h.itemId, YES, h.kindName, h.hkind, h.type, @"골랐음(색 불일치)");
        return;
    }
    NSMutableArray *bits = [NSMutableArray array];
    for (PKNectar *h in held) [bits addObject:[NSString stringWithFormat:@"색%d/k%d/'%@'x%d", h.type, h.hkind, h.kindName, h.balls]];
    PKLOGC(@"sel.miss", ([NSString stringWithFormat:@"[feed] 고른 정수(색%d k%d '%@')를 보유목록에서 못 찾음. 보유: %@",
                          color, hkind, fkind ?: @"", [bits componentsJoinedByString:@" "]]));
}

void pkNectarSyncSelection(void) {
    NSString *fed = takeHandFed();
    if (fed) {
        for (PKNectar *h in pkNectarList())
            if ([h.itemId isEqualToString:fed]) { pin(fed, h.special, h.kindName, h.hkind, h.type, @"손으로 줌"); break; }
    }
    void *tracker = pkExtract();
    if (!tracker || !pkRuntimeReady()) return;
    // Re-picking the already-selected nectar never calls SetExtract, so the
    // selection is read outright: MostRecent is what the next throw would use.
    void *ex = pkCall0(tracker, "get_MostRecent");
    if (!ex) { PKLOGC(@"sel.none", @"[feed] 게임에 선택된 정수 없음 — 보유량 기준 자동 선택"); return; }
    pinFromExtract(ex);
}
