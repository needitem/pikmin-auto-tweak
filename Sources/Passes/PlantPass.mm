#import "Passes.h"
#import "Clock.h"
#import "GameContext.h"
#import "Layout.h"
#import "Log.h"
#import "Nectar.h"
#import "Petals.h"

// Keep a planting session running. The game's own FlowerPlantingController
// starts it exactly as the 심기 button does; from then on the game itself sends
// PlantFlower as the (spoofed) location moves and stops when petals run out.
//
// Petal choice: plain petals only (special kinds are kept for decor), and of
// those the stack we hold the MOST of — the biggest stock is spent first.
// Is a planting session live? Asked of the controller's own state, not of a
// field: `isStarted` only says the controller finished initialising (it is
// true from launch — reading it made every pass think a session was running,
// so a session was never started). IsPlanting is a reactive property whose
// .Value is the bool; IsStartingPlanting covers the moment between the request
// and the session going live.
static BOOL sessionLive(void *plant, BOOL *known) {
    *known = pkMethodOf(plant, "get_IsPlanting", 0) != NULL;
    void *prop = pkCall0(plant, "get_IsPlanting");
    BOOL planting = prop && pkUnboxBool(pkCall0(prop, "get_Value"));
    BOOL starting = pkUnboxBool(pkCall0(plant, "get_IsStartingPlanting"));
    return planting || starting;
}

NSString *pkPlantPass(void) {
    void *plant = pkPlant();
    if (!plant) return @"심기 컨트롤러 대기 (지도 화면이 뜨면 잡힘)";
    if (!pkRpc() || !pkInv()) return @"서버 준비 대기";

    BOOL known = NO;
    BOOL started = sessionLive(plant, &known);
    if (!known) return @"🌱 세션 상태 getter 없음 — 이중 시작을 막으려 시작 안 함";
    NSArray<PKPetal *> *petals = pkPetalList();
    long long plain = 0, special = 0;
    for (PKPetal *p in petals) (p.special ? special : plain) += p.num;

    static NSTimeInterval lastCensus = -1e9;
    if (pkMono() - lastCensus > 300) {                       // what we hold, every 5 min
        lastCensus = pkMono();
        NSMutableArray *bits = [NSMutableArray array];
        for (PKPetal *p in petals)
            [bits addObject:[NSString stringWithFormat:@"c%dk%d[%@]x%d%@", p.color, p.kind, p.flowerName, p.num, p.special ? @"*" : @""]];
        PALOG(@"[심기] 꽃잎 재고: %@", [bits componentsJoinedByString:@" "]);
    }
    if (started) return [NSString stringWithFormat:@"🌱 심는 중 (일반 꽃잎 %lld, 특수 %lld)", plain, special];
    if (plain <= 0) return [NSString stringWithFormat:@"🌱 일반 꽃잎 없음 (특수 %lld 보존)", special];

    PKPetal *best = nil;
    for (PKPetal *p in petals) {
        if (p.special) continue;
        // Most petals first; the id breaks ties so the choice is stable.
        if (!best || p.num > best.num || (p.num == best.num && [p.itemId compare:best.itemId] == NSOrderedAscending)) best = p;
    }
    if (!best) return @"🌱 쓸 꽃잎 없음";

    // A start that did not turn into a live session (no permission, refused) is
    // not retried every pass.
    static NSTimeInterval lastStart = -1e9;
    if (pkMono() - lastStart < 60) return @"🌱 시작 요청 후 대기 중";
    void *m = pkMethodOf(plant, "StartPlantingWithConfirmationAsync", 2);
    if (!m) return @"StartPlantingWithConfirmationAsync 없음";
    unsigned char confirm = 0;
    void *a[2] = { pkNewString(best.itemId), &confirm };
    BOOL ok = NO;
    pkInvokeEx(m, plant, a, &ok);
    lastStart = pkMono();
    PALOG(@"[심기] 시작 petal=%@ color=%d kind=%d num=%d (가장 많은 일반 꽃잎) ok=%d", best.itemId, best.color, best.kind, best.num, ok);
    return ok ? [NSString stringWithFormat:@"🌱 심기 시작 — 색 %d 꽃잎 %d장", best.color, best.num] : @"🌱 심기 시작 실패";
}
