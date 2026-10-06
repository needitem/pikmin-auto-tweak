#import "NectarSelection.h"
#import "GameContext.h"
#import "HandFed.h"
#import "Layout.h"
#import "Log.h"
#import "Nectar.h"
#import "Settings.h"

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
    NSString *fed = pkTakeHandFed();
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
