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
@property (nonatomic) double need;
@property (nonatomic, copy) NSArray<PKPikmin *> *elite;          // top quota by hearts
@property (nonatomic, copy) NSArray<PKPikmin *> *decorLow;       // movable costume Pikmin under 4 hearts
@property (nonatomic, copy) NSArray<PKPikmin *> *eliteCands;     // movable elite under 8 hearts, not already in decorLow
@property (nonatomic) NSUInteger taken, takenDecor, takenElite;
@end
@implementation PKTroopGroup
@end

// One group per colour. `canMove` limits the candidates to Pikmin that can be
// moved now; nil means everyone.
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
        g.need = (double)(quota - MIN(n4, quota)) / (double)MAX(quota, (NSUInteger)1);
        g.elite = [all subarrayWithRange:NSMakeRange(0, quota)];

        NSMutableArray<PKPikmin *> *low = [NSMutableArray array];
        NSMutableSet<NSString *> *inLow = [NSMutableSet set];
        for (PKPikmin *p in all)                                              // `all` is already hearts-descending
            if (p.isDecor && p.hearts < kHeartsRed && (!canMove || [canMove containsObject:p.pid])) { [low addObject:p]; [inLow addObject:p.pid]; }
        g.decorLow = low;
        // Inside a colour: the elite still under 4 hearts first (so the colour
        // really has a full quota at 4+), then the rest toward 8 — each part
        // closest-to-goal first (`elite` is hearts-descending).
        NSMutableArray<PKPikmin *> *under4 = [NSMutableArray array], *toEight = [NSMutableArray array];
        for (PKPikmin *p in g.elite) {
            if (p.hearts >= kHeartsFull || [inLow containsObject:p.pid] || (canMove && ![canMove containsObject:p.pid])) continue;
            [(p.hearts < kHeartsRed ? under4 : toEight) addObject:p];
        }
        g.eliteCands = [under4 arrayByAddingObjectsFromArray:toEight];
        [groups addObject:g];
    }
    return groups;
}

NSDictionary<NSNumber *, NSNumber *> *pkColorNeed(NSArray<PKPikmin *> *roster) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (PKTroopGroup *g in makeGroups(roster, nil)) out[@(g.color)] = @(g.need);
    return out;
}

NSSet<NSString *> *pkTroopElite(NSArray<PKPikmin *> *roster) {
    NSMutableSet<NSString *> *e = [NSMutableSet set];
    for (PKTroopGroup *g in makeGroups(roster, nil)) for (PKPikmin *p in g.elite) [e addObject:p.pid];
    return e;
}

// Hand out places from the groups' lists, each time to the colour that has
// received the fewest so far for its weight (ties: the lower colour id).
// Counting every place a colour got — decor and elite together — keeps the
// colours level overall; the weight tips it toward colours still short of 40.
static void serve(NSArray<PKTroopGroup *> *groups, NSArray<PKPikmin *> *(^list)(PKTroopGroup *),
                  BOOL decorPhase, NSMutableArray<PKPikmin *> *chosen, NSMutableSet<NSString *> *chosenIds, NSUInteger slots) {
    while (chosen.count < slots) {
        PKTroopGroup *best = nil;
        for (PKTroopGroup *g in groups) {
            NSUInteger used = decorPhase ? g.takenDecor : g.takenElite;
            if (used >= list(g).count) continue;
            // places received, per unit of weight: a colour short of its quota at 4
            // hearts (need up to 1) is served up to twice as often as a full one
            if (!best || (double)g.taken / (1.0 + g.need) < (double)best.taken / (1.0 + best.need)) best = g;
        }
        if (!best) break;
        PKPikmin *p = list(best)[decorPhase ? best.takenDecor++ : best.takenElite++];
        best.taken++;
        [chosen addObject:p]; [chosenIds addObject:p.pid];
    }
}

NSArray<PKPikmin *> *pkTroopPlan(NSArray<PKPikmin *> *roster, NSArray<PKPikmin *> *movable,
                                 NSUInteger slots, NSString **summary) {
    NSMutableSet<NSString *> *canMove = [NSMutableSet set];
    for (PKPikmin *p in movable) [canMove addObject:p.pid];
    NSArray<PKTroopGroup *> *groups = makeGroups(roster, canMove);

    NSMutableArray<PKPikmin *> *chosen = [NSMutableArray array];
    NSMutableSet<NSString *> *chosenIds = [NSMutableSet set];
    serve(groups, ^NSArray<PKPikmin *> *(PKTroopGroup *g) { return g.decorLow; }, YES, chosen, chosenIds, slots);     // 1. decor under 4
    serve(groups, ^NSArray<PKPikmin *> *(PKTroopGroup *g) { return g.eliteCands; }, NO, chosen, chosenIds, slots);    // 2. elite toward 8

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
            if (g.taken) [bits addObject:[NSString stringWithFormat:@"%@ 데코%lu·정예%lu", @(colorName(g.color)), (unsigned long)g.takenDecor, (unsigned long)g.takenElite]];
        [bits addObject:[NSString stringWithFormat:@"기타 %lu", (unsigned long)(chosen.count - planned)]];
        *summary = [bits componentsJoinedByString:@", "];
    }
    return chosen;
}
