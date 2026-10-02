#import "TroopPlan.h"
#import "GameConstants.h"

const int kTroopEliteQuota = 40;
static const float kHeartsFull = 8.0f;          // yellow hearts maxed
static const float kHeartsRed = PK_HEARTS_TARGET;   // the red maximum: 4

static const char *const kColorNames[9] = { "미상", "빨강", "파랑", "노랑", "하양", "보라", "바위", "날개", "얼음" };
static const char *colorName(int c) { return kColorNames[(c >= 1 && c <= 8) ? c : 0]; }

// Most hearts first; costume Pikmin first among equals; the id keeps it stable.
static NSComparisonResult byHearts(PKPikmin *a, PKPikmin *b) {
    if (a.hearts != b.hearts) return a.hearts > b.hearts ? NSOrderedAscending : NSOrderedDescending;
    if (a.isDecor != b.isDecor) return a.isDecor ? NSOrderedAscending : NSOrderedDescending;
    return [a.pid compare:b.pid];
}

@interface PKTroopGroup : NSObject
@property (nonatomic) int color;
@property (nonatomic) BOOL build;                   // BUILD (to 4 hearts) or MASTER (to 8)
@property (nonatomic) double weight;
@property (nonatomic, copy) NSArray<PKPikmin *> *candidates;
@property (nonatomic, copy) NSArray<PKPikmin *> *elite;
@property (nonatomic) NSUInteger taken;
@end
@implementation PKTroopGroup
@end

// One group per colour. `canMove` limits the candidates to Pikmin that can be
// moved now; nil means everyone (the standing, not the plan for this moment).
static NSArray<PKTroopGroup *> *makeGroups(NSArray<PKPikmin *> *roster, NSSet<NSString *> *canMove) {
    NSMutableDictionary<NSNumber *, NSMutableArray<PKPikmin *> *> *byColor = [NSMutableDictionary dictionary];
    for (PKPikmin *p in roster) {
        NSMutableArray *a = byColor[@(p.color)];
        if (!a) { a = [NSMutableArray array]; byColor[@(p.color)] = a; }
        [a addObject:p];
    }
    NSMutableArray<PKTroopGroup *> *groups = [NSMutableArray array];
    for (NSNumber *key in [byColor.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSMutableArray<PKPikmin *> *all = byColor[key];
        [all sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) { return byHearts(a, b); }];
        NSUInteger quota = MIN((NSUInteger)kTroopEliteQuota, all.count);     // a small colour is all elite
        NSUInteger n4 = 0;
        for (PKPikmin *p in all) if (p.hearts >= kHeartsRed) n4++;
        PKTroopGroup *g = [PKTroopGroup new];
        g.color = key.intValue;
        g.build = n4 < quota;
        float goal = g.build ? kHeartsRed : kHeartsFull;
        g.elite = [all subarrayWithRange:NSMakeRange(0, quota)];
        NSMutableArray<PKPikmin *> *cands = [NSMutableArray array];
        for (PKPikmin *p in g.elite)
            if (p.hearts < goal && (!canMove || [canMove containsObject:p.pid])) [cands addObject:p];
        g.candidates = cands;
        g.weight = !cands.count ? 0.0 : g.build ? 1.0 + (double)(quota - n4) / (double)quota : 1.0;
        [groups addObject:g];
    }
    return groups;
}

void pkTroopStanding(NSArray<PKPikmin *> *roster, NSSet<NSString *> **elite, NSSet<NSString *> **training) {
    NSMutableSet<NSString *> *e = [NSMutableSet set], *t = [NSMutableSet set];
    for (PKTroopGroup *g in makeGroups(roster, nil)) {
        for (PKPikmin *p in g.elite) [e addObject:p.pid];
        for (PKPikmin *p in g.candidates) [t addObject:p.pid];
    }
    if (elite) *elite = e;
    if (training) *training = t;
}

NSArray<PKPikmin *> *pkTroopPlan(NSArray<PKPikmin *> *roster, NSArray<PKPikmin *> *movable,
                                 NSUInteger slots, NSString **summary) {
    NSMutableSet<NSString *> *canMove = [NSMutableSet set];
    for (PKPikmin *p in movable) [canMove addObject:p.pid];
    NSArray<PKTroopGroup *> *groups = makeGroups(roster, canMove);

    // D'Hondt: each place goes to the group with the best weight / (places + 1).
    NSMutableArray<PKPikmin *> *chosen = [NSMutableArray array];
    NSMutableSet<NSString *> *chosenIds = [NSMutableSet set];
    while (chosen.count < slots) {
        PKTroopGroup *best = nil; double bestScore = 0;
        for (PKTroopGroup *g in groups) {
            if (g.taken >= g.candidates.count || g.weight <= 0) continue;
            double score = g.weight / (double)(g.taken + 1);
            if (score > bestScore) { best = g; bestScore = score; }        // ties: the lower colour id
        }
        if (!best) break;
        PKPikmin *p = best.candidates[best.taken++];
        [chosen addObject:p]; [chosenIds addObject:p.pid];
    }

    // Nobody above wants the rest of the places: the best of whoever is left,
    // maxed Pikmin last (walking gains them nothing).
    NSUInteger planned = chosen.count;
    if (chosen.count < slots) {
        NSMutableArray<PKPikmin *> *rest = [NSMutableArray array];
        for (PKPikmin *p in movable) if (![chosenIds containsObject:p.pid]) [rest addObject:p];
        [rest sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) {
            BOOL ma = a.hearts >= kHeartsFull, mb = b.hearts >= kHeartsFull;
            if (ma != mb) return ma ? NSOrderedDescending : NSOrderedAscending;
            return byHearts(a, b);
        }];
        for (PKPikmin *p in rest) { if (chosen.count >= slots) break; [chosen addObject:p]; }
    }

    if (summary) {
        NSMutableArray *bits = [NSMutableArray array];
        for (PKTroopGroup *g in groups)
            if (g.taken) [bits addObject:[NSString stringWithFormat:@"%@ %lu→%d", @(colorName(g.color)), (unsigned long)g.taken, g.build ? 4 : 8]];
        [bits addObject:[NSString stringWithFormat:@"기타 %lu", (unsigned long)(chosen.count - planned)]];
        *summary = [bits componentsJoinedByString:@", "];
    }
    return chosen;
}
