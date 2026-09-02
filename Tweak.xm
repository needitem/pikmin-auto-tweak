// Pikmin Auto — own-device Pikmin Bloom (com.nianticlabs.pikmin) automation.
//
//  • Silent background numbering: every Pikmin is renamed to its pluck-order
//    number (1..N). Idempotent — only Pikmin whose name is already wrong get a
//    rename, so it converges and new Pikmin simply pick up the next number.
//  • 🌸 자동 수확  — PickPikminFlowers over every owned Pikmin, on a timer.
//  • 📦 자동 수집  — completes every ready Pikmin task (expeditions: fruit,
//    seedlings, gifts) via CompletePikminTask.
//  • 🍯 자동 정수  — Stage-1 safe check: reads the nectar (HoneyBall) inventory
//    and reports the count. Feeding is enabled once the read path is verified
//    on-device (multi-offset read, done cautiously).
//  • 🧭 자동 탐험  — starts the expeditions waiting in ExpeditionDataStore, with
//    the party the game's own rules accept (see pkExpeditionCandidates).
//
// All actions go through the game's own server RPCs (RpcManager). Unity IL2CPP,
// metadata v31 un-obfuscated, so classes/methods resolve by name at runtime.
//
// Layout facts (Il2CppDumper dump of this build):
//   PikminManager (Niantic.Ichigo.Game.Pikmins): pikmins Dictionary<string,Pikmin> @0x60,
//       inventoryManager @0x30, void AddOrUpdatePikmin(PikminInventoryItem), Pikmin GetPikmin(string)
//   Pikmin: id (string) @0xA8, pikminProto @0xC0
//   PikminProto (Ichigo.Proto): name_ (string) @0x30, pluckTime_ @0xA0
//   ZonedTimestampProto: utcTimeMs_ (long) @0x18
//   RpcManager (Niantic.Ichigo.Rpc): Send{RenamePikmin,PickPikminFlowers,CompletePikminTask,GetPlayer}RpcForResultAsync
//   Request protos (Ichigo.Proto): RenamePikminRequestProto{set_PikminId,set_Name},
//       PickPikminFlowersRequestProto{get_PikminId:RepeatedField<string>},
//       CompletePikminTaskRequestProto{pikminTaskId_ @0x18}
//   InventoryManager: List<PikminTaskInventoryItem> GetPikminTaskList(); storages hold
//       base ItemStorage.Items = List<Predicted<InventoryItem>> @0x10; honeyBall storage @0x48
//   HoneyBallProto: numBalls_ @0x18, honeyType_ @0x1C
//   ExpeditionDataStore (…Game.Expedition.Data): cache Dictionary<string,…> @0x18;
//       values are ExpeditionItemData{item(PikminTaskInventoryItem) @0x78, stats @0x80}
//       with the game's own Allows()/CanTryStart/StartDisabledReason/StartExpeditionAsync
//   PikminUtils (…Game.Pikmins): IsPikminInTroop(PikminProto, InventoryManager) — note the
//       [Extension] overload takes the arguments the other way round, and
//       class_get_method_from_name cannot tell them apart; GetPikminInTroopCount(InventoryManager)
//   PikminInventoryTools (…Game.Pikmins): clientSettingsCache @0x18 → CurrentSettings →
//       ClientSettingsProto.pikmin_ @0x78 → PikminSettingsProto.minTroopPikminCount_ @0x1C

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <dlfcn.h>
#import <pthread.h>

// ---------- il2cpp runtime API ----------
typedef void*        (*t_domain_get)(void);
typedef void*        (*t_thread_attach)(void*);
typedef void**       (*t_domain_get_assemblies)(void*, size_t*);
typedef const void*  (*t_assembly_get_image)(const void*);
typedef const char*  (*t_image_get_name)(const void*);
typedef void*        (*t_class_from_name)(const void*, const char*, const char*);
typedef void*        (*t_class_get_method_from_name)(void*, const char*, int);
typedef void*        (*t_class_get_field_from_name)(void*, const char*);
typedef size_t       (*t_field_get_offset)(void*);
typedef void*        (*t_object_new)(void*);
typedef void*        (*t_object_get_class)(void*);
typedef void*        (*t_runtime_invoke)(const void*, void*, void**, void**);
typedef void*        (*t_string_new)(const char*);
typedef void         (*t_MSHookFunction)(void*, void*, void**);
typedef uint32_t     (*t_gchandle_new)(void*, int);
typedef void*        (*t_gchandle_get_target)(uint32_t);
typedef void         (*t_gchandle_free)(uint32_t);
typedef void*        (*t_class_get_nested_types)(void*, void**);
typedef const char*  (*t_class_get_name)(void*);

static t_domain_get                 f_domain_get;
static t_thread_attach              f_thread_attach;
static t_domain_get_assemblies      f_domain_get_assemblies;
static t_assembly_get_image         f_assembly_get_image;
static t_image_get_name             f_image_get_name;
static t_class_from_name            f_class_from_name;
static t_class_get_method_from_name f_class_get_method_from_name;
static t_class_get_field_from_name  f_class_get_field_from_name;
static t_field_get_offset           f_field_get_offset;
static t_object_new                 f_object_new;
static t_object_get_class           f_object_get_class;
static t_runtime_invoke             f_runtime_invoke;
static t_string_new                 f_string_new;
static t_MSHookFunction             f_MSHookFunction;
static t_gchandle_new               f_gchandle_new;
static t_gchandle_get_target        f_gchandle_get_target;
static t_gchandle_free              f_gchandle_free;
static t_class_get_nested_types     f_class_get_nested_types;
static t_class_get_name             f_class_get_name;

static void *gUnity = NULL;
#define SYM(v, name) v = (typeof(v))dlsym(gUnity ? gUnity : RTLD_DEFAULT, name)

static void tryGrabUnityHandle(void) {
    if (gUnity) return;
    NSString *fw = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
    gUnity = dlopen(fw.fileSystemRepresentation, RTLD_NOLOAD);
}

static BOOL resolveAPI(void) {
    static BOOL done = NO;
    if (done) return YES;
    tryGrabUnityHandle();
    SYM(f_domain_get, "il2cpp_domain_get");
    SYM(f_thread_attach, "il2cpp_thread_attach");
    SYM(f_domain_get_assemblies, "il2cpp_domain_get_assemblies");
    SYM(f_assembly_get_image, "il2cpp_assembly_get_image");
    SYM(f_image_get_name, "il2cpp_image_get_name");
    SYM(f_class_from_name, "il2cpp_class_from_name");
    SYM(f_class_get_method_from_name, "il2cpp_class_get_method_from_name");
    SYM(f_class_get_field_from_name, "il2cpp_class_get_field_from_name");
    SYM(f_field_get_offset, "il2cpp_field_get_offset");
    SYM(f_object_new, "il2cpp_object_new");
    SYM(f_object_get_class, "il2cpp_object_get_class");
    SYM(f_runtime_invoke, "il2cpp_runtime_invoke");
    SYM(f_string_new, "il2cpp_string_new");
    f_MSHookFunction = (t_MSHookFunction)dlsym(RTLD_DEFAULT, "MSHookFunction");
    SYM(f_gchandle_new, "il2cpp_gchandle_new");
    SYM(f_gchandle_get_target, "il2cpp_gchandle_get_target");
    SYM(f_gchandle_free, "il2cpp_gchandle_free");
    SYM(f_class_get_nested_types, "il2cpp_class_get_nested_types");
    SYM(f_class_get_name, "il2cpp_class_get_name");
    done = f_domain_get && f_domain_get_assemblies && f_assembly_get_image &&
           f_image_get_name && f_class_from_name && f_class_get_method_from_name &&
           f_class_get_field_from_name && f_field_get_offset && f_object_new &&
           f_object_get_class && f_runtime_invoke && f_string_new && f_MSHookFunction;
    return done;
}

static void *pkFindClass(const char *ns, const char *name) {
    if (!f_domain_get) return NULL;
    void *dom = f_domain_get(); if (!dom) return NULL;
    if (f_thread_attach) f_thread_attach(dom);
    size_t n = 0; void **as = f_domain_get_assemblies(dom, &n);
    for (size_t i = 0; i < n; i++) {
        const void *im = f_assembly_get_image(as[i]);
        if (!im) continue;
        void *k = f_class_from_name(im, ns, name);
        if (k) return k;
    }
    return NULL;
}

// Append a line to the app's own Documents/pa.log (sandbox-writable), read back
// as root over SSH. Toasts are hidden behind the game UI, so the log is the
// only reliable channel.
static void PALOG(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void PALOG(NSString *fmt, ...) {
    static NSString *path = nil;
    if (!path) path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                        stringByAppendingPathComponent:@"pa.log"];
    va_list ap; va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%.3f %@\n",
                      [NSDate date].timeIntervalSince1970, body];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
    @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; }
    @finally { [fh closeFile]; }
}

// Read an Il2CppString into an NSString (len @0x10, UTF-16 chars @0x14).
static NSString *pkStr(void *s) {
    if (!s) return nil;
    int len = *(int*)((char*)s + 0x10);
    if (len < 0 || len > 4096) return nil;
    return [NSString stringWithCharacters:(const unichar*)((char*)s + 0x14) length:(NSUInteger)len];
}

// ---------- captured live instances ----------
static void *gRpc = NULL;      // RpcManager
static void *gMgr = NULL;      // PikminManager
static void *gInv(void) { return gMgr ? *(void**)((char*)gMgr + 0x30) : NULL; }   // InventoryManager

static void *(*orig_getplayer)(void*, void*, void*, int, void*);
static void *hook_getplayer(void *self, void *req, void *ct, int retry, void *mi) {
    if (self && !gRpc) { gRpc = self; PALOG(@"[capture] RpcManager=%p (GetPlayer)", self); }
    return orig_getplayer(self, req, ct, retry, mi);
}
static void (*orig_addupd)(void*, void*, void*);
static void hook_addupd(void *self, void *item, void *mi) {
    if (self && !gMgr) { gMgr = self; PALOG(@"[capture] PikminManager=%p (AddOrUpdatePikmin)", self); }
    orig_addupd(self, item, mi);
}
static void *(*orig_getpikmin)(void*, void*, void*);
static void *hook_getpikmin(void *self, void *idStr, void *mi) {
    if (self && !gMgr) { gMgr = self; PALOG(@"[capture] PikminManager=%p (GetPikmin)", self); }
    return orig_getpikmin(self, idStr, mi);
}
// Extra RpcManager capture points — periodic RPCs the game fires on its own, so
// we catch the wrapper `this` even though the one-time login GetPlayer already
// went out before our hooks were in place. Same native shape as GetPlayer:
// (self, request, CancellationToken(8B), RpcRetryPolicy(int), MethodInfo*).
static void *(*orig_activity)(void*, void*, void*, int, void*);
static void *hook_activity(void *self, void *req, void *ct, int retry, void *mi) {
    if (self && !gRpc) { gRpc = self; PALOG(@"[capture] RpcManager=%p (BatchReportActivity)", self); }
    return orig_activity(self, req, ct, retry, mi);
}
static void *(*orig_flag)(void*, void*, void*, int, void*);
static void *hook_flag(void *self, void *req, void *ct, int retry, void *mi) {
    if (self && !gRpc) { gRpc = self; PALOG(@"[capture] RpcManager=%p (UpdateGamePlayFlag)", self); }
    return orig_flag(self, req, ct, retry, mi);
}
// Camera-focus handling. No-oping PikminFocusController.SetFocus crashed the
// expedition-reward flow (it reads the focused Pikmin, which then stayed null),
// so we DO NOT suppress focus by swallowing SetFocus. We only capture the live
// PikminFocusController here (calling through untouched); the safe way to stop
// the camera moving is the game's own Pause(), applied on the instance.
static BOOL gFocusSuppress = NO;
static void *gFocus = NULL;                      // live PikminFocusController
static void (*orig_setfocus)(void*, void*, int, void*);
static void hook_setfocus(void *self, void *pikmin, int focusType, void *mi) {
    if (self) gFocus = self;
    orig_setfocus(self, pikmin, focusType, mi);
}
// PikminCameraController.SetTarget(Pikmin) is the actual camera move onto a Pikmin.
// No-op it while automation runs so feeds/harvests don't yank the camera — but we
// leave PikminFocusController.SetFocus alone (its state stays valid), so the
// expedition-reward flow that reads the focused Pikmin does NOT crash.
static void (*orig_settarget)(void*, void*, void*);
static void hook_settarget(void *self, void *pikmin, void *mi) {
    if (gFocusSuppress) return;
    orig_settarget(self, pikmin, mi);
}

// Observe every FeedPikmins RPC — ours AND the ones the game sends when the user
// manually feeds — logging the exact request, so we can compare payloads.
// FeedPikminsRequestProto: pikminId_ RepeatedField @0x18, itemId_ @0x20, numItems_ @0x28.
static void pkLogFeedReq(const char *tag, void *req) {
    if (!req) return;
    void *rf = *(void**)((char*)req + 0x18);
    int pcnt = -1;
    if (rf) {
        void *rfCls = f_object_get_class(rf);
        void *fc = f_class_get_field_from_name(rfCls, "count");
        if (!fc) fc = f_class_get_field_from_name(rfCls, "_count");
        if (fc) pcnt = *(int*)((char*)rf + f_field_get_offset(fc));
    }
    void *itemId = *(void**)((char*)req + 0x20);
    int numItems = *(int*)((char*)req + 0x28);
    PALOG(@"[feedRPC:%s] pikminCount=%d itemId='%@' numItems=%d", tag, pcnt, pkStr(itemId) ?: @"", numItems);
}
static void *(*orig_feedsend)(void*, void*, void*, int, void*);
static void *hook_feedsend(void *self, void *req, void *ct, int retry, void *mi) {
    pkLogFeedReq("R", req);
    return orig_feedsend(self, req, ct, retry, mi);
}
static void *(*orig_feedsend2)(void*, void*, void*, int, void*);
static void *hook_feedsend2(void *self, void *req, void *ct, int retry, void *mi) {
    pkLogFeedReq("P", req);
    return orig_feedsend2(self, req, ct, retry, mi);
}
// Same, for PickPikminFlowers — capture the game's own manual harvest request.
static void pkLogPickReq(const char *tag, void *req) {
    if (!req) return;
    void *rf = *(void**)((char*)req + 0x18);
    int pcnt = -1;
    if (rf) {
        void *rfCls = f_object_get_class(rf);
        void *fc = f_class_get_field_from_name(rfCls, "count");
        if (!fc) fc = f_class_get_field_from_name(rfCls, "_count");
        if (fc) pcnt = *(int*)((char*)rf + f_field_get_offset(fc));
    }
    PALOG(@"[pickRPC:%s] pikminCount=%d", tag, pcnt);
}
static void *(*orig_picksend)(void*, void*, void*, int, void*);
static void *hook_picksend(void *self, void *req, void *ct, int retry, void *mi) {
    pkLogPickReq("R", req);
    return orig_picksend(self, req, ct, retry, mi);
}
static void *(*orig_picksend2)(void*, void*, void*, int, void*);
static void *hook_picksend2(void *self, void *req, void *ct, int retry, void *mi) {
    pkLogPickReq("P", req);
    return orig_picksend2(self, req, ct, retry, mi);
}

// Observe every SetPikminSeed RPC — the game's manual planting and ours — so
// the two requests can be compared field by field.
// SetPikminSeedRequestProto: seedId_ @0x18, point_ @0x20, slotOption_ @0x28 {slotIndex_ @0x18}.
static void pkLogSeedReq(const char *tag, void *req) {
    if (!req) return;
    void *seed = *(void**)((char*)req + 0x18);
    void *pt   = *(void**)((char*)req + 0x20);
    void *so   = *(void**)((char*)req + 0x28);
    PALOG(@"[seedRPC:%s] seed='%@' point=%@ slot=%@", tag, pkStr(seed) ?: @"",
          pt ? [NSString stringWithFormat:@"(%.6f,%.6f)", *(double*)((char*)pt + 0x18), *(double*)((char*)pt + 0x20)] : @"null",
          so ? [NSString stringWithFormat:@"%d", *(int*)((char*)so + 0x18)] : @"null");
}
static void *(*orig_seedsend)(void*, void*, void*, int, void*);
static void *hook_seedsend(void *self, void *req, void *ct, int retry, void *mi) {
    pkLogSeedReq("R", req);
    return orig_seedsend(self, req, ct, retry, mi);
}
static void *(*orig_seedsend2)(void*, void*, void*, int, void*);
static void *hook_seedsend2(void *self, void *req, void *ct, int retry, void *mi) {
    pkLogSeedReq("P", req);
    return orig_seedsend2(self, req, ct, retry, mi);
}

// Capture the game's own feed path: PikminActionManager.ScheduleFeedPikminAsync
// (string pikminId, string itemId). When the user feeds manually, this logs the
// exact itemId that works and captures the manager instance for us to reuse.
static void *gAction = NULL;                      // PikminActionManager
static void *(*orig_schedfeed)(void*, void*, void*, void*);
static void *hook_schedfeed(void *self, void *pikId, void *itemId, void *mi) {
    if (self) gAction = self;
    PALOG(@"[schedFeed] pik='%@' item='%@'", pkStr(pikId) ?: @"", pkStr(itemId) ?: @"");
    return orig_schedfeed(self, pikId, itemId, mi);
}
// Manual harvest goes through the same PikminActionManager, so hooking it arms
// gAction too — the user harvests normally and the feed path becomes available.
static bool (*orig_schedpick)(void*, void*, void*);
static bool hook_schedpick(void *self, void *pikId, void *mi) {
    if (self && !gAction) { gAction = self; PALOG(@"[capture] PikminActionManager=%p (pick)", self); }
    return orig_schedpick(self, pikId, mi);
}

// Capture the live ExpeditionDataStore. It is the game's own registry of every
// expedition the client knows about (available, in progress, returned), keyed by
// task id; its values are ExpeditionItemData objects, which carry the game's own
// eligibility/limit/start logic. Both mutator entry points are hooked because
// AddData only fires the first time a task appears, while NotifyUpdate keeps
// firing afterwards — either one hands us `self`.
static void *gExpStore = NULL;                    // ExpeditionDataStore
static void (*orig_expadd)(void*, void*, void*);
static void hook_expadd(void *self, void *data, void *mi) {
    if (self && !gExpStore) { gExpStore = self; PALOG(@"[capture] ExpeditionDataStore=%p (AddData)", self); }
    orig_expadd(self, data, mi);
}
static void (*orig_expupd)(void*, void*, void*);
static void hook_expupd(void *self, void *data, void *mi) {
    if (self && !gExpStore) { gExpStore = self; PALOG(@"[capture] ExpeditionDataStore=%p (NotifyUpdate)", self); }
    orig_expupd(self, data, mi);
}

// Capture PikminInventoryTools — the Zenject singleton that owns the game's own
// troop-reservation rule. We only need the IClientSettingsCache it holds (@0x18)
// to read the minimum troop size the game keeps back from expeditions.
static void *gPikTools = NULL;                    // PikminInventoryTools
static void (*orig_pitctor)(void*, void*, void*, void*, void*);
static void hook_pitctor(void *self, void *a, void *b, void *c, void *mi) {
    if (self && !gPikTools) { gPikTools = self; PALOG(@"[capture] PikminInventoryTools=%p (ctor)", self); }
    orig_pitctor(self, a, b, c, mi);
}
static bool (*orig_pitin)(void*, void*, void*);
static bool hook_pitin(void *self, void *pid, void *mi) {
    if (self && !gPikTools) { gPikTools = self; PALOG(@"[capture] PikminInventoryTools=%p (inInv)", self); }
    return orig_pitin(self, pid, mi);
}

// Capture FlowerPlantingController — the game's own planting session owner.
// StartPlantingWithConfirmationAsync(petalId, confirmation:false) starts a
// session exactly as the 심기 button does; from then on the game itself sends
// PlantFlower2 as the (spoofed) location moves and stops when petals run out.
// isStarted @0x118 tells whether a session is live.
static void *gPlant = NULL;                       // FlowerPlantingController
static void (*orig_plantinit)(void*, void*);
static void hook_plantinit(void *self, void *mi) {
    if (self && gPlant != self) { gPlant = self; PALOG(@"[capture] FlowerPlantingController=%p (Init)", self); }
    orig_plantinit(self, mi);
}
// Capture MapObjectManager — holds every map object the server streamed for the
// current viewport (big flowers, flower fields, mushrooms) in
// mapObjects Dictionary<string, MapObject> @0x70; MapObject.Proto @0x20.
static void *gMapObj = NULL;                      // MapObjectManager
static void (*orig_mapupd)(void*, void*);
static void hook_mapupd(void *self, void *mi) {
    if (self && gMapObj != self) { gMapObj = self; PALOG(@"[capture] MapObjectManager=%p (Update)", self); }
    orig_mapupd(self, mi);
}

static void pkInstallHooks(void) {
    static BOOL installed = NO;
    if (installed || !resolveAPI()) return;
    void *rpcCls = pkFindClass("Niantic.Ichigo.Rpc", "RpcManager");
    void *mgrCls = pkFindClass("Niantic.Ichigo.Game.Pikmins", "PikminManager");
    if (!rpcCls || !mgrCls) return;
    void *mGP = f_class_get_method_from_name(rpcCls, "SendGetPlayerRpcForResultAsync", 3);
    void *mBA = f_class_get_method_from_name(rpcCls, "SendBatchReportActivityRpcForResultAsync", 3);
    void *mGF = f_class_get_method_from_name(rpcCls, "SendUpdateGamePlayFlagRpcForResultAsync", 3);
    void *mAU = f_class_get_method_from_name(mgrCls, "AddOrUpdatePikmin", 1);
    void *mGK = f_class_get_method_from_name(mgrCls, "GetPikmin", 1);
    if (mGP) { void *fp = *(void**)mGP; if (fp) f_MSHookFunction(fp, (void*)hook_getplayer, (void**)&orig_getplayer); }
    if (mBA) { void *fp = *(void**)mBA; if (fp) f_MSHookFunction(fp, (void*)hook_activity, (void**)&orig_activity); }
    if (mGF) { void *fp = *(void**)mGF; if (fp) f_MSHookFunction(fp, (void*)hook_flag, (void**)&orig_flag); }
    if (mAU) { void *fp = *(void**)mAU; if (fp) f_MSHookFunction(fp, (void*)hook_addupd, (void**)&orig_addupd); }
    if (mGK) { void *fp = *(void**)mGK; if (fp) f_MSHookFunction(fp, (void*)hook_getpikmin, (void**)&orig_getpikmin); }
    // Camera-focus suppressor.
    void *focCls = pkFindClass("Niantic.Ichigo.Game.Garden", "PikminFocusController");
    void *mSF = focCls ? f_class_get_method_from_name(focCls, "SetFocus", 2) : NULL;
    if (mSF) { void *fp = *(void**)mSF; if (fp) f_MSHookFunction(fp, (void*)hook_setfocus, (void**)&orig_setfocus); }
    void *camCls = pkFindClass("Niantic.Ichigo.Game.Garden.Cameras", "PikminCameraController");
    void *mST = camCls ? f_class_get_method_from_name(camCls, "SetTarget", 1) : NULL;
    if (mST) { void *fp = *(void**)mST; if (fp) f_MSHookFunction(fp, (void*)hook_settarget, (void**)&orig_settarget); }
    // Observe manual (and our) feed RPCs — both the ForResult and the plain variant.
    void *mFS = f_class_get_method_from_name(rpcCls, "SendFeedPikminsRpcForResultAsync", 3);
    if (mFS) { void *fp = *(void**)mFS; if (fp) f_MSHookFunction(fp, (void*)hook_feedsend, (void**)&orig_feedsend); }
    void *mFS2 = f_class_get_method_from_name(rpcCls, "SendFeedPikminsRpcAsync", 3);
    if (mFS2) { void *fp = *(void**)mFS2; if (fp) f_MSHookFunction(fp, (void*)hook_feedsend2, (void**)&orig_feedsend2); }
    void *mPS = f_class_get_method_from_name(rpcCls, "SendPickPikminFlowersRpcForResultAsync", 3);
    if (mPS) { void *fp = *(void**)mPS; if (fp) f_MSHookFunction(fp, (void*)hook_picksend, (void**)&orig_picksend); }
    void *mPS2 = f_class_get_method_from_name(rpcCls, "SendPickPikminFlowersRpcAsync", 3);
    if (mPS2) { void *fp = *(void**)mPS2; if (fp) f_MSHookFunction(fp, (void*)hook_picksend2, (void**)&orig_picksend2); }
    void *mSS = f_class_get_method_from_name(rpcCls, "SendSetPikminSeedRpcForResultAsync", 3);
    if (mSS) { void *fp = *(void**)mSS; if (fp) f_MSHookFunction(fp, (void*)hook_seedsend, (void**)&orig_seedsend); }
    void *mSS2 = f_class_get_method_from_name(rpcCls, "SendSetPikminSeedRpcAsync", 3);
    if (mSS2) { void *fp = *(void**)mSS2; if (fp) f_MSHookFunction(fp, (void*)hook_seedsend2, (void**)&orig_seedsend2); }
    // Capture the game's own feed path (manual feeds reveal the working itemId).
    void *actCls = pkFindClass("Niantic.Ichigo.Game", "PikminActionManager");
    void *mSchF = actCls ? f_class_get_method_from_name(actCls, "ScheduleFeedPikminAsync", 2) : NULL;
    if (mSchF) { void *fp = *(void**)mSchF; if (fp) f_MSHookFunction(fp, (void*)hook_schedfeed, (void**)&orig_schedfeed); }
    void *mSchP = actCls ? f_class_get_method_from_name(actCls, "SchedulePickPikminFlowerBatchedRequest", 1) : NULL;
    if (mSchP) { void *fp = *(void**)mSchP; if (fp) f_MSHookFunction(fp, (void*)hook_schedpick, (void**)&orig_schedpick); }
    // PikminInventoryTools — reached for the game's own min-troop setting.
    void *pitCls = pkFindClass("Niantic.Ichigo.Game.Pikmins", "PikminInventoryTools");
    void *mPitC = pitCls ? f_class_get_method_from_name(pitCls, ".ctor", 3) : NULL;
    void *mPitI = pitCls ? f_class_get_method_from_name(pitCls, "IsPikminInInventory", 1) : NULL;
    if (mPitC) { void *fp = *(void**)mPitC; if (fp) f_MSHookFunction(fp, (void*)hook_pitctor, (void**)&orig_pitctor); }
    if (mPitI) { void *fp = *(void**)mPitI; if (fp) f_MSHookFunction(fp, (void*)hook_pitin, (void**)&orig_pitin); }
    // Expedition data store — the source of every startable expedition.
    void *edsCls = pkFindClass("Niantic.Ichigo.Game.Expedition.Data", "ExpeditionDataStore");
    void *mEA = edsCls ? f_class_get_method_from_name(edsCls, "AddData", 1) : NULL;
    void *mEU = edsCls ? f_class_get_method_from_name(edsCls, "NotifyUpdate", 1) : NULL;
    if (mEA) { void *fp = *(void**)mEA; if (fp) f_MSHookFunction(fp, (void*)hook_expadd, (void**)&orig_expadd); }
    if (mEU) { void *fp = *(void**)mEU; if (fp) f_MSHookFunction(fp, (void*)hook_expupd, (void**)&orig_expupd); }
    // Planting controller + map object manager (자동성장).
    void *fpcCls = pkFindClass("Niantic.Ichigo.Game.Flowers", "FlowerPlantingController");
    void *mPI = fpcCls ? f_class_get_method_from_name(fpcCls, "Init", 0) : NULL;
    if (mPI) { void *fp = *(void**)mPI; if (fp) f_MSHookFunction(fp, (void*)hook_plantinit, (void**)&orig_plantinit); }
    void *momCls = pkFindClass("Niantic.Ichigo.Game.MapObjects", "MapObjectManager");
    void *mMU = momCls ? f_class_get_method_from_name(momCls, "Update", 0) : NULL;
    if (mMU) { void *fp = *(void**)mMU; if (fp) f_MSHookFunction(fp, (void*)hook_mapupd, (void**)&orig_mapupd); }
    PALOG(@"[hooks] fpcCls=%p mPI=%p momCls=%p mMU=%p", fpcCls, mPI, momCls, mMU);
    PALOG(@"[hooks] edsCls=%p mEA=%p mEU=%p", edsCls, mEA, mEU);
    PALOG(@"[hooks] mFS=%p mFS2=%p mPS=%p mPS2=%p mSchF=%p mSchP=%p", mFS, mFS2, mPS, mPS2, mSchF, mSchP);
    installed = (mGP || mAU || mGK) != 0;
    PALOG(@"[hooks] rpcCls=%p mgrCls=%p mGP=%p mBA=%p mGF=%p mAU=%p mGK=%p focCls=%p mSF=%p installed=%d",
          rpcCls, mgrCls, mGP, mBA, mGF, mAU, mGK, focCls, mSF, installed);
}

// ---------- generic il2cpp call helpers ----------
static void *pkMethod(void *cls, const char *name, int argc) {
    return cls ? f_class_get_method_from_name(cls, name, argc) : NULL;
}
static void *pkInvoke(void *method, void *obj, void **args) {
    if (!method) return NULL;
    void *exc = NULL;
    void *r = f_runtime_invoke(method, obj, args, &exc);
    return exc ? NULL : r;
}

// ---------- Pikmin enumeration (sorted by pluck time) ----------
typedef struct { void *pk; long long ts; } PkEnt;
static int pkCmp(const void *a, const void *b) {
    long long x = ((const PkEnt*)a)->ts, y = ((const PkEnt*)b)->ts;
    return (x < y) ? -1 : (x > y) ? 1 : 0;
}
static NSData *pkEnumerate(void) {
    if (!gMgr || !resolveAPI()) return nil;
    void *dict = *(void**)((char*)gMgr + 0x60);
    if (!dict) return nil;
    void *dcls = f_object_get_class(dict);
    // .NET Core corlib names the fields _entries/_count (older runtimes: entries/count).
    void *fE = dcls ? f_class_get_field_from_name(dcls, "_entries") : NULL;
    if (!fE && dcls) fE = f_class_get_field_from_name(dcls, "entries");
    void *fC = dcls ? f_class_get_field_from_name(dcls, "_count") : NULL;
    if (!fC && dcls) fC = f_class_get_field_from_name(dcls, "count");
    if (!fE || !fC) return nil;
    void *entries = *(void**)((char*)dict + f_field_get_offset(fE));
    int count = *(int*)((char*)dict + f_field_get_offset(fC));
    if (!entries || count <= 0 || count > 200000) return nil;
    // Entry<string,Pikmin>: hashCode@0, next@4, key@8, value@0x10, size 0x18; array
    // data @+0x20. A used slot is identified robustly by value != null (works for
    // both the .NET Framework and Core entry conventions).
    char *data = (char*)entries + 0x20;
    NSMutableData *out = [NSMutableData data];
    for (int i = 0; i < count; i++) {
        char *e = data + (size_t)i * 0x18;
        void *pk = *(void**)(e + 0x10);
        if (!pk) continue;
        long long ts = 0x7fffffffffffffffLL;
        void *proto = *(void**)((char*)pk + 0xC0);
        if (proto) { void *pl = *(void**)((char*)proto + 0xA0); if (pl) ts = *(long long*)((char*)pl + 0x18); }
        PkEnt ent = { pk, ts };
        [out appendBytes:&ent length:sizeof(ent)];
    }
    NSUInteger n = out.length / sizeof(PkEnt);
    if (!n) return nil;
    qsort((void*)out.mutableBytes, n, sizeof(PkEnt), pkCmp);
    return out;
}

// ---------- request builders / RPC senders ----------
// Add one Il2CppString id into a request's RepeatedField<string> pikminId_ via get_PikminId()+Add.
static void pkAddPikminId(void *req, void *reqCls, void *idStr) {
    void *mGet = pkMethod(reqCls, "get_PikminId", 0);
    void *rf = pkInvoke(mGet, req, NULL);
    if (!rf) return;
    void *rfCls = f_object_get_class(rf);
    void *mAdd = pkMethod(rfCls, "Add", 1);
    void *a[1] = { idStr };
    pkInvoke(mAdd, rf, a);
}
// How many ids actually made it into the request's RepeatedField<string> pikminId_.
static int pkRepeatedCount(void *req, void *reqCls) {
    void *rf = pkInvoke(pkMethod(reqCls, "get_PikminId", 0), req, NULL);
    if (!rf) return -1;
    void *rfCls = f_object_get_class(rf);
    void *fc = f_class_get_field_from_name(rfCls, "count");
    if (!fc) fc = f_class_get_field_from_name(rfCls, "_count");
    if (!fc) return -2;
    return *(int*)((char*)rf + f_field_get_offset(fc));
}

// new + .ctor() a request proto in Ichigo.Proto.
static void *pkNewReq(const char *name, void **outCls) {
    void *cls = pkFindClass("Ichigo.Proto", name);
    if (outCls) *outCls = cls;
    if (!cls) return NULL;
    void *req = f_object_new(cls);
    if (!req) return NULL;
    void *ctor = pkMethod(cls, ".ctor", 0);
    if (ctor) pkInvoke(ctor, req, NULL);
    return req;
}
// Invoke gRpc.<method>(req, CancellationToken.None, RpcRetryPolicy=2). Fire-and-forget.
static BOOL pkSendRpc(const char *rpcMethod, void *req) {
    if (!gRpc || !req) return NO;
    void *rpcCls = f_object_get_class(gRpc);
    void *m = pkMethod(rpcCls, rpcMethod, 3);
    if (!m) return NO;
    unsigned char ct[8] = {0}; int retry = 2;
    void *a[3] = { req, ct, &retry };
    void *exc = NULL;
    f_runtime_invoke(m, gRpc, a, &exc);
    return exc == NULL;
}

// ---------- full owned-Pikmin roster (includes waiting/idle) ----------
// PikminManager.pikmins holds only the ~active in-world set; the complete owned
// roster is InventoryManager.GetPikminList() : List<PikminInventoryItem>. Each
// item's PikminProto (get_Proto) carries id_@0x28, name_@0x30, pluckTime_@0xA0.
// Returns @[ @{ @"id":NSValue(idStr), @"proto":NSValue(proto), @"ts":@(utcMs) } ] sorted by ts.
static NSArray *pkAllPikmin(void) {
    void *inv = gInv();
    if (!inv || !resolveAPI()) return nil;
    void *invCls = f_object_get_class(inv);
    void *mList = pkMethod(invCls, "GetPikminList", 0);
    void *list = pkInvoke(mList, inv, NULL);
    if (!list) return nil;
    int size = *(int*)((char*)list + 0x18);            // List<T>._size
    void *arr = *(void**)((char*)list + 0x10);         // List<T>._items
    if (!arr || size <= 0 || size > 200000) return nil;
    char *data = (char*)arr + 0x20;
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < size; i++) {
        void *item = *(void**)(data + (size_t)i * 8);
        if (!item) continue;
        void *itCls = f_object_get_class(item);
        void *proto = pkInvoke(pkMethod(itCls, "get_Proto", 0), item, NULL);
        if (!proto) continue;
        void *idStr = *(void**)((char*)proto + 0x28);  // PikminProto.id_
        if (!idStr) continue;
        long long ts = 0x7fffffffffffffffLL;
        void *pl = *(void**)((char*)proto + 0xA0);
        if (pl) ts = *(long long*)((char*)pl + 0x18);
        // PikminProto.statusCase_ @0xD0 — Available=1, Task=2 (busy on an
        // expedition/carry), Entourage=32. starred_ @0x98 marks a favourite.
        int status = *(int*)((char*)proto + 0xD0);
        BOOL starred = *(unsigned char*)((char*)proto + 0x98) != 0;
        [out addObject:@{ @"id": [NSValue valueWithPointer:idStr],
                          @"proto": [NSValue valueWithPointer:proto],
                          @"item": [NSValue valueWithPointer:item],
                          @"status": @(status),
                          @"starred": @(starred),
                          @"ts": @(ts) }];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long x = [a[@"ts"] longLongValue], y = [b[@"ts"] longLongValue];
        return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
    }];
    return out;
}

// The deployed squad — PikminManager.playerFollowingPikmins @0x68 is a
// List<IPlayerFollower> whose elements ARE Pikmin objects (Pikmin : IPlayerFollower),
// so each element's id is at Pikmin.id @0xA8. Nectar can only be fed to deployed
// Pikmin, so this is the correct feed target. Returns @[ NSValue(idStr) ].
static NSArray *pkSquad(void) {
    if (!gMgr || !resolveAPI()) return nil;
    void *list = *(void**)((char*)gMgr + 0x68);
    if (!list) return nil;
    int size = *(int*)((char*)list + 0x18);
    void *arr = *(void**)((char*)list + 0x10);
    if (!arr || size <= 0 || size > 10000) return nil;
    // Elements are declared List<IPlayerFollower>; take only the ones that really
    // are Pikmin objects, and read the SERVER id from their proto (Pikmin.pikminProto
    // @0xC0 → PikminProto.id_ @0x28) — the same reliable id rename uses. Reading the
    // runtime Pikmin.id @0xA8 gave ids the feed RPC choked on (null deref at 0xB8).
    void *pikCls = pkFindClass("Niantic.Ichigo.Game.Pikmins", "Pikmin");
    char *data = (char*)arr + 0x20;
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < size; i++) {
        void *pk = *(void**)(data + (size_t)i * 8);
        if (!pk) continue;
        if (pikCls && f_object_get_class(pk) != pikCls) continue;   // real Pikmin only
        void *proto = *(void**)((char*)pk + 0xC0);
        if (!proto) continue;
        void *idStr = *(void**)((char*)proto + 0x28);
        if (!idStr) continue;
        int state = *(int*)((char*)proto + 0x48);       // PikminProto.flowerState_
        int nflw  = *(int*)((char*)proto + 0x38);       // numFlowers_
        [out addObject:@{ @"id": [NSValue valueWithPointer:idStr],
                          @"state": @(state), @"nflw": @(nflw) }];
    }
    return out;
}
// Just the id pointers from a pkSquad() result.
static NSArray *pkSquadIds(NSArray *squad) {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *d in squad) [ids addObject:d[@"id"]];
    return ids;
}

// ---------- nectar (HoneyBall) inventory ----------
// Nectar (HoneyBall) types we are allowed to spend. HoneyType: 1=WHITE, 2=RED,
// 3=BLUE, 4=YELLOW, 5=HAPPY(rainbow). The user opted to burn the four common
// colours and keep HAPPY, so HAPPY(5) and UNKNOWN(0) are excluded.
static BOOL pkNectarAllowed(int honeyType) {
    return honeyType >= 1 && honeyType <= 4;
}

// honeyBall storage @0x48 → ItemStorage.Items List<Predicted<InventoryItem>> @0x10;
// element Predicted.confirmedValue @0x10 → HoneyBallInventoryItem (get_Id, get_Proto),
// HoneyBallProto: numBalls_ @0x18, honeyType_ @0x1C. Returns only the allowed kinds:
// @[ @{ @"id":NSValue(itemIdStr), @"balls":@(n), @"type":@(honeyType) } ].
static int pkProtoBalls(void *item) {   // numBalls_ from a HoneyBallInventoryItem's proto
    if (!item) return 0;
    void *proto = pkInvoke(pkMethod(f_object_get_class(item), "get_Proto", 0), item, NULL);
    if (!proto) return 0;
    return *(int*)((char*)proto + 0x18);
}
static NSArray *pkNectar(void) {
    void *inv = gInv();
    if (!inv || !resolveAPI()) return nil;
    void *storage = *(void**)((char*)inv + 0x48);
    if (!storage) return nil;
    void *items = *(void**)((char*)storage + 0x10);
    if (!items) return nil;
    int size = *(int*)((char*)items + 0x18);
    void *arr = *(void**)((char*)items + 0x10);
    if (!arr || size < 0 || size > 100000) return nil;
    char *data = (char*)arr + 0x20;
    NSMutableArray *out = [NSMutableArray array];
    long long confByType[8] = {0}, predByType[8] = {0};   // histogram for the log
    for (int i = 0; i < size; i++) {
        void *pred = *(void**)(data + (size_t)i * 8);
        if (!pred) continue;
        void *conf = *(void**)((char*)pred + 0x10);        // Predicted.confirmedValue
        void *prd  = *(void**)((char*)pred + 0x18);        // Predicted.predictedValue
        void *item = conf ? conf : prd;
        if (!item) continue;
        void *itCls = f_object_get_class(item);
        void *idStr = pkInvoke(pkMethod(itCls, "get_Id", 0), item, NULL);
        void *proto = pkInvoke(pkMethod(itCls, "get_Proto", 0), item, NULL);
        if (!proto) continue;
        int n = *(int*)((char*)proto + 0x18);              // numBalls_ (confirmed side)
        int type = *(int*)((char*)proto + 0x1C);           // honeyType_
        NSString *fkind = pkStr(*(void**)((char*)proto + 0x28));   // flowerKind_
        int np = prd ? pkProtoBalls(prd) : n;              // predicted count
        if (type >= 0 && type < 8) { confByType[type] += (n > 0 ? n : 0); predByType[type] += (np > 0 ? np : 0); }
        // Only PLAIN colour nectar (empty flowerKind) grows any flower. Flower-specific
        // nectar (e.g. flowerKind "canna", a long itemId) is a server no-op for a broad
        // feed — that is what stalled the nectar total.
        BOOL plain = (fkind.length == 0);
        int use = np;                                      // predicted count = what the user sees
        if (idStr && use > 0 && use < 100000 && pkNectarAllowed(type) && plain)
            [out addObject:@{ @"id": [NSValue valueWithPointer:idStr], @"balls": @(use), @"type": @(type) }];
    }
    static int dumpN = 0;
    if (dumpN++ % 4 == 0)   // periodic histogram so we can verify the type read
        PALOG(@"[nectar] conf W%lld R%lld B%lld Y%lld H%lld | pred W%lld R%lld B%lld Y%lld H%lld",
              confByType[1],confByType[2],confByType[3],confByType[4],confByType[5],
              predByType[1],predByType[2],predByType[3],predByType[4],predByType[5]);
    return out;
}

// Feed one nectar kind to MANY Pikmin in a single FeedPikmins RPC — the request's
// pikminId_ is a repeated field, so the whole roster is fed in parallel in one
// call (no per-Pikmin camera focus, no burst of requests).
static BOOL pkFeedBatch(NSArray<NSValue *> *pikIdPtrs, void *nectarIdStr, int numItems) {
    if (!pikIdPtrs.count || !nectarIdStr) return NO;
    void *cls = NULL;
    void *req = pkNewReq("FeedPikminsRequestProto", &cls);
    if (!req) return NO;
    for (NSValue *v in pikIdPtrs) { void *id = [v pointerValue]; if (id) pkAddPikminId(req, cls, id); }
    void *mItem = pkMethod(cls, "set_ItemId", 1);
    void *a1[1] = { nectarIdStr }; pkInvoke(mItem, req, a1);
    void *mNum = pkMethod(cls, "set_NumItems", 1);
    void *a2[1] = { &numItems }; pkInvoke(mNum, req, a2);
    return pkSendRpc("SendFeedPikminsRpcAsync", req);   // plain variant, as the game uses
}

// ---------- feature: silent auto-numbering ----------
static NSTimer *gNumTimer = NULL;   // paces the rename stream
// Build the list of (pk, desiredNumber) whose current name is wrong.
static void autoNumberPass(void) {
    if (gNumTimer) return;                       // a rename stream already running
    if (!gMgr || !gRpc || !resolveAPI()) return;
    NSArray *all = pkAllPikmin();                // full owned roster (incl. waiting)
    NSUInteger total = all.count;
    if (!total) return;
    void *renCls = pkFindClass("Ichigo.Proto", "RenamePikminRequestProto");
    void *setId = pkMethod(renCls, "set_PikminId", 1);
    void *setNm = pkMethod(renCls, "set_Name", 1);
    if (!renCls || !setId || !setNm) return;
    // Collect mismatches: id = PikminProto.id_, current name = PikminProto.name_ @0x30.
    NSMutableArray<NSArray *> *todo = [NSMutableArray array];   // @[ NSValue(idPtr), numString ]
    for (NSUInteger i = 0; i < total; i++) {
        void *idStr = [all[i][@"id"] pointerValue];
        void *proto = [all[i][@"proto"] pointerValue];
        NSString *cur = proto ? pkStr(*(void**)((char*)proto + 0x30)) : nil;
        NSString *want = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
        if (idStr && ![cur isEqualToString:want])
            [todo addObject:@[ [NSValue valueWithPointer:idStr], want ]];
    }
    PALOG(@"[number] total=%lu mismatches=%lu", (unsigned long)total, (unsigned long)todo.count);
    if (!todo.count) return;
    __block NSUInteger k = 0;
    gNumTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *tm) {
        if (k >= todo.count) { [tm invalidate]; gNumTimer = nil; return; }
        void *idStr = [todo[k][0] pointerValue];
        NSString *want = todo[k][1];
        void *req = pkNewReq("RenamePikminRequestProto", NULL);
        if (req) {
            void *a1[1] = { idStr };            pkInvoke(setId, req, a1);
            void *ns = f_string_new(want.UTF8String);
            void *a2[1] = { ns };               pkInvoke(setNm, req, a2);
            pkSendRpc("SendRenamePikminRpcForResultAsync", req);
        }
        k++;
    }];
}

// ---------- feature: harvest flowers (all owned pikmin) ----------
static NSString *harvestPass(void) {
    if (!gMgr || !gRpc) return @"게임/서버 준비 대기";
    // Only deployed (squad) Pikmin grow flowers to pick, so target just those.
    NSArray *ids = pkSquadIds(pkSquad());
    if (!ids.count) return @"🌸 대열에 피크민 없음";
    // Prefer the game's OWN harvest path: PikminActionManager.SchedulePickPikminFlower-
    // BatchedRequest(pikminId). The raw PickPikminFlowers RPC was silently rejected
    // (flowers never emptied), same as feed — the game method takes the right id
    // form and batches, so it actually picks.
    if (gAction) {
        void *m = pkMethod(f_object_get_class(gAction), "SchedulePickPikminFlowerBatchedRequest", 1);
        if (m) {
            int n = 0;
            for (NSValue *v in ids) { void *pid = [v pointerValue]; void *a[1] = { pid }; if (pkInvoke(m, gAction, a)) n++; (void)n; }
            return [NSString stringWithFormat:@"🌸 수확(게임경로) %lu마리", (unsigned long)ids.count];
        }
    }
    void *cls = NULL;
    void *req = pkNewReq("PickPikminFlowersRequestProto", &cls);
    if (!req) return @"수확 요청 생성 실패";
    for (NSValue *v in ids) { void *idStr = [v pointerValue]; if (idStr) pkAddPikminId(req, cls, idStr); }
    BOOL ok = pkSendRpc("SendPickPikminFlowersRpcForResultAsync", req);
    return ok ? [NSString stringWithFormat:@"🌸 수확(RPC) %lu마리 — gAction 미포착", (unsigned long)ids.count] : @"🌸 수확 전송 실패";
}

// ---------- feature: collect expedition rewards (complete returned tasks) ----------
// Decided by the game's own state machine: ExpeditionDataStore holds an
// ExpeditionItemData per task and its State (Available 0, Outgoing 1, AtSpawn 2,
// Incoming 3, Returned 4) is what the panel's 회수 button reads. Only Returned
// tasks get CompletePikminTask. The earlier version fired it at every task in
// the inventory once a second, ready or not — a pointless request storm.
static void *pkItemProto(void *item);
static NSArray *pkExpeditions(void);
static int pkIntProp(void *obj, const char *name);
#define PK_EXP_RETURNED 4
static NSMutableDictionary<NSString *, NSNumber *> *gCollectSent = nil;
static NSString *collectPass(void) {
    void *inv = gInv();
    if (!inv || !gRpc) return @"인벤토리/서버 준비 대기";
    if (!gExpStore) return @"탐험 스토어 대기 (지도가 뜨면 잡힘)";
    if (!gCollectSent) gCollectSent = [NSMutableDictionary dictionary];
    NSArray *exps = pkExpeditions();
    if (!exps.count) return @"탐험 없음";
    int sent = 0, byState[8] = {0};
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    void *tCls = pkFindClass("Ichigo.Proto", "CompletePikminTaskRequestProto");
    for (NSValue *ev in exps) {
        void *d = [ev pointerValue];
        int st = pkIntProp(d, "get_State");
        if (st >= 0 && st < 8) byState[st]++;
        if (st != PK_EXP_RETURNED) continue;
        void *item = *(void**)((char*)d + 0x78);              // PikminTaskInventoryItem
        void *idStr = item ? pkInvoke(pkMethod(f_object_get_class(item), "get_Id", 0), item, NULL) : NULL;
        if (!idStr) continue;
        NSString *tid = pkStr(idStr) ?: @"";
        NSNumber *when = gCollectSent[tid];
        if (when && now - when.doubleValue < 60.0) continue;    // answer pending
        void *req = tCls ? f_object_new(tCls) : NULL;
        if (!req) continue;
        void *ctor = pkMethod(tCls, ".ctor", 0);
        if (ctor) pkInvoke(ctor, req, NULL);
        *(void**)((char*)req + 0x18) = idStr;          // pikminTaskId_
        if (pkSendRpc("SendCompletePikminTaskRpcForResultAsync", req)) {
            sent++; gCollectSent[tid] = @(now);
            PALOG(@"[collect] 회수 task=%@", tid);
        }
        if (sent >= 5) break;
    }
    return [NSString stringWithFormat:@"📦 회수 요청 %d건 (대기 %d, 출발 %d, 현장 %d, 귀환중 %d, 귀환 %d)",
            sent, byState[0], byState[1], byState[2], byState[3], byState[4]];
}

// ---------- feature: auto-expedition (탐험) ----------
//
// Sends Pikmin on expeditions — the fruit/seedling/gift/postcard tasks, NOT
// mushrooms. Every decision is made by the game's own code so the request we end
// up sending is byte-for-byte the one the Go button would have sent:
//
//   ExpeditionDataStore.cache @0x18  Dictionary<string, IExpeditionDataStoreItem>
//     └─ ExpeditionItemData      item @0x78 (PikminTaskInventoryItem), stats @0x80
//          .Allows(PikminInventoryItem)  — honours the task's restriction
//          .get_MaxPikminsAllowed()      — stats.Weight * 2 (or 1 if restricted)
//          .get_CanTryStart()            — !Started && CarryingPower >= Weight
//          .get_StartDisabledReason()    — non-null means the game would refuse
//          .StartExpeditionAsync()       — builds StartExpeditionRequestProto
//                                          {expeditionTaskId, pikminId[], currentLocation}
//                                          and sends SendStartExpeditionRpc...
//
// Assigning Pikmin is what the panel's 자동 (auto-pick) button does: it writes the
// chosen ids into PikminTaskProto.pikminId_ @0x28 and invalidates the cached
// stats. We do exactly that (SetPikmins' own body), adding one Pikmin at a time
// and asking the game after each whether the party is now strong enough — so the
// party is the smallest one the game itself accepts.
#define PK_TASK_EXPEDITION 6                      // PikminTaskProto.TaskOneofCase.Expedition
#define PK_STATUS_AVAILABLE 1                     // PikminProto.StatusOneofCase.Available
#define PK_STATUS_TASK      2                     // …Task — busy on an expedition/carry
#define PK_STATUS_ENTOURAGE 32                    // …Entourage — walking with the player

// Every ExpeditionItemData currently in the store.
static NSArray *pkExpeditions(void) {
    if (!gExpStore || !resolveAPI()) return nil;
    void *dict = *(void**)((char*)gExpStore + 0x18);
    if (!dict) return nil;
    void *dcls = f_object_get_class(dict);
    void *fE = dcls ? f_class_get_field_from_name(dcls, "_entries") : NULL;
    if (!fE && dcls) fE = f_class_get_field_from_name(dcls, "entries");
    void *fC = dcls ? f_class_get_field_from_name(dcls, "_count") : NULL;
    if (!fC && dcls) fC = f_class_get_field_from_name(dcls, "count");
    if (!fE || !fC) return nil;
    void *entries = *(void**)((char*)dict + f_field_get_offset(fE));
    int count = *(int*)((char*)dict + f_field_get_offset(fC));
    if (!entries || count <= 0 || count > 100000) return nil;
    // The store also holds blockers (mushroom invites) and fakes, so keep only
    // the real ExpeditionItemData objects.
    void *eidCls = pkFindClass("Niantic.Ichigo.Game.Expedition.Data", "ExpeditionItemData");
    if (!eidCls) return nil;
    char *data = (char*)entries + 0x20;
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        void *v = *(void**)(data + (size_t)i * 0x18 + 0x10);
        if (!v || f_object_get_class(v) != eidCls) continue;
        [out addObject:[NSValue valueWithPointer:v]];
    }
    return out;
}

// Write pikmin ids straight into the task proto's RepeatedField<string> and tell
// the item data to drop its cached stats — this is the body of
// ExpeditionItemData.SetPikmins, minus its "already started" guard (we only ever
// call it on tasks we have just confirmed are unstarted).
static void pkAssignPikmins(void *itemData, NSArray<NSValue *> *ids) {
    void *inv = *(void**)((char*)itemData + 0x78);            // PikminTaskInventoryItem
    if (!inv) return;
    void *proto = pkInvoke(pkMethod(f_object_get_class(inv), "get_Proto", 0), inv, NULL);
    if (!proto) return;
    void *rf = *(void**)((char*)proto + 0x28);                // PikminTaskProto.pikminId_
    if (!rf) return;
    void *rfCls = f_object_get_class(rf);
    pkInvoke(pkMethod(rfCls, "Clear", 0), rf, NULL);
    void *mAdd = pkMethod(rfCls, "Add", 1);
    for (NSValue *v in ids) { void *a[1] = { [v pointerValue] }; pkInvoke(mAdd, rf, a); }
    pkInvoke(pkMethod(f_object_get_class(itemData), "InvalidateAllCachedValues", 0), itemData, NULL);
}

static BOOL pkBoolProp(void *obj, const char *name) {
    void *r = pkInvoke(pkMethod(f_object_get_class(obj), name, 0), obj, NULL);
    // il2cpp boxes value-type returns; the payload sits right after the header.
    return r ? (*(unsigned char*)((char*)r + 0x10) != 0) : NO;
}
static int pkIntProp(void *obj, const char *name) {
    void *r = pkInvoke(pkMethod(f_object_get_class(obj), name, 0), obj, NULL);
    return r ? *(int*)((char*)r + 0x10) : 0;
}

// The minimum number of Pikmin the game itself keeps in the troop:
// ClientSettingsProto.pikmin_ @0x78 -> PikminSettingsProto.minTroopPikminCount_ @0x1C
// (the game defaults it to 1 when the field is unset).
static int pkMinTroop(void) {
    if (!gPikTools || !resolveAPI()) return 1;
    void *csc = *(void**)((char*)gPikTools + 0x18);          // IClientSettingsCache
    if (!csc) return 1;
    void *cs = pkInvoke(pkMethod(f_object_get_class(csc), "get_CurrentSettings", 0), csc, NULL);
    if (!cs) return 1;
    void *ps = *(void**)((char*)cs + 0x78);                  // ClientSettingsProto.pikmin_
    if (!ps) return 1;
    int v = *(int*)((char*)ps + 0x1C);                       // minTroopPikminCount_
    return v > 0 ? v : 1;
}

// Candidate Pikmin for an expedition, decided the way the game decides it.
//
// The old rule excluded every troop member outright, which emptied the list on a
// large troop ("후보0 — … 부대제외 31, 부대원 60") and was simply not the game's
// rule. PikminInventoryTools.ReservingPikminForTroop is:
//
//   if (HasUnrestrictedExpedition(onboarding)) reserve nothing
//   needToReserve = count(eligible that are in troop) - GetPikminInTroopCount()
//                   + GetMinTroopPikminCount(clientSettings)
//   reserve the first needToReserve eligible troop members, send the rest
//
// i.e. troop Pikmin ARE sendable; the game only holds back enough of them to keep
// the troop at its minimum size. Troop membership and the troop count come from
// the game's own PikminUtils, not from playerFollowingPikmins.
//
// Busy Pikmin (status Task — already on an expedition or a carry) are the only
// hard exclusion; favourites are kept home as a courtesy, as before.
static NSArray *pkExpeditionCandidates(void) {
    NSArray *all = pkAllPikmin();                  // already sorted by pluck time
    if (!all.count) return nil;
    void *inv = gInv();
    void *utilCls = pkFindClass("Niantic.Ichigo.Game.Pikmins", "PikminUtils");
    void *mInTroop  = pkMethod(utilCls, "IsPikminInTroop", 2);        // (InventoryManager, PikminProto)
    void *mTroopCnt = pkMethod(utilCls, "GetPikminInTroopCount", 1);  // (InventoryManager)

    int troopTotal = 0;
    if (inv && mTroopCnt) {
        void *a[1] = { inv };
        void *r = pkInvoke(mTroopCnt, NULL, a);
        if (r) troopTotal = *(int*)((char*)r + 0x10);
    }

    // PikminUtils declares IsPikminInTroop twice — (PikminProto, InventoryManager)
    // and the [Extension] (InventoryManager, PikminProto). class_get_method_from_name
    // matches on name+argc only, so which one comes back is not knowable up front and
    // the wrong argument order silently answers "not in troop" for everybody (the
    // 0.5.2 run logged "부대원 포함 0" against a troop of 33). Ask both ways and keep
    // the ordering whose tally actually agrees with GetPikminInTroopCount; the status
    // flag (Entourage) is the fallback if neither call is available.
    NSMutableArray *pool = [NSMutableArray array];
    NSCountedSet *statuses = [NSCountedSet set];
    int nStarred = 0, nBusy = 0, nPI = 0, nIP = 0, nEnt = 0;
    for (NSDictionary *d in all) {
        [statuses addObject:d[@"status"]];
        int st = [d[@"status"] intValue];
        if (st == PK_STATUS_TASK || st == 0) { nBusy++; continue; }     // busy / no status
        if ([d[@"starred"] boolValue]) { nStarred++; continue; }        // keep favourites home
        void *proto = [d[@"proto"] pointerValue];
        BOOL pi = NO, ip = NO;
        if (inv && mInTroop) {
            void *a1[2] = { proto, inv };
            void *r1 = pkInvoke(mInTroop, NULL, a1);
            pi = r1 && *(unsigned char*)((char*)r1 + 0x10) != 0;
            void *a2[2] = { inv, proto };
            void *r2 = pkInvoke(mInTroop, NULL, a2);
            ip = r2 && *(unsigned char*)((char*)r2 + 0x10) != 0;
        }
        if (pi) nPI++;
        if (ip) nIP++;
        if (st == PK_STATUS_ENTOURAGE) nEnt++;
        NSMutableDictionary *e = [d mutableCopy];
        e[@"troopPI"] = @(pi); e[@"troopIP"] = @(ip);
        [pool addObject:e];
    }
    // Whichever tally lands closest to the game's own troop count wins.
    NSString *troopKey = @"troopPI"; int poolInTroop = nPI;
    if (abs(nIP - troopTotal) < abs(nPI - troopTotal)) { troopKey = @"troopIP"; poolInTroop = nIP; }
    if (troopTotal > 0 && poolInTroop == 0 && nEnt > 0) { troopKey = nil; poolInTroop = nEnt; }
    for (NSMutableDictionary *e in pool)
        e[@"troop"] = troopKey ? e[troopKey] : @([e[@"status"] intValue] == PK_STATUS_ENTOURAGE);

    // The game's own reservation arithmetic. Non-eligible troop members already
    // satisfy part of the minimum, so only the shortfall is held back.
    int minTroop = pkMinTroop();
    int need = poolInTroop - troopTotal + minTroop;
    NSMutableArray *out = [NSMutableArray array];
    int held = 0;
    for (NSDictionary *d in pool) {
        if (need > 0 && held < need && [d[@"troop"] boolValue]) { held++; continue; }
        [out addObject:d];
    }

    if (!out.count) {
        NSMutableArray *bits = [NSMutableArray array];
        for (NSNumber *k in [statuses.allObjects sortedArrayUsingSelector:@selector(compare:)])
            [bits addObject:[NSString stringWithFormat:@"status%@=%lu", k, (unsigned long)[statuses countForObject:k]]];
        PALOG(@"[탐험] 후보0 — 전체 %lu, %@, 작업중제외 %d, 즐겨찾기제외 %d, 부대유보 %d/%d (부대 %d[%@], 최소 %d)",
              (unsigned long)all.count, [bits componentsJoinedByString:@" "],
              nBusy, nStarred, held, need, troopTotal, troopKey ?: @"ent", minTroop);
    } else {
        PALOG(@"[탐험] 후보 %lu마리 (부대원 포함 %d[%@ pi=%d ip=%d ent=%d], 부대유보 %d, 부대 %d, 최소 %d)",
              (unsigned long)out.count, poolInTroop, troopKey ?: @"ent", nPI, nIP, nEnt,
              held, troopTotal, minTroop);
    }
    return out;
}

// Tasks we have already sent this session, keyed by ExpeditionItemData.Key, with
// the time we sent them — see the cooldown check below.
static NSMutableDictionary<NSString *, NSNumber *> *gExpSent = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gExpTries = nil;
static const NSTimeInterval kExpCooldown = 30.0;
// A task the server keeps refusing must not be retried forever: the wait
// doubles with each attempt that left it Available, up to an hour.
static NSTimeInterval pkExpWait(NSString *key) {
    int n = [gExpTries[key] intValue];
    NSTimeInterval w = kExpCooldown;
    for (int i = 1; i < n && w < 3600.0; i++) w *= 3.0;
    return MIN(w, 3600.0);
}

// One expedition per pass, so the request rate stays ordinary and the log reads
// one line per send-off.
static NSString *expeditionPass(void) {
    if (!gExpSent) gExpSent = [NSMutableDictionary dictionary];
    if (!gExpTries) gExpTries = [NSMutableDictionary dictionary];
    if (!gExpStore) { PALOG(@"[탐험] 스토어 미포착 — 지도에 탐험이 뜨면 잡힘"); return @"탐험 목록 대기 (지도에 탐험이 보이면 잡힘)"; }
    NSArray *exps = pkExpeditions();
    if (!exps.count) { PALOG(@"[탐험] 스토어 비어 있음"); return @"탐험 없음"; }
    // Census of what the store holds, so "nothing sent" can be told apart from
    // "nothing startable is in the store".
    {
        int nExp = 0, nIdle = 0;
        for (NSValue *ev in exps) {
            void *d = [ev pointerValue];
            void *inv = *(void**)((char*)d + 0x78);
            void *pr = inv ? pkInvoke(pkMethod(f_object_get_class(inv), "get_Proto", 0), inv, NULL) : NULL;
            if (!pr) continue;
            if (*(int*)((char*)pr + 0x50) != PK_TASK_EXPEDITION) continue;
            nExp++;
            if (*(long long*)((char*)pr + 0x18) == 0) nIdle++;
        }
        PALOG(@"[탐험] 스토어 %lu건 / 탐험 %d건 / 미출발 %d건",
              (unsigned long)exps.count, nExp, nIdle);
    }
    NSArray *cands = pkExpeditionCandidates();
    if (!cands.count) return @"보낼 피크민 없음";

    int seen = 0;
    for (NSValue *ev in exps) {
        void *d = [ev pointerValue];
        void *inv = *(void**)((char*)d + 0x78);
        if (!inv) continue;
        void *proto = pkInvoke(pkMethod(f_object_get_class(inv), "get_Proto", 0), inv, NULL);
        if (!proto) continue;
        if (*(int*)((char*)proto + 0x50) != PK_TASK_EXPEDITION) continue;  // taskCase_
        // The game's own state machine, not our reading of startTimeMs_:
        // Available 0, Outgoing 1, AtSpawn 2, Incoming 3, Returned 4.
        if (pkIntProp(d, "get_State") != 0) continue;
        seen++;
        void *dCls = f_object_get_class(d);
        // startTimeMs_ only flips once the server has answered, so a second pass
        // inside that round trip sees the task as still unstarted and sends it
        // again — which is exactly what happened when the toggle's immediate pass
        // and the next timer tick landed 0.13s apart. Remember what we just sent.
        NSString *tkey = pkStr(pkInvoke(pkMethod(dCls, "get_Key", 0), d, NULL));
        if (tkey) {
            NSNumber *when = gExpSent[tkey];
            // Still Available after a send means the server did not take it.
            if (when && [NSDate date].timeIntervalSince1970 - when.doubleValue < pkExpWait(tkey)) continue;
        }
        void *mWhy = pkMethod(dCls, "get_StartDisabledReason", 0);
        // StartDisabledReason is recomputed from the party currently assigned, so
        // asking it BEFORE assigning anybody always answered "이 아이템을 운반하려면
        // 피크민의 전체 힘이 더 강해져야 합니다" and every heavy expedition was skipped
        // forever. It is now asked once the party is picked, below.

        int maxN = pkIntProp(d, "get_MaxPikminsAllowed");
        if (maxN <= 0) continue;
        void *mAllows = pkMethod(dCls, "Allows", 1);

        NSMutableArray<NSValue *> *picked = [NSMutableArray array];
        BOOL ready = NO;
        for (NSDictionary *c in cands) {
            if ((int)picked.count >= maxN) break;
            void *item = [c[@"item"] pointerValue];
            if (mAllows) {
                void *a[1] = { item };
                void *r = pkInvoke(mAllows, d, a);
                if (!r || *(unsigned char*)((char*)r + 0x10) == 0) continue;   // restricted task
            }
            [picked addObject:c[@"id"]];
            pkAssignPikmins(d, picked);
            // CanTryStart == !Started && CarryingPower >= Weight, both recomputed
            // by the game from the party we just assigned.
            if (pkBoolProp(d, "get_CanTryStart")) { ready = YES; break; }
        }
        if (!ready) {
            pkAssignPikmins(d, @[]);            // leave the local proto as we found it
            PALOG(@"[탐험] 힘 부족 — 후보 %lu, 뽑음 %lu, 최대 %d",
                  (unsigned long)cands.count, (unsigned long)picked.count, maxN);
            continue;
        }
        // Now that a party is assigned, the game's own veto is meaningful: out of
        // range, inventory full, feature locked, still not strong enough, …
        void *why = pkInvoke(mWhy, d, NULL);
        if (why) {
            pkAssignPikmins(d, @[]);
            PALOG(@"[탐험] 건너뜀 — %@", pkStr(why) ?: @"불가");
            continue;
        }
        void *mStart = pkMethod(dCls, "StartExpeditionAsync", 0);
        if (!mStart) { pkAssignPikmins(d, @[]); return @"StartExpeditionAsync 없음"; }
        pkInvoke(mStart, d, NULL);
        NSString *key = tkey ?: @"?";
        int tries = 0;
        if (tkey) {
            gExpSent[tkey] = @([NSDate date].timeIntervalSince1970);
            tries = [gExpTries[tkey] intValue] + 1;
            gExpTries[tkey] = @(tries);
        }
        PALOG(@"[탐험] 출발 task=%@ 피크민 %lu마리 (최대 %d, %d번째 시도%@)", key, (unsigned long)picked.count, maxN,
              tries, tries > 1 ? [NSString stringWithFormat:@", 다음 대기 %.0f초", pkExpWait(key)] : @"");
        return [NSString stringWithFormat:@"🚀 탐험 출발 — 피크민 %lu마리", (unsigned long)picked.count];
    }
    return seen ? [NSString stringWithFormat:@"보낼 수 있는 탐험 없음 (미출발 %d건)", seen]
                : @"대기 중인 탐험 없음";
}

// ---------- feature: auto-feed nectar ----------
// Each pass feeds up to kFeedPerTick Pikmin one nectar each, cycling through the
// nectar kinds we hold, until no nectar is left. Conservative batch size keeps
// the request rate ordinary and lets the log show nectar draining pass by pass.
static NSString *feedPass(void) {
    if (!gMgr || !gRpc) return @"게임/서버 준비 대기";
    NSArray *nectar = pkNectar();                       // allowed kinds (W/R/B/Y), predicted balls
    long long total = 0;
    NSDictionary *best = nil;
    for (NSDictionary *d in nectar) {
        total += [d[@"balls"] longLongValue];
        if (!best || [d[@"balls"] intValue] > [best[@"balls"] intValue]) best = d;
    }
    PALOG(@"[feed] allowed kinds=%lu total=%lld", (unsigned long)nectar.count, total);
    if (total <= 0 || !best) return @"🍯 정수 소진 — 급여 완료";
    PALOG(@"[feed] best itemId='%@' type=%@ balls=%@",
          pkStr([best[@"id"] pointerValue]), best[@"type"], best[@"balls"]);
    // Diagnostic: the first deployed Pikmin's flower state — feeding a maxed flower
    // is a server no-op. PikminProto: numFlowers_@0x38, flowerState_@0x48,
    // flowerStateFlowerCount_@0x58, wiltedCount_@0x5C.
    {
        void *fl = *(void**)((char*)gMgr + 0x68);
        void *fa = fl ? *(void**)((char*)fl + 0x10) : NULL;
        int fs = fl ? *(int*)((char*)fl + 0x18) : 0;
        if (fa && fs > 0) {
            void *pk0 = *(void**)((char*)fa + 0x20);
            void *pr0 = pk0 ? *(void**)((char*)pk0 + 0xC0) : NULL;
            if (pr0)
                PALOG(@"[feed] flower0 numFlowers=%d state=%d stateCnt=%d wilt=%d",
                      *(int*)((char*)pr0 + 0x38), *(int*)((char*)pr0 + 0x48),
                      *(int*)((char*)pr0 + 0x58), *(int*)((char*)pr0 + 0x5C));
        }
    }
    PALOG(@"[feed] step1 squad read");
    // Only deployed (squad) Pikmin can be fed — waiting ones are rejected server-side.
    NSArray *squad = pkSquad();
    // A Pikmin whose flower is already at its max petals is rejected server-side
    // (no nectar spent), and harvest keeps the others below max, so this spends
    // nectar only where there is actually room — without needing the
    // per-friendship capacity table. (flowerState stays FLOWER even after a
    // harvest, so it can't be used to tell "has room".)
    //
    // Pipeline pacing: the squad is fed in rotation, a handful per pass, one
    // Pikmin per FeedPikmins RPC (the shape the game's manual feed uses — a
    // 24-in-one RPC never consumed nectar). Feeding the whole squad every
    // second was dozens of RPCs a second; this is a few every kFeedPace.
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *d in squad) [ids addObject:d[@"id"]];   // whole squad
    void *nid = [best[@"id"] pointerValue];
    if (!ids.count) return @"🍯 대열에 피크민 없음 (배치/출격 필요)";
    static NSUInteger cursor = 0;
    const int kMaxPerPass = 8;
    int sent = 0;
    for (int k = 0; k < kMaxPerPass && k < (int)ids.count; k++) {
        NSValue *v = ids[(cursor + k) % ids.count];
        if (pkFeedBatch(@[ v ], nid, 1)) sent++;
    }
    cursor = (cursor + kMaxPerPass) % ids.count;
    PALOG(@"[feed] per-pikmin RPCs sent=%d itemId='%@' (squad %lu, cursor %lu)", sent, pkStr(nid) ?: @"",
          (unsigned long)ids.count, (unsigned long)cursor);
    return [NSString stringWithFormat:@"🍯 대열급여 %d마리(1개씩) type%@ / 정수총 %lld",
            sent, best[@"type"], total];
}

// ================= 자동성장 (auto-grow) pipeline =================
//
// The nectar loop from the field guide, automated end to end:
//   walk (GPS Wander)  →  plant flowers with the petal colour we are shortest
//   of  →  claim nectar from every bloomed big flower we pass  →  fruit
//   expeditions spawn around fresh blooms and the 탐험 pass sends them  →
//   수집 completes them (fruit → nectar)  →  정수 feeds the squad  →  수확
//   picks the petals  →  seedlings ride the step count in the planter and are
//   plucked the moment they are ripe.
//
// Everything below is decided from the game's own state and sent through the
// game's own RPC wrappers; nothing is forged.

// ---------- current (spoofed) location ----------
static CLLocationManager *gLoc = nil;
static CLLocation *gLastLoc = nil;                // whatever CoreLocation (or GPS Wander) hands us
static double pkDistM(double lat1, double lng1, double lat2, double lng2) {
    double r = 6371000.0, p = M_PI / 180.0;
    double dlat = (lat2 - lat1) * p, dlng = (lng2 - lng1) * p;
    double a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1 * p) * cos(lat2 * p) * sin(dlng / 2) * sin(dlng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}

// ---------- small il2cpp collection helpers ----------
// List<T> of reference T: _items @0x10, _size @0x18, array data @+0x20.
static void pkEachList(void *list, void (^fn)(void *item)) {
    if (!list) return;
    int size = *(int*)((char*)list + 0x18);
    void *arr = *(void**)((char*)list + 0x10);
    if (!arr || size <= 0 || size > 100000) return;
    char *data = (char*)arr + 0x20;
    for (int i = 0; i < size; i++) { void *it = *(void**)(data + (size_t)i * 8); if (it) fn(it); }
}
// RepeatedField<T> of reference T: fields `array` / `count` (resolved by name).
static void pkEachRepeated(void *rf, void (^fn)(void *item)) {
    if (!rf) return;
    void *cls = f_object_get_class(rf);
    void *fa = f_class_get_field_from_name(cls, "array");
    void *fc = f_class_get_field_from_name(cls, "count");
    if (!fa || !fc) return;
    void *arr = *(void**)((char*)rf + f_field_get_offset(fa));
    int n = *(int*)((char*)rf + f_field_get_offset(fc));
    if (!arr || n <= 0 || n > 100000) return;
    char *data = (char*)arr + 0x20;
    for (int i = 0; i < n; i++) { void *it = *(void**)(data + (size_t)i * 8); if (it) fn(it); }
}
static void *pkInvList(const char *getter) {          // InventoryManager.Get*List()
    void *inv = gInv();
    return inv ? pkInvoke(pkMethod(f_object_get_class(inv), getter, 0), inv, NULL) : NULL;
}
static void *pkItemProto(void *item) { return item ? pkInvoke(pkMethod(f_object_get_class(item), "get_Proto", 0), item, NULL) : NULL; }
static void *pkItemId(void *item)    { return item ? pkInvoke(pkMethod(f_object_get_class(item), "get_Id", 0), item, NULL) : NULL; }
// A nested class (Outer.Types.Inner) cannot be found by dotted name; walk the
// outer class's nested types instead.
static void *pkNestedClass(void *outer, const char *name) {
    if (!outer || !f_class_get_nested_types || !f_class_get_name) return NULL;
    void *iter = NULL, *k;
    while ((k = f_class_get_nested_types(outer, &iter))) {
        if (!strcmp(f_class_get_name(k), name)) return k;
        // Types live one level deeper (Outer.Types.Inner).
        if (!strcmp(f_class_get_name(k), "Types")) {
            void *it2 = NULL, *k2;
            while ((k2 = f_class_get_nested_types(k, &it2)))
                if (!strcmp(f_class_get_name(k2), name)) return k2;
        }
    }
    return NULL;
}
static void *pkNewObj(void *cls) {
    if (!cls) return NULL;
    void *o = f_object_new(cls);
    if (!o) return NULL;
    void *ctor = pkMethod(cls, ".ctor", 0);
    if (ctor) pkInvoke(ctor, o, NULL);
    return o;
}
// Ichigo.Proto.PointProto{latDegrees_ @0x18, lngDegrees_ @0x20}
static void *pkNewPoint(double lat, double lng) {
    void *p = pkNewReq("PointProto", NULL);
    if (!p) return NULL;
    *(double*)((char*)p + 0x18) = lat;
    *(double*)((char*)p + 0x20) = lng;
    return p;
}

// ---------- why these calls are fire-and-forget ----------
//
// It is tempting to read the Task each RpcManager method returns and log what
// the server actually said. Two attempts wedged the whole app about a second
// after the first tracked call — once with a pinned GC handle, once with a
// plain one and purely field-based reads — so the game does not survive us
// holding on to its Tasks from an NSTimer tick. Nothing in the log, no crash
// report, and uiopen would not bring it back.
//
// Results are therefore judged from state the game itself keeps and we already
// read every pass: a claimed flower has visitRewardReceived_ set on its map
// object, a planted seedling has plantedTimeMs_, a started expedition leaves
// ExpeditionState.Available. That is slower to observe but cannot hang.

// ---------- map objects (big flowers etc.) ----------
#define PK_MO_POIFLOWER   13      // MapObjectProto.ObjectOneofCase
#define PK_MO_FLOWERFIELD 14
#define PK_MO_OVERLAY     21
#define PK_MO_MUSHROOM    22
#define PK_MO_CAMPAIGN    23
#define PK_FS_LEAF        1       // PoiFlowerOverlayProto.Types.State
#define PK_FS_BUD         2
#define PK_FS_FLOWER      3
#define PK_FS_FULL_BLOOM  4
#define PK_FS_PRE_FLOWER  5

// Every object the manager holds:
//   @{ id, idp(NSValue Il2CppString), kind, lat, lng, state, color, bloom(ms), visited }
// MapObjectProto: id_ @0x18, point_ @0x20, object_ @0x30, objectCase_ @0x38.
// PoiFlowerProto: state_ @0x18, appearance_ @0x20 (FlowerProto.color_ @0x18),
//   bloomedTimeMs_ @0x40, visitRewardReceived_ @0x48.
// PoiFlowerOverlayProto: state_ @0x18, flower_ @0x20 (FlowerPetalProto.flowerType_ @0x18),
//   lastBloomingMs_ @0x28.
static NSArray *pkMapObjects(void) {
    if (!gMapObj || !resolveAPI()) return nil;
    void *dict = *(void**)((char*)gMapObj + 0x70);
    if (!dict) return nil;
    void *dcls = f_object_get_class(dict);
    void *fE = dcls ? f_class_get_field_from_name(dcls, "_entries") : NULL;
    if (!fE && dcls) fE = f_class_get_field_from_name(dcls, "entries");
    void *fC = dcls ? f_class_get_field_from_name(dcls, "_count") : NULL;
    if (!fC && dcls) fC = f_class_get_field_from_name(dcls, "count");
    if (!fE || !fC) return nil;
    void *entries = *(void**)((char*)dict + f_field_get_offset(fE));
    int count = *(int*)((char*)dict + f_field_get_offset(fC));
    if (!entries || count <= 0 || count > 100000) return nil;
    char *data = (char*)entries + 0x20;
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        void *v = *(void**)(data + (size_t)i * 0x18 + 0x10);
        if (!v) continue;
        // MapObjectManager.MapObject: Proto @0x10 is a Predicted<MapObjectProto>
        // (confirmedValue @0x10, predictedValue @0x18) — take the predicted one,
        // which is what the map shows, falling back to the confirmed one.
        void *pred = *(void**)((char*)v + 0x10);
        if (!pred) continue;
        void *proto = *(void**)((char*)pred + 0x18);
        if (!proto) proto = *(void**)((char*)pred + 0x10);
        if (!proto) continue;
        void *idStr = *(void**)((char*)proto + 0x18);
        void *pt    = *(void**)((char*)proto + 0x20);
        void *obj   = *(void**)((char*)proto + 0x30);
        int kase    = *(int*)((char*)proto + 0x38);
        if (!idStr || !pt) continue;
        double lat = *(double*)((char*)pt + 0x18), lng = *(double*)((char*)pt + 0x20);
        int state = 0, color = 0; long long bloom = 0; BOOL visited = NO;
        if (kase == PK_MO_POIFLOWER && obj) {
            state = *(int*)((char*)obj + 0x18);
            void *ap = *(void**)((char*)obj + 0x20);
            color = ap ? *(int*)((char*)ap + 0x18) : 0;
            bloom = *(long long*)((char*)obj + 0x40);
            visited = *(unsigned char*)((char*)obj + 0x48) != 0;
        } else if (kase == PK_MO_OVERLAY && obj) {
            state = *(int*)((char*)obj + 0x18);
            void *fp = *(void**)((char*)obj + 0x20);
            color = fp ? *(int*)((char*)fp + 0x18) : 0;
            bloom = *(long long*)((char*)obj + 0x28);
        }
        NSString *ids = pkStr(idStr) ?: @"";
        [out addObject:@{ @"id": ids, @"idp": [NSValue valueWithPointer:idStr], @"kind": @(kase),
                          @"lat": @(lat), @"lng": @(lng), @"state": @(state), @"color": @(color),
                          @"bloom": @(bloom), @"visited": @(visited) }];
    }
    return out;
}

// Dump the current map objects + our position to Documents/mapobjects.json so
// GPS Wander can draw them and route the walk through the big flowers.
static void mapDumpPass(void) {
    NSArray *objs = pkMapObjects();
    if (!objs) return;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *o in objs) {
        [rows addObject:@{ @"id": o[@"id"], @"kind": o[@"kind"], @"lat": o[@"lat"], @"lng": o[@"lng"],
                           @"state": o[@"state"], @"color": o[@"color"], @"bloom": o[@"bloom"],
                           @"visited": o[@"visited"] }];
    }
    NSDictionary *doc = @{ @"t": @([NSDate date].timeIntervalSince1970),
                           @"lat": @(gLastLoc ? gLastLoc.coordinate.latitude : 0),
                           @"lng": @(gLastLoc ? gLastLoc.coordinate.longitude : 0),
                           @"objs": rows };
    NSData *json = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
    if (!json) return;
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                      stringByAppendingPathComponent:@"mapobjects.json"];
    [json writeToFile:path atomically:YES];
    // A copy where GPS Wander looks first. The sandbox may refuse; say so once.
    static int sharedState = -1;
    NSError *e = nil;
    BOOL ok = [json writeToFile:@"/var/jb/var/mobile/Library/GPSWander/mapobjects.json"
                        options:NSDataWritingAtomic error:&e];
    if ((int)ok != sharedState) {
        sharedState = ok;
        PALOG(@"[map] shared copy %@%@", ok ? @"written" : @"refused", ok ? @"" : [NSString stringWithFormat:@" — %@", e.localizedDescription]);
    }
}

// ---------- feature: 큰꽃 정수 (claim the visit reward of bloomed big flowers) ----------
// PoiFlowerVisitRewardClaimer.CanTryClaim = IsBlooming && !VisitRewardReceived &&
// IsWithinRange && HasCapacity. We check the first three from the map object and
// our own position; the server answers with FailedReason for the rest.
static NSMutableDictionary<NSString *, NSNumber *> *gPoiTried = nil;
// PoiInteractionSettings.DEFAULT_POI_FLOWER_RANGE = 100 m — the game's own
// range for a big flower (campaigns carry their own interactionRangeMeter_).
// A tighter guess (40 m) meant we never even asked while standing 56 m away.
static const double kPoiRangeM = 100.0;
static const NSTimeInterval kPoiRetry = 180.0;    // seconds before re-asking for the same flower
static NSString *bigFlowerPass(void) {
    if (!gMapObj) return @"맵 오브젝트 대기";
    if (!gRpc) return @"서버 준비 대기";
    if (!gLastLoc) return @"위치 대기";
    if (!gPoiTried) gPoiTried = [NSMutableDictionary dictionary];
    NSArray *objs = pkMapObjects();
    int nFlower = 0, nBloom = 0, nNear = 0, sent = 0;
    double mlat = gLastLoc.coordinate.latitude, mlng = gLastLoc.coordinate.longitude;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    for (NSDictionary *o in objs) {
        if ([o[@"kind"] intValue] != PK_MO_POIFLOWER) continue;
        nFlower++;
        int st = [o[@"state"] intValue];
        if (st != PK_FS_FLOWER && st != PK_FS_FULL_BLOOM) continue;
        nBloom++;
        if ([o[@"visited"] boolValue]) continue;
        double d = pkDistM(mlat, mlng, [o[@"lat"] doubleValue], [o[@"lng"] doubleValue]);
        if (d > kPoiRangeM) continue;
        nNear++;
        NSString *mid = o[@"id"];
        NSNumber *when = gPoiTried[mid];
        if (when && now - when.doubleValue < kPoiRetry) continue;
        void *req = pkNewReq("ClaimPoiFlowerVisitRewardRequestProto", NULL);
        if (!req) return @"큰꽃 요청 생성 실패";
        *(void**)((char*)req + 0x18) = [o[@"idp"] pointerValue];   // mapObjectId_
        *(unsigned char*)((char*)req + 0x20) = 1;                   // includeFailedReason_
        // Plain variant — the one a successful claim was first observed with.
        // Fire and forget: the answer is read off the map object instead (the
        // server sets visitRewardReceived_), because touching the returned Task
        // at all wedged the app twice. See the note above pkSendRpc.
        if (pkSendRpc("SendClaimPoiFlowerVisitRewardRpcAsync", req)) {
            sent++;
            gPoiTried[mid] = @(now);
            PALOG(@"[큰꽃] 정수 채집 요청 id=%@ state=%d color=%@ dist=%.0fm", mid, st, o[@"color"], d);
        }
        if (sent >= 2) break;
    }
    // Did the last claim take? The server flips visitRewardReceived_ on the map
    // object, so the flag is the answer — no response parsing needed.
    static NSUInteger lastClaimed = 0;
    NSUInteger claimed = 0;
    for (NSDictionary *o in objs)
        if ([o[@"kind"] intValue] == PK_MO_POIFLOWER && [o[@"visited"] boolValue]) claimed++;
    if (claimed != lastClaimed) {
        PALOG(@"[큰꽃] 채집 완료 표시 %lu → %lu", (unsigned long)lastClaimed, (unsigned long)claimed);
        lastClaimed = claimed;
    }
    return [NSString stringWithFormat:@"🌼 큰꽃 %d / 만개 %d / 사정권(≤%.0fm) %d / 요청 %d / 채집됨 %lu",
            nFlower, nBloom, kPoiRangeM, nNear, sent, (unsigned long)claimed];
}

// ---------- feature: 꽃 심기 (keep a planting session running) ----------
// Petal choice: plain petals only (special kinds are kept for decor), colour =
// whichever of white/red/blue/yellow we hold the least nectar of, among the
// colours we have petals for. FlowerProto.Types.Type FLOWER_0..3 (1..4) line up
// with HoneyType WHITE/RED/BLUE/YELLOW (1..4).
static long long gNectarPred[8];                   // filled by pkNectarCensus()
static void pkNectarCensus(void) {
    memset(gNectarPred, 0, sizeof(gNectarPred));
    void *inv = gInv();
    if (!inv) return;
    void *storage = *(void**)((char*)inv + 0x48);
    void *items = storage ? *(void**)((char*)storage + 0x10) : NULL;
    pkEachList(items, ^(void *pred) {
        void *conf = *(void**)((char*)pred + 0x10);
        void *prd  = *(void**)((char*)pred + 0x18);
        void *item = prd ? prd : conf;
        void *proto = pkItemProto(item);
        if (!proto) return;
        int n = *(int*)((char*)proto + 0x18), type = *(int*)((char*)proto + 0x1C);
        NSString *fkind = pkStr(*(void**)((char*)proto + 0x28));
        if (type >= 0 && type < 8 && n > 0 && fkind.length == 0) gNectarPred[type] += n;
    });
}
// @[ @{ idp, color, kind, num, special } ] — FlowerPetalProto: flowerType_ @0x18,
// kind_ @0x1C, numPetal_ @0x20, flowerKind_ @0x28.
static NSArray *pkPetals(void) {
    NSMutableArray *out = [NSMutableArray array];
    pkEachList(pkInvList("GetFlowerPetalList"), ^(void *item) {
        void *proto = pkItemProto(item);
        void *idp = pkItemId(item);
        if (!proto || !idp) return;
        int color = *(int*)((char*)proto + 0x18), kind = *(int*)((char*)proto + 0x1C);
        int num = *(int*)((char*)proto + 0x20);
        NSString *fk = pkStr(*(void**)((char*)proto + 0x28));
        BOOL special = (kind != 0) || (fk.length > 0);
        if (num <= 0) return;
        [out addObject:@{ @"idp": [NSValue valueWithPointer:idp], @"id": pkStr(idp) ?: @"",
                          @"color": @(color), @"kind": @(kind), @"num": @(num), @"special": @(special) }];
    });
    return out;
}
static NSString *plantPass(void) {
    if (!gPlant) return @"심기 컨트롤러 대기 (지도 화면이 뜨면 잡힘)";
    if (!gRpc || !gInv()) return @"서버 준비 대기";
    BOOL started = *(unsigned char*)((char*)gPlant + 0x118) != 0;    // isStarted
    NSArray *petals = pkPetals();
    long long plain = 0, special = 0;
    for (NSDictionary *p in petals) { if ([p[@"special"] boolValue]) special += [p[@"num"] intValue]; else plain += [p[@"num"] intValue]; }
    static NSTimeInterval lastCensus = 0;
    if ([NSDate date].timeIntervalSince1970 - lastCensus > 300) {   // what we hold, every 5 min
        lastCensus = [NSDate date].timeIntervalSince1970;
        NSMutableArray *bits = [NSMutableArray array];
        for (NSDictionary *p in petals)
            [bits addObject:[NSString stringWithFormat:@"c%@k%@x%@%@", p[@"color"], p[@"kind"], p[@"num"],
                             [p[@"special"] boolValue] ? @"*" : @""]];
        PALOG(@"[심기] 꽃잎 재고: %@", [bits componentsJoinedByString:@" "]);
    }
    if (started) return [NSString stringWithFormat:@"🌱 심는 중 (일반 꽃잎 %lld, 특수 %lld)", plain, special];
    if (plain <= 0) return [NSString stringWithFormat:@"🌱 일반 꽃잎 없음 (특수 %lld 보존)", special];
    pkNectarCensus();
    NSDictionary *best = nil; long long bestNectar = 0;
    for (NSDictionary *p in petals) {
        if ([p[@"special"] boolValue]) continue;
        int c = [p[@"color"] intValue];
        long long nec = (c >= 1 && c <= 4) ? gNectarPred[c] : 0x7fffffff;
        if (!best || nec < bestNectar || (nec == bestNectar && [p[@"num"] intValue] > [best[@"num"] intValue])) { best = p; bestNectar = nec; }
    }
    if (!best) return @"🌱 쓸 꽃잎 없음";
    void *m = pkMethod(f_object_get_class(gPlant), "StartPlantingWithConfirmationAsync", 2);
    if (!m) return @"StartPlantingWithConfirmationAsync 없음";
    unsigned char confirm = 0;
    void *a[2] = { [best[@"idp"] pointerValue], &confirm };
    void *r = pkInvoke(m, gPlant, a);
    PALOG(@"[심기] 시작 petal=%@ color=%@ num=%@ (정수 W%lld R%lld B%lld Y%lld) task=%p",
          best[@"id"], best[@"color"], best[@"num"], gNectarPred[1], gNectarPred[2], gNectarPred[3], gNectarPred[4], r);
    return [NSString stringWithFormat:@"🌱 심기 시작 — 색 %@ 꽃잎 %@장", best[@"color"], best[@"num"]];
}

// ---------- feature: 모종 (plant seedlings into free planter slots, pluck ripe ones) ----------
// PikminSeedProto: requiredSteps_ @0x50, currentSteps_ @0x54, currentBonusSteps_ @0x58,
//   plantedTimeMs_ @0x60, starred_ @0x70.
// PlanterProto: slot_ @0x20 RepeatedField<SlotProto>; SlotProto: pikminSeedId_ @0x18,
//   remainingUse_ @0x20, index_ @0x24, slotType_ @0x28 (1 = disposable).
// SetPikminSeedRequestProto: seedId_ @0x18, point_ @0x20, slotOption_ @0x28 {slotIndex_ @0x18}.
// PullPikminRequestProto: seedId_ RepeatedField<string> (get_SeedId).
static NSMutableDictionary<NSString *, NSNumber *> *gSeedSent = nil;
static const NSTimeInterval kSeedRetry = 120.0;
static NSString *seedPass(void) {
    if (!gRpc || !gInv()) return @"서버 준비 대기";
    if (!gSeedSent) gSeedSent = [NSMutableDictionary dictionary];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableArray *ripe = [NSMutableArray array], *waiting = [NSMutableArray array];
    __block int nPlanted = 0, nSeeds = 0;
    pkEachList(pkInvList("GetPikminSeedList"), ^(void *item) {
        void *proto = pkItemProto(item);
        void *idp = pkItemId(item);
        if (!proto || !idp) return;
        nSeeds++;
        int req = *(int*)((char*)proto + 0x50), cur = *(int*)((char*)proto + 0x54);
        float bonus = *(float*)((char*)proto + 0x58);
        long long planted = *(long long*)((char*)proto + 0x60);
        void *birth = *(void**)((char*)proto + 0x28);          // birthPlacePoint_
        NSDictionary *d = @{ @"idp": [NSValue valueWithPointer:idp], @"id": pkStr(idp) ?: @"",
                             @"req": @(req), @"cur": @(cur), @"bonus": @(bonus),
                             @"blat": @(birth ? *(double*)((char*)birth + 0x18) : 0),
                             @"blng": @(birth ? *(double*)((char*)birth + 0x20) : 0) };
        if (planted > 0) { nPlanted++; if (req > 0 && cur + (int)bonus >= req) [ripe addObject:d]; }
        else [waiting addObject:d];
    });
    int pulled = 0, set = 0;
    // 1) Pluck ripe seedlings — one PullPikmin RPC, up to 5 ids.
    if (ripe.count) {
        void *cls = NULL;
        void *req = pkNewReq("PullPikminRequestProto", &cls);
        void *rf = req ? pkInvoke(pkMethod(cls, "get_SeedId", 0), req, NULL) : NULL;
        void *mAdd = rf ? pkMethod(f_object_get_class(rf), "Add", 1) : NULL;
        if (mAdd) {
            for (NSDictionary *d in ripe) {
                NSNumber *when = gSeedSent[d[@"id"]];
                if (when && now - when.doubleValue < kSeedRetry) continue;
                void *a[1] = { [d[@"idp"] pointerValue] };
                pkInvoke(mAdd, rf, a);
                gSeedSent[d[@"id"]] = @(now);
                PALOG(@"[모종] 뽑기 id=%@ steps %@/%@", d[@"id"], d[@"cur"], d[@"req"]);
                if (++pulled >= 5) break;
            }
            if (pulled) pkSendRpc("SendPullPikminRpcForResultAsync", req);
        }
    }
    // 2) Fill free planter slots with the seedlings that ripen soonest.
    NSMutableArray *freeSlots = [NSMutableArray array];
    __block int nSlots = 0;
    pkEachList(pkInvList("GetPlanterList"), ^(void *planter) {
        void *proto = pkItemProto(planter);
        if (!proto) return;
        pkEachRepeated(*(void**)((char*)proto + 0x20), ^(void *slot) {
            nSlots++;
            NSString *sid = pkStr(*(void**)((char*)slot + 0x18));
            int remaining = *(int*)((char*)slot + 0x20), idx = *(int*)((char*)slot + 0x24), type = *(int*)((char*)slot + 0x28);
            if (sid.length) return;                              // occupied
            if (type == 1 && remaining <= 0) return;             // used-up disposable slot
            [freeSlots addObject:@(idx)];
        });
    });
    // Until a planting is seen to take (planted count goes up), do not keep
    // trying with the next seed every pass — one attempt, then wait 5 minutes.
    static NSTimeInterval lastTry = 0; static int plantedAtTry = -1;
    BOOL took = nPlanted > plantedAtTry;
    BOOL mayPlant = (now - lastTry >= 300.0) || took;
    if (freeSlots.count && waiting.count && gLastLoc && mayPlant) {
        [waiting sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"req"] compare:b[@"req"]];
        }];
        for (NSDictionary *d in waiting) {
            if (set >= (int)freeSlots.count) break;
            NSNumber *when = gSeedSent[d[@"id"]];
            if (when && now - when.doubleValue < kSeedRetry) continue;
            // Exactly the request the game's own planter sends (captured with
            // [seedRPC]): seedId, point = the seed's birth place, NO slot option
            // — the server picks the slot. Ours with slotIndex + current position
            // was silently refused.
            void *cls = NULL;
            void *req = pkNewReq("SetPikminSeedRequestProto", &cls);
            if (!req) break;
            double blat = [d[@"blat"] doubleValue], blng = [d[@"blng"] doubleValue];
            if (blat == 0 && blng == 0) { blat = gLastLoc.coordinate.latitude; blng = gLastLoc.coordinate.longitude; }
            *(void**)((char*)req + 0x18) = [d[@"idp"] pointerValue];                 // seedId_
            *(void**)((char*)req + 0x20) = pkNewPoint(blat, blng);                    // point_
            lastTry = now; plantedAtTry = nPlanted;
            if (pkSendRpc("SendSetPikminSeedRpcAsync", req)) {
                gSeedSent[d[@"id"]] = @(now);
                PALOG(@"[모종] 심기 id=%@ req=%@ point=(%.6f,%.6f)", d[@"id"], d[@"req"], blat, blng);
                set++;
            }
            break;   // one planting per pass — the slot list refreshes after the server answers
        }
    }
    return [NSString stringWithFormat:@"🌰 모종 %d (화분 %d, 익음 %lu, 대기 %lu) / 빈칸 %lu / 뽑기 %d 심기 %d",
            nSeeds, nPlanted, (unsigned long)ripe.count, (unsigned long)waiting.count,
            (unsigned long)freeSlots.count, pulled, set];
}

// ================= Overlay UI =================
// Minimal delegate so the keep-alive location session is treated as active.
@interface PAKeepAlive : NSObject <CLLocationManagerDelegate>
@end
@class PAOverlay;
@implementation PAKeepAlive
- (void)locationManager:(CLLocationManager *)m didUpdateLocations:(NSArray *)locs {
    // Fires in the background too (while the location session is alive), so this is
    // what keeps the automation running when the phone is locked.
    if (locs.lastObject) gLastLoc = locs.lastObject;
    [NSClassFromString(@"PAOverlay") performSelector:@selector(runDue)];
}
- (void)locationManager:(CLLocationManager *)m didFailWithError:(NSError *)e {}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)m {
    PALOG(@"[keepalive] auth changed -> %d", (int)m.authorizationStatus);
}
@end

@interface PAPassWindow : UIWindow @end
@implementation PAPassWindow
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:pt withEvent:e];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface PAOverlay : NSObject
+ (void)ensure;
@end

static UIWindow *gWin = nil;
static UILabel  *gToast = nil;
static UIButton *gHarvestBtn = nil, *gCollectBtn = nil, *gFeedBtn = nil, *gExpedBtn = nil;
static UIButton *gPlantBtn = nil, *gPoiBtn = nil, *gSeedBtn = nil, *gAutoBtn = nil;
static PAKeepAlive *gKeep = nil;
static const NSTimeInterval kActionPace = 1.0;   // driver tick
static const NSTimeInterval kFeedPace    = 30.0; // one nectar to the squad, batch per pass
static const NSTimeInterval kHarvestPace = 60.0; // petal pick over the squad
static const NSTimeInterval kCollectPace = 15.0; // complete returned expeditions
static const NSTimeInterval kExpedPace   = 10.0; // one send-off per pass
static const NSTimeInterval kPlantPace  = 15.0;  // planting session check
static const NSTimeInterval kPoiPace    = 3.0;   // big-flower scan
static const NSTimeInterval kSeedPace   = 20.0;  // seedling plant/pluck
static const NSTimeInterval kMapPace    = 5.0;   // mapobjects.json refresh

static NSString * const kHarvestKey = @"pa_harvest";
static NSString * const kCollectKey = @"pa_collect";
static NSString * const kFeedKey    = @"pa_feed";
static NSString * const kExpedKey   = @"pa_expedition";
static NSString * const kPlantKey   = @"pa_plant";
static NSString * const kPoiKey     = @"pa_poi";
static NSString * const kSeedKey    = @"pa_seed";
static NSString * const kAutoKey    = @"pa_auto";      // 자동성장: every toggle at once

// Suppress camera focus whenever any automation toggle is active.
static void pkSyncFocus(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    gFocusSuppress = [d boolForKey:kHarvestKey] || [d boolForKey:kCollectKey] ||
                     [d boolForKey:kFeedKey]    || [d boolForKey:kExpedKey]   ||
                     [d boolForKey:kPlantKey]   || [d boolForKey:kPoiKey]     ||
                     [d boolForKey:kSeedKey];
}

@implementation PAOverlay

+ (void)toast:(NSString *)msg { /* on-screen toast removed — everything goes to pa.log */ }

+ (void)drag:(UIPanGestureRecognizer *)g {
    UIView *host = g.view.superview;
    CGPoint t = [g translationInView:host];
    CGPoint c = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    CGFloat hw = g.view.bounds.size.width / 2, hh = g.view.bounds.size.height / 2;
    c.x = MAX(hw, MIN(host.bounds.size.width  - hw, c.x));
    c.y = MAX(hh, MIN(host.bounds.size.height - hh, c.y));
    g.view.center = c;
    [g setTranslation:CGPointZero inView:host];
}

+ (void)styleBtn:(UIButton *)b on:(BOOL)on base:(NSString *)base {
    b.backgroundColor = on ? [[UIColor systemGreenColor] colorWithAlphaComponent:0.9]
                           : [[UIColor systemGrayColor] colorWithAlphaComponent:0.85];
    [b setTitle:[NSString stringWithFormat:@"%@ %@", on ? @"☑" : @"☐", base] forState:UIControlStateNormal];
}

// The single driver for all enabled passes. Called from BOTH a foreground NSTimer
// and the background location callback (which keeps firing while the app is alive
// in the background), so automation continues when the phone is locked. A time
// throttle keeps the two sources from double-firing.
+ (void)runDue {
    static NSTimeInterval last = 0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - last < kActionPace - 0.3) return;
    last = now;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // Each pass on its own cadence. The old driver ran every pass every second,
    // which meant dozens of RPCs a second while feeding — a request pattern no
    // real player produces. These paces keep the pipeline moving at a rate
    // indistinguishable from a busy human.
    static NSTimeInterval lastFeed = 0, lastHarvest = 0, lastCollect = 0, lastExped = 0;
    static NSTimeInterval lastPlant = 0, lastPoi = 0, lastSeed = 0, lastMap = 0, lastBg = 0;
    BOOL bg = [UIApplication sharedApplication].applicationState != UIApplicationStateActive;
    if (bg && now - lastBg >= 60.0) { lastBg = now; PALOG(@"[bg] alive in background — passes keep running"); }
    if ([d boolForKey:kFeedKey]    && now - lastFeed    >= kFeedPace)    { lastFeed    = now; PALOG(@"[feed] %@", feedPass()); }
    if ([d boolForKey:kHarvestKey] && now - lastHarvest >= kHarvestPace) { lastHarvest = now; PALOG(@"[harvest] %@", harvestPass()); }
    if ([d boolForKey:kCollectKey] && now - lastCollect >= kCollectPace) { lastCollect = now; PALOG(@"[collect] %@", collectPass()); }
    if ([d boolForKey:kExpedKey]   && now - lastExped   >= kExpedPace)   { lastExped   = now; PALOG(@"[탐험] %@", expeditionPass()); }
    // 자동성장 passes.
    if ([d boolForKey:kPlantKey] && now - lastPlant >= kPlantPace) { lastPlant = now; PALOG(@"[심기] %@", plantPass()); }
    if ([d boolForKey:kPoiKey]   && now - lastPoi   >= kPoiPace)   { lastPoi   = now; PALOG(@"[큰꽃] %@", bigFlowerPass()); }
    if ([d boolForKey:kSeedKey]  && now - lastSeed  >= kSeedPace)  { lastSeed  = now; PALOG(@"[모종] %@", seedPass()); }
    if (gMapObj && now - lastMap >= kMapPace) { lastMap = now; mapDumpPass(); }
}

+ (void)syncAllButtons {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [self styleBtn:gFeedBtn    on:[d boolForKey:kFeedKey]    base:@"정수"];
    [self styleBtn:gHarvestBtn on:[d boolForKey:kHarvestKey] base:@"수확"];
    [self styleBtn:gCollectBtn on:[d boolForKey:kCollectKey] base:@"수집"];
    [self styleBtn:gExpedBtn   on:[d boolForKey:kExpedKey]   base:@"탐험"];
    [self styleBtn:gPlantBtn   on:[d boolForKey:kPlantKey]   base:@"심기"];
    [self styleBtn:gPoiBtn     on:[d boolForKey:kPoiKey]     base:@"큰꽃"];
    [self styleBtn:gSeedBtn    on:[d boolForKey:kSeedKey]    base:@"모종"];
    BOOL all = [d boolForKey:kFeedKey] && [d boolForKey:kHarvestKey] && [d boolForKey:kCollectKey] &&
               [d boolForKey:kExpedKey] && [d boolForKey:kPlantKey] && [d boolForKey:kPoiKey] && [d boolForKey:kSeedKey];
    [d setBool:all forKey:kAutoKey];
    [self styleBtn:gAutoBtn on:all base:@"자동성장"];
    pkSyncFocus();
}
+ (void)toggleKey:(NSString *)key {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:key] forKey:key];
    [self syncAllButtons];
}
+ (void)togglePlant { [self toggleKey:kPlantKey]; if ([[NSUserDefaults standardUserDefaults] boolForKey:kPlantKey]) PALOG(@"[심기] %@", plantPass()); }
+ (void)togglePoi   { [self toggleKey:kPoiKey];   if ([[NSUserDefaults standardUserDefaults] boolForKey:kPoiKey])   PALOG(@"[큰꽃] %@", bigFlowerPass()); }
+ (void)toggleSeed  { [self toggleKey:kSeedKey];  if ([[NSUserDefaults standardUserDefaults] boolForKey:kSeedKey])  PALOG(@"[모종] %@", seedPass()); }
// 자동성장: the whole pipeline on or off in one tap.
+ (void)toggleAuto {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL on = ![d boolForKey:kAutoKey];
    for (NSString *k in @[kFeedKey, kHarvestKey, kCollectKey, kExpedKey, kPlantKey, kPoiKey, kSeedKey]) [d setBool:on forKey:k];
    [self syncAllButtons];
    PALOG(@"[자동성장] %@", on ? @"ON — 정수/수확/수집/탐험/심기/큰꽃/모종 전부" : @"OFF");
    if (on) [PAOverlay runDue];
}

+ (void)toggleHarvest {
    BOOL on = ![[NSUserDefaults standardUserDefaults] boolForKey:kHarvestKey];
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kHarvestKey];
    [self styleBtn:gHarvestBtn on:on base:@"수확"];
    pkSyncFocus();
    if (on) PALOG(@"[harvest] %@", harvestPass());
}
+ (void)toggleCollect {
    BOOL on = ![[NSUserDefaults standardUserDefaults] boolForKey:kCollectKey];
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kCollectKey];
    [self styleBtn:gCollectBtn on:on base:@"수집"];
    pkSyncFocus();
    if (on) PALOG(@"[collect] %@", collectPass());
}
+ (void)toggleFeed {
    BOOL on = ![[NSUserDefaults standardUserDefaults] boolForKey:kFeedKey];
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kFeedKey];
    [self styleBtn:gFeedBtn on:on base:@"정수"];
    pkSyncFocus();
    if (on) PALOG(@"[feed] %@", feedPass());
}

+ (void)toggleExped {
    BOOL on = ![[NSUserDefaults standardUserDefaults] boolForKey:kExpedKey];
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kExpedKey];
    [self styleBtn:gExpedBtn on:on base:@"탐험"];
    pkSyncFocus();
    if (on) [PAOverlay runDue];     // via the throttle, so the next tick does not re-run it
}

+ (UIButton *)button:(NSString *)base y:(CGFloat)y sel:(SEL)sel key:(NSString *)key root:(UIView *)root width:(CGFloat)w {
    BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(w - 110, y, 96, 34);
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    b.layer.cornerRadius = 8; b.layer.zPosition = 100000;
    b.backgroundColor = on ? [[UIColor systemGreenColor] colorWithAlphaComponent:0.9]
                           : [[UIColor systemGrayColor] colorWithAlphaComponent:0.85];
    [b setTitle:[NSString stringWithFormat:@"%@ %@", on ? @"☑" : @"☐", base] forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [root addSubview:b];
    return b;
}

+ (void)ensure {
    if (gWin) return;
    NSArray *scenes = [UIApplication sharedApplication].connectedScenes.allObjects;
    UIWindowScene *scene = nil;
    for (UIScene *s in scenes)
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
    if (!scene)
        for (UIScene *s in scenes)
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;

    PAPassWindow *win = [[PAPassWindow alloc] initWithWindowScene:scene];
    win.frame = scene.coordinateSpace.bounds;
    win.windowLevel = (UIWindowLevel)1000000;
    win.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    win.rootViewController = vc;
    win.hidden = NO;
    gWin = win;
    UIView *root = vc.view;
    CGFloat w = win.bounds.size.width;

    gFeedBtn    = [self button:@"정수"   y:64  sel:@selector(toggleFeed)    key:kFeedKey    root:root width:w];
    gHarvestBtn = [self button:@"수확"   y:104 sel:@selector(toggleHarvest) key:kHarvestKey root:root width:w];
    gCollectBtn = [self button:@"수집"   y:144 sel:@selector(toggleCollect) key:kCollectKey root:root width:w];
    gExpedBtn   = [self button:@"탐험"   y:184 sel:@selector(toggleExped)   key:kExpedKey   root:root width:w];
    gPlantBtn   = [self button:@"심기"   y:224 sel:@selector(togglePlant)   key:kPlantKey   root:root width:w];
    gPoiBtn     = [self button:@"큰꽃"   y:264 sel:@selector(togglePoi)     key:kPoiKey     root:root width:w];
    gSeedBtn    = [self button:@"모종"   y:304 sel:@selector(toggleSeed)    key:kSeedKey    root:root width:w];
    gAutoBtn    = [self button:@"자동성장" y:352 sel:@selector(toggleAuto)  key:kAutoKey    root:root width:w];
    [self syncAllButtons];

    // Our own location feed — whatever CoreLocation (or the GPS Wander tweak
    // underneath it) reports is where the game believes we are; the big-flower
    // range check and seedling planting point use it.
    // Background too: the game declares the location background mode (its own
    // background planting relies on it), so a session with background updates
    // allowed keeps this process alive with the screen off, and every fix that
    // arrives — GPS Wander pushes one a second — drives runDue.
    gKeep = [PAKeepAlive new];
    gLoc = [CLLocationManager new];
    gLoc.delegate = gKeep;
    gLoc.desiredAccuracy = kCLLocationAccuracyBest;
    gLoc.distanceFilter = kCLDistanceFilterNone;
    gLoc.pausesLocationUpdatesAutomatically = NO;
    @try { gLoc.allowsBackgroundLocationUpdates = YES; }
    @catch (NSException *e) { PALOG(@"[keepalive] no background location: %@", e); }
    [gLoc startUpdatingLocation];
    PALOG(@"[keepalive] location session started (bg=%d)", (int)gLoc.allowsBackgroundLocationUpdates);

    // Foreground automation driver — runs the enabled passes every kActionPace.
    // (Background execution was intentionally dropped; the app suspends when it is
    // not in the foreground.)
    [NSTimer scheduledTimerWithTimeInterval:kActionPace repeats:YES
        block:^(NSTimer *t){ [PAOverlay runDue]; }];

    // Background driver: keep buttons on top, install hooks, run numbering, and
    // resume any toggles that were left on.
    PALOG(@"[ui] overlay ready");
    __block int hb = 0;
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *tm){
        for (UIButton *b in @[gFeedBtn, gHarvestBtn, gCollectBtn, gExpedBtn, gPlantBtn, gPoiBtn, gSeedBtn, gAutoBtn])
            if (b.superview) [b.superview bringSubviewToFront:b];
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
        pkInstallHooks();
        if (++hb % 5 == 0) {
            PALOG(@"[hb] rpc=%d mgr=%d inv=%d pikmin=%lu", gRpc!=NULL, gMgr!=NULL, gInv()!=NULL,
                  (unsigned long)pkAllPikmin().count);
        }
    }];
    // Numbering runs on its own slow cadence (idempotent).
    [NSTimer scheduledTimerWithTimeInterval:15.0 repeats:YES block:^(NSTimer *tm){
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) autoNumberPass();
    }];
    // Toggles that were on before relaunch keep running via the master timer above;
    // just restore the focus-suppress state to match.
    pkSyncFocus();
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kAutoKey])
        PALOG(@"[ui] 자동성장 OFF — 버튼으로 켜면 전 파이프라인 가동");
}
@end

static void *overlayEntry(void *unused) {
    for (int i = 0; i < 1200; i++) {
        __block BOOL done = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ [PAOverlay ensure]; done = (gWin != nil); });
        if (done) return NULL;
        usleep(250000);
    }
    return NULL;
}

%ctor {
    @autoreleasepool {
        pthread_t th; pthread_create(&th, NULL, overlayEntry, NULL); pthread_detach(th);
    }
}
