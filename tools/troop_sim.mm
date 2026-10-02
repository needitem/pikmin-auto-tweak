// Offline check of the troop strategy against a roster dump.
//   clang++ -std=gnu++17 -fobjc-arc -framework Foundation -ISources/Model -ISources/Game \
//       Sources/Model/TroopPlan.mm tools/troop_sim.mm -o /tmp/troop_sim
//   /tmp/troop_sim <roster.json> [troopSize=38]
// Compares the new plan with the previous 4-tier rule on the snapshot, then
// replays both over many rounds with an ASSUMED equal heart gain per troop
// member per round — the gain rate is unknown, so only the shape of the
// outcome (who gets raised) means anything, not the round numbers.
#import <Foundation/Foundation.h>
#import "Roster.h"
#import "TroopPlan.h"

@implementation PKPikmin
- (BOOL)isDecor { return _asset >= 2; }
@end

static const char *const kNames[9] = { "미상", "빨강", "파랑", "노랑", "하양", "보라", "바위", "날개", "얼음" };

// The rule this replaced: decor<4, plain<4, decor>=4, plain>=4; closest to 4 first inside a tier.
static NSArray<PKPikmin *> *legacyPlan(NSArray<PKPikmin *> *elig, NSUInteger slots) {
    int (^tier)(PKPikmin *) = ^int(PKPikmin *p) { return p.hearts < 4 ? (p.isDecor ? 1 : 2) : (p.isDecor ? 3 : 4); };
    NSArray *s = [elig sortedArrayUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) {
        int ta = tier(a), tb = tier(b);
        if (ta != tb) return ta < tb ? NSOrderedAscending : NSOrderedDescending;
        if (a.hearts != b.hearts) return a.hearts > b.hearts ? NSOrderedAscending : NSOrderedDescending;
        return [a.pid compare:b.pid];
    }];
    return s.count > slots ? [s subarrayWithRange:NSMakeRange(0, slots)] : s;
}

static void census(NSArray<PKPikmin *> *all, const char *title) {
    int n4[9] = {0}, n8[9] = {0}, tot[9] = {0};
    for (PKPikmin *p in all) { int c = (p.color >= 1 && p.color <= 8) ? p.color : 0; tot[c]++; if (p.hearts >= 4) n4[c]++; if (p.hearts >= 8) n8[c]++; }
    printf("  %-9s", title);
    for (int c = 1; c <= 8; c++) printf(" %s %2d/%d", kNames[c], n4[c], n8[c]);
    printf("\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: troop_sim roster.json [troop]\n"); return 1; }
        NSUInteger troop = argc > 2 ? (NSUInteger)atoi(argv[2]) : 38;
        NSDictionary *doc = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
        NSMutableArray<PKPikmin *> *all = [NSMutableArray array];
        for (NSDictionary *d in doc[@"pikmin"]) {
            PKPikmin *p = [PKPikmin new];
            p.pid = [NSString stringWithFormat:@"%@", d[@"name"]];
            p.color = [d[@"color"] intValue]; p.hearts = [d[@"hearts"] floatValue];
            p.asset = [d[@"asset"] intValue]; p.status = [d[@"status"] intValue];
            [all addObject:p];
        }
        NSPredicate *idle = [NSPredicate predicateWithBlock:^BOOL(PKPikmin *p, id _) { return p.status != 2; }];
        NSArray<PKPikmin *> *movable = [all filteredArrayUsingPredicate:idle];
        printf("로스터 %lu마리 (이동 가능 %lu), 부대 %lu\n\n", (unsigned long)all.count, (unsigned long)movable.count, (unsigned long)troop);

        NSString *summary = nil;
        NSArray<PKPikmin *> *neu = pkTroopPlan(all, movable, troop, &summary);
        NSArray<PKPikmin *> *old = legacyPlan(movable, troop);
        printf("[스냅샷] 이번에 부대에 넣을 38마리\n  새 전략: %s\n", summary.UTF8String);
        for (int pass = 0; pass < 2; pass++) {
            NSArray *sel = pass ? old : neu;
            int byc[9] = {0}; float sum = 0; int low = 0, decor = 0;
            for (PKPikmin *p in sel) { byc[(p.color >= 1 && p.color <= 8) ? p.color : 0]++; sum += p.hearts; if (p.hearts < 2) low++; if (p.isDecor) decor++; }
            printf("  %s: 색별", pass ? "이전 4티어" : "새 전략   ");
            for (int c = 1; c <= 8; c++) printf(" %s%d", kNames[c], byc[c]);
            printf(" | 평균 하트 %.2f, 2하트 미만 %d마리, 데코 %d마리\n", sum / sel.count, low, decor);
        }

        // Replay: every troop member gains the same hearts each round (assumption).
        const float gain = 0.02f;
        printf("\n[재생] 라운드마다 부대원 +%.2f 하트(가정). 각 칸은 '4하트 이상 / 8하트' 마릿수\n", gain);
        for (int pass = 0; pass < 2; pass++) {
            NSMutableArray<PKPikmin *> *sim = [NSMutableArray array];
            for (PKPikmin *p in all) { PKPikmin *q = [PKPikmin new]; q.pid = p.pid; q.color = p.color; q.hearts = p.hearts; q.asset = p.asset; q.status = p.status; [sim addObject:q]; }
            printf(" %s\n", pass ? "이전 4티어" : "새 전략");
            census(sim, "시작");
            NSSet<NSString *> *prev = nil; long swaps = 0, worst = 0;
            for (int round = 1; round <= 600; round++) {
                NSArray *mv = [sim filteredArrayUsingPredicate:idle];
                NSArray<PKPikmin *> *sel = pass ? legacyPlan(mv, troop) : pkTroopPlan(sim, mv, troop, NULL);
                NSSet<NSString *> *now = [NSSet setWithArray:[sel valueForKey:@"pid"]];
                if (prev) { NSMutableSet *in = [now mutableCopy]; [in minusSet:prev]; swaps += in.count; worst = MAX(worst, (long)in.count); }
                prev = now;
                for (PKPikmin *p in sel) p.hearts = MIN(8.0f, p.hearts + gain);
                if (round == 150 || round == 300 || round == 600) { char t[16]; snprintf(t, sizeof t, "%d라운드", round); census(sim, t); }
            }
            printf("  교체: 라운드당 평균 %.2f마리 들어옴 (최대 %ld)\n", swaps / 599.0, worst);
        }
    }
    return 0;
}
