#import "SeedValue.h"
#import "Layout.h"
#import "Log.h"
#import "Runtime.h"
#import <unordered_map>

// Large seedling types as the catalog reported them on this build, used only
// until the catalog object can be read: SEED_3/4, the SPECIAL_SEED_* colours,
// SEED_SILVER.
static BOOL fallbackLarge(int t) { return t == 3 || t == 4 || (t >= 23 && t <= 29) || t == 31 || t == 32; }

// seedType -> catalog size, read from PikminSeedCatalog.seedInfoList.
static std::unordered_map<int, int> gSizeOf;
static int gLargeValue = -1;
static int gCatalogTries = 0;

static void loadCatalog(void) {
    if (!gSizeOf.empty() || gCatalogTries >= 5) return;
    gCatalogTries++;
    NSString *ns = nil;
    void *catCls = pkFindClassByName("PikminSeedCatalog", &ns);
    void *cat = catCls ? pkFindObjectOfClass(catCls) : NULL;
    if (!cat) return;
    NSDictionary<NSNumber *, NSString *> *sizes = pkEnumMap(pkNestedClass(catCls, "Size"));
    for (NSNumber *k in sizes) if ([sizes[k] isEqualToString:@"Large"]) gLargeValue = k.intValue;
    ptrdiff_t offList = -1;
    pkRawFieldOffsetByName(catCls, "seedInfoList", &offList);
    void *list = offList >= 0 ? *(void **)((char *)cat + offList) : NULL;
    __block ptrdiff_t offType = -1, offSize = -1;
    __block int n = 0;
    pkListEach(list, ^(void *info) {
        if (offType < 0) {
            void *cls = pkClassOf(info);
            pkRawFieldOffsetByName(cls, "type", &offType);
            pkRawFieldOffsetByName(cls, "size", &offSize);
        }
        if (offType < 0 || offSize < 0) return;
        gSizeOf[*(int *)((char *)info + offType)] = *(int *)((char *)info + offSize);
        n++;
    });
    PALOG(@"[모종] 카탈로그 크기표 %d종 읽음 (Large=%d)", n, gLargeValue);
}

static BOOL isLarge(int seedType) {
    loadCatalog();
    if (!gSizeOf.empty() && gLargeValue >= 0) {
        auto it = gSizeOf.find(seedType);
        if (it != gSizeOf.end()) return it->second == gLargeValue;
    }
    return fallbackLarge(seedType);
}

PKSeedTraits pkSeedTraits(void *proto) {
    PKSeedTraits t = {0};
    if (!proto) { t.tier = PKSeedTierPlain; return t; }
    t.seedType = pkGetInt(proto, &F_Seed_type);
    t.color = pkGetInt(pkGetPtr(proto, &F_Seed_pikmin), &F_PT_type);
    t.req = pkGetInt(proto, &F_Seed_req);
    BOOL special = pkGetInt(proto, &F_Seed_treasure) != 0 || pkGetStr(proto, &F_Seed_event).length > 0;
    t.tier = special ? PKSeedTierSpecial : isLarge(t.seedType) ? PKSeedTierLarge : PKSeedTierPlain;
    return t;
}

NSComparisonResult pkSeedCompare(PKSeedTraits a, PKSeedTraits b, NSDictionary<NSNumber *, NSNumber *> *need) {
    if (a.tier != b.tier) return a.tier < b.tier ? NSOrderedAscending : NSOrderedDescending;
    double na = need[@(a.color)].doubleValue, nb = need[@(b.color)].doubleValue;
    if (na != nb) return na > nb ? NSOrderedAscending : NSOrderedDescending;          // the colour the roster wants more first
    if (a.req != b.req) return a.req < b.req ? NSOrderedAscending : NSOrderedDescending;   // then the soonest to ripen
    return NSOrderedSame;
}
