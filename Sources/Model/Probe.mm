#import "Probe.h"
#import "GameContext.h"
#import "Inventory.h"
#import "Layout.h"
#import "Log.h"
#import "Runtime.h"
#import "Settings.h"

static NSString * const kSeedFlag = @"pa_probe_seed_v1";
static NSString * const kExpFlag = @"pa_probe_exp_v1";

// pa.log lines stay readable: long descriptions go out in slices.
static void emit(NSString *label, NSString *text) {
    const NSUInteger step = 1600;
    for (NSUInteger i = 0, part = 1; i < text.length; i += step, part++)
        PALOG(@"[발견] %@ #%lu: %@", label, (unsigned long)part, [text substringWithRange:NSMakeRange(i, MIN(step, text.length - i))]);
}

static void describe(NSString *label, void *cls) {
    if (!cls) { PALOG(@"[발견] %@: 클래스 없음", label); return; }
    emit(label, pkDescribeClass(cls));
}

static void describeNamed(const char *name) {
    NSString *ns = nil;
    void *cls = pkFindClassByName(name, &ns);
    if (!cls) { PALOG(@"[발견] %s: 못 찾음", name); return; }
    describe(@(name), cls);
}

void pkProbeSeedItem(void *item) {
    if (!item || [PKSettings stringForKey:kSeedFlag].length) return;
    [PKSettings setString:@"1" forKey:kSeedFlag];
    PALOG(@"[발견] 모종 조사 시작");
    // The item and what it wraps; its parents are named in the header.
    describe(@"모종 아이템", pkClassOf(item));
    void *proto = pkItemProto(item);
    if (proto) describe(@"모종 프로토", pkClassOf(proto));
    // Catalogs and the picture book (decor collection) — found by simple name.
    const char *names[] = { "PikminSeedCatalog", "PikminSeedCatalogExtensions", "PikminSeedInfo", "SeedInfo",
                            "PikminPictureBookTrackerExtensions", "PikminPictureBookTracker", "PikminCategoryCatalog", NULL };
    for (const char **n = names; *n; n++) describeNamed(*n);
    PALOG(@"[발견] 모종 조사 끝");
}

void pkProbeExpedition(void *d) {
    if (!d || [PKSettings stringForKey:kExpFlag].length) return;
    [PKSettings setString:@"1" forKey:kExpFlag];
    PALOG(@"[발견] 탐험 조사 시작");
    describe(@"탐험 항목", pkClassOf(d));
    void *reward = pkCall0(d, "get_PoiReward");
    if (reward) describe(@"탐험 보상(PoiReward)", pkClassOf(reward));
    else PALOG(@"[발견] get_PoiReward: 값 없음");
    void *poi = pkCall0(d, "get_PoiData");
    if (poi) describe(@"탐험 장소(PoiData)", pkClassOf(poi));
    PALOG(@"[발견] 탐험 조사 끝");
}

// ---------- stage 2: tables ----------
static NSString * const kSeedTableFlag = @"pa_probe_seedtable_v1";
static NSString * const kExpTableFlag = @"pa_probe_exptable_v1";

static NSString *nameOf(NSDictionary<NSNumber *, NSString *> *map, int v) {
    NSString *n = map[@(v)];
    return n ? [NSString stringWithFormat:@"%@(%d)", n, v] : [NSString stringWithFormat:@"%d", v];
}

static NSDictionary<NSNumber *, NSString *> *gSeedTypes, *gTreasures, *gCategories, *gSizes, *gTargets;

// Everything readable about one PikminSeedProto, as a grouping key.
static NSString *seedKey(void *proto) {
    void *pk = pkGetPtr(proto, &F_Seed_pikmin);
    return [NSString stringWithFormat:@"seed=%@ treasure=%@ color=%d cat=%@ asset=%d event=%@ req=%d",
            nameOf(gSeedTypes, pkGetInt(proto, &F_Seed_type)), nameOf(gTreasures, pkGetInt(proto, &F_Seed_treasure)),
            pkGetInt(pk, &F_PT_type), nameOf(gCategories, pkGetInt(pk, &F_PT_category)), pkGetInt(pk, &F_PT_asset),
            pkGetStr(proto, &F_Seed_event).length ? @"Y" : @"-", pkGetInt(proto, &F_Seed_req)];
}

static void logEnum(NSString *label, NSDictionary<NSNumber *, NSString *> *map) {
    NSMutableArray *bits = [NSMutableArray array];
    for (NSNumber *k in [map.allKeys sortedArrayUsingSelector:@selector(compare:)]) [bits addObject:[NSString stringWithFormat:@"%@=%@", map[k], k]];
    emit([@"열거 " stringByAppendingString:label], bits.count ? [bits componentsJoinedByString:@" "] : @"(읽지 못함)");
}

static void logGroups(NSString *label, NSCountedSet *set) {
    NSArray *keys = [set.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger ca = [set countForObject:a], cb = [set countForObject:b];
        return ca != cb ? (ca > cb ? NSOrderedAscending : NSOrderedDescending) : [a compare:b];
    }];
    NSMutableString *body = [NSMutableString stringWithFormat:@"%lu종류 / %lu건\n", (unsigned long)keys.count, (unsigned long)set.count];
    NSUInteger n = 0;
    for (NSString *k in keys) { if (n++ >= 70) break; [body appendFormat:@"%3lux %@\n", (unsigned long)[set countForObject:k], k]; }
    emit(label, body);
}

// Does a catalog ScriptableObject know which seed types are large? Its SeedInfo
// list pairs each type with a Size.
static void logCatalogSizes(void) {
    NSString *ns = nil;
    void *catCls = pkFindClassByName("PikminSeedCatalog", &ns);
    void *cat = catCls ? pkFindObjectOfClass(catCls) : NULL;
    if (!cat) { PALOG(@"[발견] 모종 카탈로그 인스턴스: 못 찾음"); return; }
    ptrdiff_t offList = -1;
    __block ptrdiff_t offType = -1, offSize = -1;
    pkRawFieldOffsetByName(catCls, "seedInfoList", &offList);
    void *list = offList >= 0 ? *(void **)((char *)cat + offList) : NULL;
    NSMutableArray *rows = [NSMutableArray array];
    __block void *infoCls = NULL;
    pkListEach(list, ^(void *info) {
        if (!infoCls) {
            infoCls = pkClassOf(info);
            pkRawFieldOffsetByName(infoCls, "type", &offType);
            pkRawFieldOffsetByName(infoCls, "size", &offSize);
        }
        if (offType < 0 || offSize < 0) return;
        [rows addObject:[NSString stringWithFormat:@"%@→%@", nameOf(gSeedTypes, *(int *)((char *)info + offType)),
                         nameOf(gSizes, *(int *)((char *)info + offSize))]];
    });
    emit(@"카탈로그 크기표", rows.count ? [rows componentsJoinedByString:@"  "] : @"(비어 있음)");
}

// Where is the picture book? Breadth-first over what the game singletons
// reference, listing every class whose name mentions it.
static void logPictureBook(void) {
    void *roots[] = { pkMgr(), pkInv(), pkTools(), pkAction(), pkPlant(), pkExpStore() };
    NSMutableArray<NSValue *> *queue = [NSMutableArray array];
    NSMutableSet<NSValue *> *seen = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *found = [NSMutableDictionary dictionary];
    NSMutableArray<NSNumber *> *depth = [NSMutableArray array];
    for (void *r : roots) if (r) { NSValue *v = [NSValue valueWithPointer:r]; if (![seen containsObject:v]) { [seen addObject:v]; [queue addObject:v]; [depth addObject:@0]; } }
    for (NSUInteger i = 0; i < queue.count && seen.count < 9000; i++) {
        void *obj = queue[i].pointerValue; int d = depth[i].intValue;
        NSString *cn = pkClassName(obj);
        if (cn && [cn rangeOfString:@"PictureBook" options:NSCaseInsensitiveSearch].location != NSNotFound) found[cn] = @(found[cn].intValue + 1);
        if (d >= 4) continue;
        NSMutableArray<NSValue *> *kids = [NSMutableArray array];
        pkEachRefField(obj, ^(void *child) { [kids addObject:[NSValue valueWithPointer:child]]; });
        for (NSValue *c in kids) if (![seen containsObject:c]) { [seen addObject:c]; [queue addObject:c]; [depth addObject:@(d + 1)]; }
    }
    NSMutableArray *bits = [NSMutableArray array];
    for (NSString *k in found.allKeys) [bits addObject:[NSString stringWithFormat:@"%@ x%@", k, found[k]]];
    PALOG(@"[발견] 도감(PictureBook) 객체 탐색(%lu개 훑음): %@", (unsigned long)seen.count, bits.count ? [bits componentsJoinedByString:@", "] : @"없음");
}

void pkProbeSeedTable(NSArray<NSValue *> *protos) {
    if (!protos.count || [PKSettings stringForKey:kSeedTableFlag].length) return;
    [PKSettings setString:@"1" forKey:kSeedTableFlag];
    PALOG(@"[발견] 모종 표 조사 시작");
    void *seedProtoCls = pkClass("Ichigo.Proto", "PikminSeedProto");
    gSeedTypes = pkEnumMap(pkNestedClass(seedProtoCls, "SeedType"));
    gTreasures = pkEnumMap(pkClass("Ichigo.Proto", "TreasureType"));
    gCategories = pkEnumMap(pkNestedClass(pkClass("Ichigo.Proto", "PikminCategoryProto"), "Id"));
    NSString *ns = nil;
    void *catCls = pkFindClassByName("PikminSeedCatalog", &ns);
    gSizes = pkEnumMap(pkNestedClass(catCls, "Size"));
    logEnum(@"SeedType", gSeedTypes); logEnum(@"TreasureType", gTreasures);
    logEnum(@"카테고리", gCategories); logEnum(@"Size", gSizes);
    NSCountedSet *groups = [NSCountedSet set];
    for (NSValue *v in protos) [groups addObject:seedKey(v.pointerValue)];
    logGroups(@"내 모종 분포", groups);
    logCatalogSizes();
    logPictureBook();
    PALOG(@"[발견] 모종 표 조사 끝");
}

void pkProbeExpeditionTable(NSArray<NSValue *> *items) {
    if (!items.count || [PKSettings stringForKey:kExpTableFlag].length) return;
    [PKSettings setString:@"1" forKey:kExpTableFlag];
    PALOG(@"[발견] 탐험 표 조사 시작");
    NSString *ns = nil;
    void *tc = pkFindClassByName("TargetCase", &ns);
    gTargets = pkEnumMap(tc);
    emit(@"열거 TargetCase", [NSString stringWithFormat:@"%@ %@", ns ?: @"?", [[gTargets.allValues sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]]);
    if (!gSeedTypes) {                                      // the seed pass may not have run yet
        gSeedTypes = pkEnumMap(pkNestedClass(pkClass("Ichigo.Proto", "PikminSeedProto"), "SeedType"));
        gTreasures = pkEnumMap(pkClass("Ichigo.Proto", "TreasureType"));
        gCategories = pkEnumMap(pkNestedClass(pkClass("Ichigo.Proto", "PikminCategoryProto"), "Id"));
    }
    NSCountedSet *groups = [NSCountedSet set];
    for (NSValue *v in items) {
        void *d = v.pointerValue;
        int target = pkUnboxInt(pkCall0(d, "get_Target"));
        void *seed = pkCall0(d, "get_PikminSeed");
        [groups addObject:[NSString stringWithFormat:@"target=%@ %@", nameOf(gTargets, target), seed ? seedKey(seed) : @"(모종 없음)"]];
    }
    logGroups(@"탐험 대상 분포", groups);
    PALOG(@"[발견] 탐험 표 조사 끝");
}
