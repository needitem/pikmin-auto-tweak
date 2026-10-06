#import "ExpeditionPool.h"
#import "GameConstants.h"

static NSComparisonResult byHeartsDesc(PKPikmin *a, PKPikmin *b) {
    if (a.hearts != b.hearts) return a.hearts > b.hearts ? NSOrderedAscending : NSOrderedDescending;
    return [a.pid compare:b.pid];
}
static NSComparisonResult byHeartsAsc(PKPikmin *a, PKPikmin *b) {
    if (a.hearts != b.hearts) return a.hearts < b.hearts ? NSOrderedAscending : NSOrderedDescending;
    return [a.pid compare:b.pid];
}

NSArray<PKPikmin *> *pkExpeditionPool(NSArray<PKPikmin *> *roster, NSSet<NSString *> *members,
                                      int troopTotal, int minTroop,
                                      NSSet<NSString *> *wanted, NSSet<NSString *> *elite, PKPoolStats *stats) {
    PKPoolStats st = {0};
    NSMutableArray<PKPikmin *> *plain = [NSMutableArray array], *spare = [NSMutableArray array], *heldForTroop = [NSMutableArray array];
    for (PKPikmin *p in roster) {
        if (p.status == PK_STATUS_TASK || p.status == 0) { st.busy++; continue; }
        if (p.starred) { st.starred++; continue; }
        if ([wanted containsObject:p.pid]) [heldForTroop addObject:p];
        else if ([elite containsObject:p.pid]) [spare addObject:p];
        else [plain addObject:p];
    }
    [plain sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) { return byHeartsDesc(a, b); }];
    [spare sortUsingComparator:^NSComparisonResult(PKPikmin *a, PKPikmin *b) { return byHeartsAsc(a, b); }];
    st.plain = plain.count; st.spare = spare.count; st.heldForTroop = heldForTroop.count;

    NSMutableArray<PKPikmin *> *pool = [NSMutableArray arrayWithArray:plain];
    [pool addObjectsFromArray:spare];
    if (!pool.count) { [pool addObjectsFromArray:heldForTroop]; st.onlyTroop = YES; }

    int poolInTroop = 0;
    for (PKPikmin *p in pool) if ([members containsObject:p.pid]) poolInTroop++;
    st.need = poolInTroop - troopTotal + minTroop;
    NSMutableArray<PKPikmin *> *out = [NSMutableArray array];
    for (PKPikmin *p in pool) {
        if (st.need > 0 && st.reserved < st.need && [members containsObject:p.pid]) { st.reserved++; continue; }
        [out addObject:p];
    }
    if (stats) *stats = st;
    return out;
}
