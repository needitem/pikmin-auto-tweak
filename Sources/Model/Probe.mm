#import "Probe.h"
#import "Inventory.h"
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
