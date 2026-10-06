#import "Hooks.h"
#import "GameContext.h"
#import "Log.h"
#import "Nectar.h"
#import "Runtime.h"

static BOOL gCamSuppress = NO;
void pkSetCameraSuppress(BOOL suppress) { __atomic_store_n(&gCamSuppress, suppress, __ATOMIC_RELAXED); }

// ---------- capture hooks ----------
// RPC wrappers share one native shape: (self, request, CancellationToken(8B), RpcRetryPolicy(int), MethodInfo*).
// Every hook counts its calls (hits_<name>); the heartbeat prints the rate, so a
// hook sitting on a hot game path shows up as a number instead of a suspicion.
#define HIT(NAME) __atomic_fetch_add(&hits_##NAME, 1, __ATOMIC_RELAXED)
#define HOOK_RPC_CAPTURE(NAME, SLOT, VIA)                                                       \
    static unsigned long hits_##NAME;                                                           \
    static void *(*orig_##NAME)(void *, void *, void *, int, void *);                           \
    static void *hook_##NAME(void *self, void *req, void *ct, int retry, void *mi) {            \
        HIT(NAME);                                                                              \
        pkCapture(SLOT, self, VIA);                                                             \
        return orig_##NAME(self, req, ct, retry, mi);                                           \
    }
#define HOOK_V1_CAPTURE(NAME, SLOT, VIA)                                                        \
    static unsigned long hits_##NAME;                                                           \
    static void (*orig_##NAME)(void *, void *, void *);                                         \
    static void hook_##NAME(void *self, void *a, void *mi) {                                    \
        HIT(NAME);                                                                              \
        pkCapture(SLOT, self, VIA);                                                             \
        orig_##NAME(self, a, mi);                                                               \
    }
#define HOOK_V0_CAPTURE(NAME, SLOT, VIA)                                                        \
    static unsigned long hits_##NAME;                                                           \
    static void (*orig_##NAME)(void *, void *);                                                 \
    static void hook_##NAME(void *self, void *mi) {                                             \
        HIT(NAME);                                                                              \
        pkCapture(SLOT, self, VIA);                                                             \
        orig_##NAME(self, mi);                                                                  \
    }

HOOK_RPC_CAPTURE(getplayer, PKS_RPC, "GetPlayer")
HOOK_RPC_CAPTURE(activity,  PKS_RPC, "BatchReportActivity")   // periodic RPCs the game fires itself,
HOOK_RPC_CAPTURE(flag,      PKS_RPC, "UpdateGamePlayFlag")    // so a late start still catches `this`
HOOK_V1_CAPTURE(addupd,     PKS_MGR, "AddOrUpdatePikmin")
HOOK_V1_CAPTURE(expadd,     PKS_EXPSTORE, "AddData")          // AddData fires once per task,
HOOK_V1_CAPTURE(expupd,     PKS_EXPSTORE, "NotifyUpdate")     // NotifyUpdate keeps firing
HOOK_V1_CAPTURE(setextract, PKS_EXTRACT, "SetExtract")
HOOK_V0_CAPTURE(pamctor,    PKS_ACTION, "ctor")
HOOK_V0_CAPTURE(plantinit,  PKS_PLANT, "Init")
HOOK_V0_CAPTURE(mapupd,     PKS_MAPOBJ, "Update")

static unsigned long hits_getpikmin;
static void *(*orig_getpikmin)(void *, void *, void *);
static void *hook_getpikmin(void *self, void *idStr, void *mi) {
    HIT(getpikmin);
    pkCapture(PKS_MGR, self, "GetPikmin");
    return orig_getpikmin(self, idStr, mi);
}
static unsigned long hits_estctor;
static void (*orig_estctor)(void *, void *, void *, void *);
static void hook_estctor(void *self, void *a, void *b, void *mi) {
    HIT(estctor);
    pkCapture(PKS_EXTRACT, self, "ctor");
    orig_estctor(self, a, b, mi);
}
static unsigned long hits_pitctor;
static void (*orig_pitctor)(void *, void *, void *, void *, void *);
static void hook_pitctor(void *self, void *a, void *b, void *c, void *mi) {
    HIT(pitctor);
    pkCapture(PKS_TOOLS, self, "ctor");
    orig_pitctor(self, a, b, c, mi);
}
static unsigned long hits_pitin;
static bool (*orig_pitin)(void *, void *, void *);
static bool hook_pitin(void *self, void *pid, void *mi) {
    HIT(pitin);
    pkCapture(PKS_TOOLS, self, "IsPikminInInventory");
    return orig_pitin(self, pid, mi);
}
static unsigned long hits_schedpick;
static bool (*orig_schedpick)(void *, void *, void *);
static bool hook_schedpick(void *self, void *pikId, void *mi) {
    HIT(schedpick);
    pkCapture(PKS_ACTION, self, "SchedulePickPikminFlower");
    return orig_schedpick(self, pikId, mi);
}
// A manual feed reveals which nectar stack the player means; the feed pass
// picks it up on its own tick (nothing is looked up from inside this callback).
static unsigned long hits_schedfeed;
static void *(*orig_schedfeed)(void *, void *, void *, void *);
static void *hook_schedfeed(void *self, void *pikId, void *itemId, void *mi) {
    HIT(schedfeed);
    pkCapture(PKS_ACTION, self, "ScheduleFeedPikmin");
    pkNoteHandFedRaw(itemId);
    return orig_schedfeed(self, pikId, itemId, mi);
}
// SetTarget is the camera move onto a Pikmin. SetFocus is deliberately left
// alone: swallowing it broke the expedition-reward flow, which reads the
// focused Pikmin afterwards.
static unsigned long hits_settarget;
static void (*orig_settarget)(void *, void *, void *);
static void hook_settarget(void *self, void *pikmin, void *mi) {
    HIT(settarget);
    if (__atomic_load_n(&gCamSuppress, __ATOMIC_RELAXED)) return;
    orig_settarget(self, pikmin, mi);
}

// ---------- install table ----------
typedef struct {
    const char *ns, *cls, *method;
    int argc;
    void *hook;
    void **orig;
    int attempts;
    BOOL done;
    unsigned long *hits;
    const char *name;
    unsigned long last;
} PKHookSpec;

#define NS_RPC    "Niantic.Ichigo.Rpc"
#define NS_PIKMIN "Niantic.Ichigo.Game.Pikmins"
#define NS_EXTRACT "Niantic.Ichigo.Game.Garden.Extracts"
#define H(ns, cls, method, argc, name) \
    { ns, cls, method, argc, (void *)hook_##name, (void **)&orig_##name, 0, NO, &hits_##name, #name, 0 }

static PKHookSpec gSpecs[] = {
    H(NS_RPC, "RpcManager", "SendGetPlayerRpcForResultAsync",          3, getplayer),
    H(NS_RPC, "RpcManager", "SendBatchReportActivityRpcForResultAsync", 3, activity),
    H(NS_RPC, "RpcManager", "SendUpdateGamePlayFlagRpcForResultAsync",  3, flag),
    H(NS_PIKMIN, "PikminManager", "AddOrUpdatePikmin", 1, addupd),
    H(NS_PIKMIN, "PikminManager", "GetPikmin",         1, getpikmin),
    H("Niantic.Ichigo.Game.Garden.Cameras", "PikminCameraController", "SetTarget", 1, settarget),
    H(NS_EXTRACT, "ExtractSelectionTracker", "SetExtract", 1, setextract),
    H(NS_EXTRACT, "ExtractSelectionTracker", ".ctor",      2, estctor),
    H("Niantic.Ichigo.Game", "PikminActionManager", "ScheduleFeedPikminAsync",                 2, schedfeed),
    H("Niantic.Ichigo.Game", "PikminActionManager", ".ctor",                                   0, pamctor),
    H("Niantic.Ichigo.Game", "PikminActionManager", "SchedulePickPikminFlowerBatchedRequest",  1, schedpick),
    H(NS_PIKMIN, "PikminInventoryTools", ".ctor",               3, pitctor),
    H(NS_PIKMIN, "PikminInventoryTools", "IsPikminInInventory", 1, pitin),
    H("Niantic.Ichigo.Game.Expedition.Data", "ExpeditionDataStore", "AddData",      1, expadd),
    H("Niantic.Ichigo.Game.Expedition.Data", "ExpeditionDataStore", "NotifyUpdate", 1, expupd),
    H("Niantic.Ichigo.Game.Flowers",    "FlowerPlantingController", "Init",   0, plantinit),
    H("Niantic.Ichigo.Game.MapObjects", "MapObjectManager",         "Update", 0, mapupd),
};

// Each hook is retried on its own (a class that has not loaded yet no longer
// blocks the rest), for up to about five minutes at one attempt per second.
static const int kMaxAttempts = 300;

void pkInstallHooks(void) {
    static BOOL finished = NO;
    if (finished || !pkRuntimeReady()) return;
    int pending = 0;
    for (PKHookSpec &s : gSpecs) {
        if (s.done || s.attempts >= kMaxAttempts) continue;
        s.attempts++;
        void *cls = pkClass(s.ns, s.cls);
        if (cls && pkHookMethod(cls, s.method, s.argc, s.hook, s.orig)) {
            s.done = YES;
            PALOG(@"[hooks] %s.%s 설치", s.cls, s.method);
        } else if (s.attempts < kMaxAttempts) {
            pending++;
        }
    }
    if (pending) return;
    finished = YES;
    NSMutableArray *missing = [NSMutableArray array];
    for (const PKHookSpec &s : gSpecs)
        if (!s.done) [missing addObject:[NSString stringWithFormat:@"%s.%s", s.cls, s.method]];
    if (missing.count) PALOG(@"[hooks] 설치 실패 %lu개: %@", (unsigned long)missing.count, [missing componentsJoinedByString:@", "]);
    else PALOG(@"[hooks] 전부 설치됨");
}

NSString *pkHookStats(void) {
    NSMutableArray<NSArray *> *rows = [NSMutableArray array];
    for (PKHookSpec &s : gSpecs) {
        if (!s.done) continue;
        unsigned long now = __atomic_load_n(s.hits, __ATOMIC_RELAXED);
        if (now > s.last) [rows addObject:@[ @(s.name), @(now - s.last) ]];
        s.last = now;
    }
    if (!rows.count) return @"-";
    [rows sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[1] compare:a[1]]; }];
    NSMutableArray *bits = [NSMutableArray array];
    for (NSArray *r in rows) [bits addObject:[NSString stringWithFormat:@"%@ %@", r[0], r[1]]];
    return [bits componentsJoinedByString:@", "];
}
