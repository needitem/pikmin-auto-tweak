#import "Passes.h"
#import "Clock.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Location.h"
#import "Log.h"
#import "MapObjects.h"
#import "Roster.h"
#import "SharedFile.h"

// Both dumps rewrite only when their content changed (position, which moves
// constantly, is not part of the comparison) or once a minute regardless. The
// first cut wrote ~580 objects every five seconds and drew an iOS diskwrites
// report; the walk needs a couple of kilobytes a minute.
static const NSTimeInterval kMinRewrite = 60.0;

// Exact content comparison (NSData.hash only looks at the first 80 bytes).
static BOOL unchanged(NSData *now, NSData *__strong *last, NSTimeInterval *lastWrite) {
    NSTimeInterval t = pkMono();
    if (*last && [*last isEqualToData:now] && t - *lastWrite < kMinRewrite) return YES;
    *last = now; *lastWrite = t;
    return NO;
}

// ---------- map objects, for GPS Wander's routing ----------
// Only the kinds it can use: big flowers and mushrooms.
void pkMapDumpPass(void) {
    NSArray<PKMapObject *> *objs = pkMapObjects();
    if (!objs) return;
    NSMutableArray *rows = [NSMutableArray array];
    for (PKMapObject *o in objs) {
        if (o.kind != PK_MO_POIFLOWER && o.kind != PK_MO_MUSHROOM) continue;
        [rows addObject:@{ @"id": o.oid, @"kind": @(o.kind), @"lat": @(o.lat), @"lng": @(o.lng),
                           @"state": @(o.state), @"color": @(o.color), @"bloom": @(o.bloomMs), @"visited": @(o.visited) }];
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingSortedKeys error:nil];
    static NSData *last; static NSTimeInterval lastWrite;
    if (!body || unchanged(body, &last, &lastWrite)) return;

    double lat = 0, lng = 0; pkLocationGet(&lat, &lng);
    NSDictionary *doc = @{ @"t": @([NSDate date].timeIntervalSince1970), @"lat": @(lat), @"lng": @(lng), @"objs": rows };
    NSData *json = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
    if (!json) return;
    static int sharedState = -1;
    BOOL ok = pkWriteShared(@"mapobjects.json", json);
    if ((int)ok != sharedState) {
        sharedState = ok;
        PALOG(@"[map] %lu개 기록, 공유 경로 %@", (unsigned long)rows.count, ok ? @"성공" : @"거부(Documents로 대체)");
    }
}

// ---------- roster (for planning mushroom battles) ----------
static NSString *colorName(int c) {
    switch (c) { case 1: return @"빨강"; case 2: return @"파랑"; case 3: return @"노랑"; case 4: return @"하양";
        case 5: return @"보라"; case 6: return @"바위"; case 7: return @"날개"; case 8: return @"얼음"; }
    return @"미상";
}
static NSString *flowerName(int s) {
    switch (s) { case PK_PF_LEAF: return @"잎"; case PK_PF_BUD: return @"봉우리"; case PK_PF_FLOWER: return @"꽃";
        case PK_PF_PICK: return @"수확대기"; case PK_PF_WILTED: return @"시듦"; }
    return @"?";
}
static NSString *statusName(int s) {
    switch (s) { case PK_STATUS_AVAILABLE: return @"대기"; case PK_STATUS_TASK: return @"작업중"; case PK_STATUS_ENTOURAGE: return @"동행"; }
    return @"?";
}

void pkRosterDumpPass(void) {
    NSArray<PKPikmin *> *all = pkRoster();
    if (!all) return;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray<NSNumber *> *steps = [NSMutableArray array];   // walking changes these constantly: kept out of the change check
    NSCountedSet *byColor = [NSCountedSet set], *byStatus = [NSCountedSet set];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *flowered = [NSMutableDictionary dictionary];
    int starred = 0, decor = 0;
    for (PKPikmin *p in all) {
        NSString *ck = colorName(p.color);
        [rows addObject:@{ @"name": p.name ?: @"", @"color": @(p.color), @"colorName": ck,
                           @"flower": @(p.flowerState), @"flowerName": flowerName(p.flowerState),
                           @"status": @(p.status), @"statusName": statusName(p.status),
                           @"hearts": @(p.hearts), @"fpt": @(p.heartPoints),
                           @"asset": @(p.asset), @"category": @(p.category), @"deco": @(p.isDecor),
                           @"starred": @(p.starred) }];
        [steps addObject:@(p.steps)];
        [byColor addObject:ck];
        [byStatus addObject:statusName(p.status)];
        if (p.starred) starred++;
        if (p.isDecor) decor++;
        NSMutableDictionary *fc = flowered[ck];
        if (!fc) { fc = [@{ @"꽃": @0, @"봉우리": @0, @"잎": @0, @"기타": @0 } mutableCopy]; flowered[ck] = fc; }
        NSString *fk = p.flowerState == PK_PF_FLOWER ? @"꽃" : p.flowerState == PK_PF_BUD ? @"봉우리" : p.flowerState == PK_PF_LEAF ? @"잎" : @"기타";
        fc[fk] = @([fc[fk] intValue] + 1);
    }
    NSData *sig = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingSortedKeys error:nil];
    static NSData *last; static NSTimeInterval lastWrite;
    if (!sig || unchanged(sig, &last, &lastWrite)) return;

    NSMutableArray *outRows = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSUInteger i = 0; i < rows.count; i++) {
        NSMutableDictionary *r = [rows[i] mutableCopy];
        r[@"steps"] = steps[i];
        [outRows addObject:r];
    }
    NSDictionary *doc = @{ @"t": @([NSDate date].timeIntervalSince1970), @"total": @(rows.count), @"starred": @(starred), @"pikmin": outRows };
    NSData *json = [NSJSONSerialization dataWithJSONObject:doc options:NSJSONWritingPrettyPrinted error:nil];
    if (json) pkWriteShared(@"roster.json", json);

    NSMutableString *txt = [NSMutableString string];
    [txt appendFormat:@"=== 보유 피크민 %lu마리 (즐겨찾기 %d) ===\n[색상별]\n", (unsigned long)rows.count, starred];
    for (NSString *c in @[@"빨강", @"파랑", @"노랑", @"하양", @"보라", @"바위", @"날개", @"얼음", @"미상"]) {
        NSUInteger n = [byColor countForObject:c];
        if (!n) continue;
        NSDictionary *fc = flowered[c];
        [txt appendFormat:@"  %@ %lu마리  (꽃 %@ / 봉우리 %@ / 잎 %@)\n", c, (unsigned long)n, fc[@"꽃"] ?: @0, fc[@"봉우리"] ?: @0, fc[@"잎"] ?: @0];
    }
    [txt appendString:@"[상태별]\n"];
    for (NSString *s in @[@"대기", @"작업중", @"동행"]) {
        NSUInteger n = [byStatus countForObject:s];
        if (n) [txt appendFormat:@"  %@ %lu마리\n", s, (unsigned long)n];
    }
    [txt appendFormat:@"[데코] 코스튬 착용 %d마리 (방출 제외 권장)\n", decor];
    pkWriteShared(@"roster.txt", [txt dataUsingEncoding:NSUTF8StringEncoding]);
    PALOG(@"[로스터] %lu마리 기록", (unsigned long)rows.count);
}
