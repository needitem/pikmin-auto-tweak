#import "SingletonFinder.h"
#import "GameContext.h"
#import "Log.h"
#import "Runtime.h"
#import <QuartzCore/QuartzCore.h>
#import <unordered_set>
#import <vector>

typedef struct { PKSlotId slot; const char *ns, *cls; } Wanted;

static const Wanted kWanted[] = {
    { PKS_MGR,      "Niantic.Ichigo.Game.Pikmins",           "PikminManager" },
    { PKS_RPC,      "Niantic.Ichigo.Rpc",                    "RpcManager" },
    { PKS_ACTION,   "Niantic.Ichigo.Game",                   "PikminActionManager" },
    { PKS_EXPSTORE, "Niantic.Ichigo.Game.Expedition.Data",   "ExpeditionDataStore" },
    { PKS_TOOLS,    "Niantic.Ichigo.Game.Pikmins",           "PikminInventoryTools" },
    { PKS_PLANT,    "Niantic.Ichigo.Game.Flowers",           "FlowerPlantingController" },
    { PKS_MAPOBJ,   "Niantic.Ichigo.Game.MapObjects",        "MapObjectManager" },
    { PKS_EXTRACT,  "Niantic.Ichigo.Game.Garden.Extracts",   "ExtractSelectionTracker" },
};
static const size_t kMaxObjects = 6000;      // per call
static const int kMaxDepth = 3;              // captured object -> fields -> their fields -> theirs
// A miss costs a few thousand reflective field reads, so misses are retried
// gently: every second for the first ten tries (the usual case is caught in
// one), then every ten seconds, doubling per further miss up to two minutes.
// Some singletons only exist once the player opens a screen (the hooks catch
// those then); walking for them every ten seconds forever was pure overhead.
static const int kFastTries = 10;
static const NSTimeInterval kSlowGap = 10.0, kMaxGap = 120.0;

BOOL pkResolveSingletons(void) {
    if (!pkRuntimeReady()) return NO;
    static int misses = 0;
    static NSTimeInterval lastTry = -1e9;
    NSTimeInterval now = CACurrentMediaTime();
    if (misses >= kFastTries) {
        NSTimeInterval gap = kSlowGap;
        for (int i = kFastTries + 1; i < misses && gap < kMaxGap; i++) gap *= 2;
        if (now - lastTry < MIN(gap, kMaxGap)) return NO;
    }
    lastTry = now;
    struct Need { PKSlotId slot; void *cls; const char *name; };
    std::vector<Need> need;
    for (const Wanted &w : kWanted) {
        if (pkGet(w.slot)) continue;
        void *cls = pkClass(w.ns, w.cls);
        if (cls) need.push_back({ w.slot, cls, w.cls });
    }
    if (need.empty()) return NO;

    // Breadth-first from every singleton we already hold.
    std::vector<std::pair<void *, int>> queue;
    std::unordered_set<void *> seen;
    for (const Wanted &w : kWanted) {
        void *root = pkGet(w.slot);
        if (root && seen.insert(root).second) queue.push_back({ root, 0 });
    }
    if (queue.empty()) return NO;                    // nothing to walk from yet

    for (size_t i = 0; i < queue.size() && seen.size() < kMaxObjects && !need.empty(); i++) {
        void *obj = queue[i].first; int depth = queue[i].second;
        if (depth >= kMaxDepth) continue;
        std::vector<void *> kids;
        std::vector<void *> *out = &kids;
        pkEachRefField(obj, ^(void *child) { out->push_back(child); });
        for (void *child : kids) {
            if (!seen.insert(child).second) continue;
            void *cls = pkClassOf(child);
            for (size_t n = 0; n < need.size(); n++) {
                if (need[n].cls != cls) continue;
                pkCapture(need[n].slot, child, "field-scan");
                need.erase(need.begin() + (long)n);
                break;
            }
            queue.push_back({ child, depth + 1 });
        }
    }
    if (!need.empty()) misses++; else misses = 0;
    if (!need.empty()) {
        NSMutableArray *names = [NSMutableArray array];
        for (const Need &n : need) [names addObject:@(n.name)];
        PKLOGC(@"finder.miss", [NSString stringWithFormat:@"[capture] 필드 탐색으로 못 찾음: %@ (스캔 %zu개)",
                                [names componentsJoinedByString:@", "], seen.size()]);
    }
    return YES;
}
