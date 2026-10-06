#import "Passes.h"
#import "Clock.h"
#import "GameContext.h"
#import "Layout.h"
#import "Log.h"
#import "Nectar.h"
#import "Petals.h"
#import "PlantPlan.h"

// Keep a planting session running on the plain petal stack we hold the MOST of.
// The game's own FlowerPlantingController starts it exactly as the 심기 button
// does; from then on the game itself sends PlantFlower as the (spoofed) location
// moves and stops when the petals run out.
//
// What to do each pass (start, keep, switch to a bigger stack, leave a hand-started
// session alone) is decided in Model/PlantPlan; this pass reads the controller's
// state, applies the decision, and remembers when it last asked to start or stop.
// Only plain petals are used (special kinds are kept for decor).
static NSString *gPlantingId = nil;               // the stack our running session spends
static NSTimeInterval gLastStart = -1e9, gLastStop = -1e9;

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

// What we hold, every 5 minutes.
static void logCensus(NSArray<PKPetal *> *petals) {
    static NSTimeInterval lastCensus = -1e9;
    if (pkMono() - lastCensus <= 300) return;
    lastCensus = pkMono();
    NSMutableArray *bits = [NSMutableArray array];
    for (PKPetal *p in petals)
        [bits addObject:[NSString stringWithFormat:@"c%dk%d[%@]x%d%@", p.color, p.kind, p.flowerName, p.num, p.special ? @"*" : @""]];
    PALOG(@"[심기] 꽃잎 재고: %@", [bits componentsJoinedByString:@" "]);
}

NSString *pkPlantPass(void) {
    void *plant = pkPlant();
    if (!plant) return @"심기 컨트롤러 대기 (지도 화면이 뜨면 잡힘)";
    if (!pkRpc() || !pkInv()) return @"서버 준비 대기";

    BOOL known = NO;
    BOOL live = sessionLive(plant, &known);
    if (!known) return @"🌱 세션 상태 getter 없음 — 이중 시작을 막으려 시작 안 함";
    NSArray<PKPetal *> *petals = pkPetalList();
    long long plain = 0, special = 0;
    for (PKPetal *p in petals) (p.special ? special : plain) += p.num;
    PKPetal *best = pkBiggestPlain(petals);
    logCensus(petals);

    PKPlantInputs in = { live, gPlantingId, pkMono(), gLastStart, gLastStop };
    PKPlantDecision d = pkPlantDecide(petals, in);
    if (d.forgetOurStack) gPlantingId = nil;
    PKPetal *cur = gPlantingId ? pkStackById(petals, gPlantingId) : nil;

    switch (d.action) {
        case PKPlantLeaveAlone:
            return [NSString stringWithFormat:@"🌱 심는 중 — 직접 시작한 세션이라 그대로 둠 (일반 %lld, 특수 %lld)", plain, special];
        case PKPlantKeep:
            return [NSString stringWithFormat:@"🌱 심는 중 %@ %d장 (최다 %d장, 일반 %lld, 특수 %lld)",
                    cur ? [NSString stringWithFormat:@"색%d", cur.color] : @"?", cur ? cur.num : 0, best ? best.num : 0, plain, special];
        case PKPlantSwitchWait:
            return @"🌱 전환 대기 (중지 요청 후)";
        case PKPlantSwitch: {
            gLastStop = pkMono();
            BOOL ok = NO;
            pkInvokeEx(pkMethodOf(plant, "StopPlanting", 0), plant, NULL, &ok);
            PALOG(@"[심기] 전환: 현재 %@(색%d k%d %d장) → %@(색%d k%d %d장) 차이 %d ≥ %d, 중지 요청 ok=%d",
                  cur.itemId, cur.color, cur.kind, cur.num, best.itemId, best.color, best.kind, best.num,
                  best.num - cur.num, kPlantSwitchMargin, ok);
            return ok ? @"🌱 더 많은 꽃잎으로 전환 — 세션 중지 요청" : @"🌱 세션 중지 실패";
        }
        case PKPlantNoPlain:  return [NSString stringWithFormat:@"🌱 일반 꽃잎 없음 (특수 %lld 보존)", special];
        case PKPlantNoStack:  return @"🌱 쓸 꽃잎 없음";
        case PKPlantStartWait: return @"🌱 시작 요청 후 대기 중";
        case PKPlantStart: break;
    }

    void *m = pkMethodOf(plant, "StartPlantingWithConfirmationAsync", 2);
    if (!m) return @"StartPlantingWithConfirmationAsync 없음";
    unsigned char confirm = 0;
    void *a[2] = { pkNewString(best.itemId), &confirm };
    BOOL ok = NO;
    pkInvokeEx(m, plant, a, &ok);
    gLastStart = pkMono();
    if (ok) gPlantingId = best.itemId;
    PALOG(@"[심기] 시작 petal=%@ color=%d kind=%d num=%d (가장 많은 일반 꽃잎) ok=%d", best.itemId, best.color, best.kind, best.num, ok);
    return ok ? [NSString stringWithFormat:@"🌱 심기 시작 — 색 %d 꽃잎 %d장", best.color, best.num] : @"🌱 심기 시작 실패";
}
