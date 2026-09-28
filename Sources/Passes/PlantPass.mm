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
// Petal choice: plain petals only (special kinds are kept for decor); colour =
// whichever of white/red/blue/yellow we hold the least nectar of, among the
// colours we have petals for. FlowerProto.Type FLOWER_0..3 (1..4) line up with
// HoneyType WHITE/RED/BLUE/YELLOW (1..4).
NSString *pkPlantPass(void) {
    void *plant = pkPlant();
    if (!plant) return @"심기 컨트롤러 대기 (지도 화면이 뜨면 잡힘)";
    if (!pkRpc() || !pkInv()) return @"서버 준비 대기";

    BOOL started = pkGetBool(plant, &F_Plant_started);
    NSArray<PKPetal *> *petals = pkPetalList();
    long long plain = 0, special = 0;
    for (PKPetal *p in petals) (p.special ? special : plain) += p.num;

    static NSTimeInterval lastCensus = -1e9;
    if (pkMono() - lastCensus > 300) {                       // what we hold, every 5 min
        lastCensus = pkMono();
        NSMutableArray *bits = [NSMutableArray array];
        for (PKPetal *p in petals)
            [bits addObject:[NSString stringWithFormat:@"c%dk%dx%d%@", p.color, p.kind, p.num, p.special ? @"*" : @""]];
        PALOG(@"[심기] 꽃잎 재고: %@", [bits componentsJoinedByString:@" "]);
    }
    if (started) return [NSString stringWithFormat:@"🌱 심는 중 (일반 꽃잎 %lld, 특수 %lld)", plain, special];
    if (plain <= 0) return [NSString stringWithFormat:@"🌱 일반 꽃잎 없음 (특수 %lld 보존)", special];

    long long nectar[8];
    pkNectarPlainByColor(nectar);
    PKPetal *best = nil; long long bestNectar = 0;
    for (PKPetal *p in petals) {
        if (p.special) continue;
        long long n = (p.color >= 1 && p.color <= 4) ? nectar[p.color] : LLONG_MAX;
        if (!best || n < bestNectar || (n == bestNectar && p.num > best.num)) { best = p; bestNectar = n; }
    }
    if (!best) return @"🌱 쓸 꽃잎 없음";

    void *m = pkMethodOf(plant, "StartPlantingWithConfirmationAsync", 2);
    if (!m) return @"StartPlantingWithConfirmationAsync 없음";
    unsigned char confirm = 0;
    void *a[2] = { pkNewString(best.itemId), &confirm };
    BOOL ok = NO;
    pkInvokeEx(m, plant, a, &ok);
    PALOG(@"[심기] 시작 petal=%@ color=%d num=%d (정수 W%lld R%lld B%lld Y%lld) ok=%d",
          best.itemId, best.color, best.num, nectar[1], nectar[2], nectar[3], nectar[4], ok);
    return ok ? [NSString stringWithFormat:@"🌱 심기 시작 — 색 %d 꽃잎 %d장", best.color, best.num] : @"🌱 심기 시작 실패";
}
