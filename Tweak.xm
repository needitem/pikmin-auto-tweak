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

// Same, but only when the text has actually changed (or three minutes have
// passed). Every pass prints a status line; repeating an unchanged one every
// few seconds is what took pa.log to three quarters of a megabyte in a single
// session, and those writes count against the app's background disk budget.
static void PKLOGC(NSString *key, NSString *msg) {
    static NSMutableDictionary *lastMsg = nil, *lastAt = nil;
    if (!lastMsg) { lastMsg = [NSMutableDictionary dictionary]; lastAt = [NSMutableDictionary dictionary]; }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ([lastMsg[key] isEqualToString:msg] && now - [lastAt[key] doubleValue] < 180.0) return;
    lastMsg[key] = msg; lastAt[key] = @(now);
    PALOG(@"%@", msg);
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
    PKLOGC([NSString stringWithFormat:@"feedRPC.%s", tag],
           ([NSString stringWithFormat:@"[feedRPC:%s] pikminCount=%d itemId='%@' numItems=%d", tag, pcnt, pkStr(itemId) ?: @"", numItems]));
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
    PKLOGC([NSString stringWithFormat:@"pickRPC.%s", tag],
           ([NSString stringWithFormat:@"[pickRPC:%s] pikminCount=%d", tag, pcnt]));
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
// Picking a nectar off the selector reel — the bar the user drags from — runs
// through HoneyBallObservableList.OnHoneyBallSelectedPreStageAsync, whose one
// argument is the HoneyBallData that was chosen. That is the selection
// itself, caught the moment it is made, without waiting for the user to
// actually feed anyone. (The choice is nowhere else: not the server prefs,
// not the 137 keys of the game's own preferences file.)
//
// HoneyBallData: EntryData @0x18 → HoneyBallEntryData.HoneyBallItem @0x10,
// a HoneyBallInventoryItem whose proto carries honeyFlowerKind_ and flowerKind_.
static void pkRememberSpecialFromItem(void *item);
// The selection itself. ExtractSelectionTracker is the game's holder for
// "the nectar currently picked" — a caching observable whose SetExtract runs
// every time the user chooses one off the reel, before anything is fed. Its
// Extract carries the colour (extractType @0x20) and the nectar type
// (honeyBallType @0x60 → HoneyBallTypeProto: honeyType_ @0x18,
// honeyFlowerKind_ @0x1C, flowerKind_ @0x20), which together name exactly
// one stack in the inventory.
static void *pkMethod(void *cls, const char *name, int argc);
static void *pkInvoke(void *method, void *obj, void **args);
static void pkPinFromExtract(void *extract);
static void pkReadExtract(void *ex, int *color, int *hkind, NSString **fkind);
static void *gExtractSel = NULL;                  // live ExtractSelectionTracker
static void (*orig_setextract)(void*, void*, void*);
static void hook_setextract(void *self, void *extract, void *mi) {
    if (self) gExtractSel = self;
    orig_setextract(self, extract, mi);
    if (extract) pkPinFromExtract(extract);
}
// Waiting for SetExtract is not enough: re-picking the nectar that is already
// selected is a no-op, so the call never comes and the choice stays invisible.
// Capturing the tracker itself lets the current selection be read outright —
// get_MostRecent is the value the game would hand to the next throw.
static void (*orig_estctor)(void*, void*, void*, void*);
static void hook_estctor(void *self, void *a, void *b, void *mi) {
    if (self && !gExtractSel) { gExtractSel = self; PALOG(@"[capture] ExtractSelectionTracker=%p (ctor)", self); }
    orig_estctor(self, a, b, mi);
}
static void pkPinFromCurrentSelection(void) {
    if (!gExtractSel || !resolveAPI()) return;
    void *m = pkMethod(f_object_get_class(gExtractSel), "get_MostRecent", 0);
    void *ex = m ? pkInvoke(m, gExtractSel, NULL) : NULL;
    if (!ex) {
        PKLOGC(@"sel.none", @"[feed] 게임에 선택된 정수 없음 — 보유량 기준 자동 선택");
        return;
    }
    int color = 0, hkind = 0; NSString *fkind = nil;
    pkReadExtract(ex, &color, &hkind, &fkind);
    PKLOGC(@"sel.cur", ([NSString stringWithFormat:@"[feed] 게임에서 선택 중: 색%d kind%d '%@'",
                         color, hkind, fkind ?: @""]));
    pkPinFromExtract(ex);
}
static void (*orig_hbselect)(void*, void*, void*);
static void hook_hbselect(void *self, void *honeyBallData, void *mi) {
    if (honeyBallData) {
        void *entry = *(void**)((char*)honeyBallData + 0x18);
        void *item  = entry ? *(void**)((char*)entry + 0x10) : NULL;
        if (item) pkRememberSpecialFromItem(item);
    }
    orig_hbselect(self, honeyBallData, mi);
}
static void pkRememberSpecial(void *itemIdStr);
static void *(*orig_schedfeed)(void*, void*, void*, void*);
static void *hook_schedfeed(void *self, void *pikId, void *itemId, void *mi) {
    if (self) gAction = self;
    PALOG(@"[schedFeed] pik='%@' item='%@'", pkStr(pikId) ?: @"", pkStr(itemId) ?: @"");
    pkRememberSpecial(itemId);
    return orig_schedfeed(self, pikId, itemId, mi);
}
// Manual harvest goes through the same PikminActionManager, so hooking it arms
// gAction too — the user harvests normally and the feed path becomes available.
// Zenject builds this one; hooking its constructor hands us the instance at
// startup instead of waiting for the user to feed or harvest by hand, which
// is why the game's own harvest path used to sit unused for a whole session.
static void (*orig_pamctor)(void*, void*);
static void hook_pamctor(void *self, void *mi) {
    if (self && !gAction) { gAction = self; PALOG(@"[capture] PikminActionManager=%p (ctor)", self); }
    orig_pamctor(self, mi);
}
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
    void *estCls = pkFindClass("Niantic.Ichigo.Game.Garden.Extracts", "ExtractSelectionTracker");
    void *mSetEx = estCls ? f_class_get_method_from_name(estCls, "SetExtract", 1) : NULL;
    if (mSetEx) { void *fp = *(void**)mSetEx; if (fp) f_MSHookFunction(fp, (void*)hook_setextract, (void**)&orig_setextract); }
    void *mEstC = estCls ? f_class_get_method_from_name(estCls, ".ctor", 2) : NULL;
    if (mEstC) { void *fp = *(void**)mEstC; if (fp) f_MSHookFunction(fp, (void*)hook_estctor, (void**)&orig_estctor); }
    PALOG(@"[hooks] estCls=%p SetExtract=%p ctor=%p", estCls, mSetEx, mEstC);
    void *hbCls = pkFindClass("Niantic.Ichigo.Game.Garden.Extracts.Scroll", "HoneyBallObservableList");
    void *mHbSel = hbCls ? f_class_get_method_from_name(hbCls, "OnHoneyBallSelectedPreStageAsync", 1) : NULL;
    if (mHbSel) { void *fp = *(void**)mHbSel; if (fp) f_MSHookFunction(fp, (void*)hook_hbselect, (void**)&orig_hbselect); }
    PALOG(@"[hooks] hbCls=%p 정수선택=%p", hbCls, mHbSel);
    void *mSchF = actCls ? f_class_get_method_from_name(actCls, "ScheduleFeedPikminAsync", 2) : NULL;
    if (mSchF) { void *fp = *(void**)mSchF; if (fp) f_MSHookFunction(fp, (void*)hook_schedfeed, (void**)&orig_schedfeed); }
    void *mPamC = actCls ? f_class_get_method_from_name(actCls, ".ctor", 0) : NULL;
    if (mPamC) { void *fp = *(void**)mPamC; if (fp) f_MSHookFunction(fp, (void*)hook_pamctor, (void**)&orig_pamctor); }
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
    PALOG(@"[hooks] fpcCls=%p mPI=%p momCls=%p mMU=%p actCls=%p ctor=%p", fpcCls, mPI, momCls, mMU, actCls, mPamC);
    PALOG(@"[hooks] edsCls=%p mEA=%p mEU=%p", edsCls, mEA, mEU);
    PALOG(@"[hooks] mFS=%p mFS2=%p mPS=%p mPS2=%p mSchF=%p mSchP=%p", mFS, mFS2, mPS, mPS2, mSchF, mSchP);
    installed = (mGP || mAU || mGK) != 0;
    PALOG(@"[hooks] rpcCls=%p mgrCls=%p mGP=%p mBA=%p mGF=%p mAU=%p mGK=%p focCls=%p mSF=%p installed=%d",
          rpcCls, mgrCls, mGP, mBA, mGF, mAU, mGK, focCls, mSF, installed);
}

// How long each pass actually takes. Without this, tuning the cadences is
// guesswork: a pass that costs 4 ms can run every second, one that costs 300 ms
// cannot. Reported by the heartbeat as total-ms/calls.
static NSMutableDictionary<NSString *, NSNumber *> *gPassMs = nil, *gPassN = nil;
static NSString *pkTime(NSString *name, NSString *(^body)(void)) {
    if (!gPassMs) { gPassMs = [NSMutableDictionary dictionary]; gPassN = [NSMutableDictionary dictionary]; }
    NSTimeInterval t0 = CACurrentMediaTime();
    NSString *r = body();
    double ms = (CACurrentMediaTime() - t0) * 1000.0;
    gPassMs[name] = @([gPassMs[name] doubleValue] + ms);
    gPassN[name]  = @([gPassN[name] intValue] + 1);
    return r;
}
static NSString *pkPassTimings(void) {
    if (!gPassN.count) return @"-";
    NSMutableArray *bits = [NSMutableArray array];
    for (NSString *k in [gPassN.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        int n = [gPassN[k] intValue];
        if (!n) continue;
        [bits addObject:[NSString stringWithFormat:@"%@ %.0f/%d", k, [gPassMs[k] doubleValue], n]];
    }
    [gPassMs removeAllObjects]; [gPassN removeAllObjects];
    return [bits componentsJoinedByString:@" "];
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
        // numFlowers_ @0x38 is the lifetime count of flowers this Pikmin has
        // bloomed, not what it is holding — using it as "has petals" sent a
        // harvest request for every Pikmin in the squad, every time, and the
        // server ignored the lot. What can be picked right now is
        // flowerStateFlowerCount_ @0x58, plus wiltedCount_ @0x5C once the
        // flower has wilted.
        int state = *(int*)((char*)proto + 0x48);       // PikminProto.flowerState_
        int nflw  = *(int*)((char*)proto + 0x38);       // numFlowers_ (lifetime)
        int cnt   = *(int*)((char*)proto + 0x58);       // flowerStateFlowerCount_
        int wilt  = *(int*)((char*)proto + 0x5C);       // wiltedCount_
        [out addObject:@{ @"id": [NSValue valueWithPointer:idStr],
                          @"state": @(state), @"nflw": @(nflw),
                          @"cnt": @(cnt), @"wilt": @(wilt) }];
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
        // Plain colour nectar grows any flower. Flower-specific nectar (a
        // flowerKind such as "canna") only takes while the Pikmin's head is
        // still a leaf or a bud — feed it to an open flower and the server
        // does nothing, which is what made it look useless. Both kinds are
        // returned now, tagged, and feedPass sends each where it works.
        int hkind = *(int*)((char*)proto + 0x20);          // honeyFlowerKind_
        // FlowerKind 5 is COMMON — the ordinary nectar, despite carrying a
        // kind. Only a named flower (rose, canna, …) is the special sort that
        // decides what a bud opens into.
        BOOL special = (fkind.length > 0) || (hkind != 0 && hkind != 5);
        int use = np;                                      // predicted count = what the user sees
        if (idStr && use > 0 && use < 100000 && pkNectarAllowed(type))
            [out addObject:@{ @"id": [NSValue valueWithPointer:idStr], @"balls": @(use),
                              @"type": @(type), @"special": @(special), @"hkind": @(hkind),
                              @"kindName": fkind ?: @"" }];
    }
    static int dumpN = 0;
    if (dumpN++ % 20 == 0)  // periodic histogram; rare, it is only a sanity check
        PALOG(@"[nectar] conf W%lld R%lld B%lld Y%lld H%lld | pred W%lld R%lld B%lld Y%lld H%lld",
              confByType[1],confByType[2],confByType[3],confByType[4],confByType[5],
              predByType[1],predByType[2],predByType[3],predByType[4],predByType[5]);
    return out;
}

// Match a fed itemId against the nectar we hold and pin its kind as the one
// to spend on buds. A plain colour nectar clears the pin instead, so handing
// out an ordinary one says "no particular flower".
// The chosen nectar, however we came by it: its item id pins the exact stack,
// so colour is included — two lisianthus stacks of different colours are
// different ids. A plain colour nectar clears the pin.
static void pkPinNectar(NSString *itemId, BOOL special, NSString *kindName, int hkind, int type, NSString *how) {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    if (!special) {
        if ([u stringForKey:@"pa_special"] || [u stringForKey:@"pa_special_id"]) {
            [u removeObjectForKey:@"pa_special"];
            [u removeObjectForKey:@"pa_special_id"];
            PALOG(@"[feed] 특수정수 지정 해제 — 일반 정수를 %@", how);
        }
        return;
    }
    NSString *kind = kindName.length ? kindName : [NSString stringWithFormat:@"kind%d", hkind];
    if ([[u stringForKey:@"pa_special_id"] isEqualToString:itemId]) return;
    [u setObject:kind forKey:@"pa_special"];
    [u setObject:itemId forKey:@"pa_special_id"];
    PALOG(@"[feed] 특수정수 지정: %@ (색%d, id=%@) — %@", kind, type, itemId, how);
}
static void pkRememberSpecialFromItem(void *item) {
    if (!item || !resolveAPI()) return;
    void *itCls = f_object_get_class(item);
    void *idStr = pkInvoke(pkMethod(itCls, "get_Id", 0), item, NULL);
    void *proto = pkInvoke(pkMethod(itCls, "get_Proto", 0), item, NULL);
    if (!idStr || !proto) return;
    int type  = *(int*)((char*)proto + 0x1C);          // honeyType_ (colour)
    int hkind = *(int*)((char*)proto + 0x20);          // honeyFlowerKind_
    NSString *fkind = pkStr(*(void**)((char*)proto + 0x28));
    BOOL special = (fkind.length > 0) || (hkind != 0 && hkind != 5);
    pkPinNectar(pkStr(idStr) ?: @"", special, fkind, hkind, type, @"선택함");
}
// Turn the chosen Extract into the inventory stack it refers to: same colour,
// same flower kind. That id is what feeding spends, so the colour the user
// picked is honoured — two lisianthus stacks of different colours are two
// different ids and only one of them is theirs.
// Read a chosen Extract. The flower it belongs to is on the Extract itself —
// flowerKind @0x28, a FlowerKind object carrying id ("lisianthus") @0x18 and
// the enum @0x20. honeyBallType @0x60 also has a kind but comes back empty
// for the reel's entries, which is why a red lisianthus first read as plain
// red nectar.
static void pkReadExtract(void *ex, int *color, int *hkind, NSString **fkind) {
    *color = *(int*)((char*)ex + 0x20);                // extractType (colour)
    void *fk = *(void**)((char*)ex + 0x28);            // FlowerKind
    if (fk) {
        *fkind = pkStr(*(void**)((char*)fk + 0x18));   // FlowerKind.id
        *hkind = *(int*)((char*)fk + 0x20);            // FlowerKind.kind
    }
    if (!(*fkind).length) {                            // fall back to the proto
        void *hbt = *(void**)((char*)ex + 0x60);
        if (hbt) {
            if (!*hkind) *hkind = *(int*)((char*)hbt + 0x1C);
            *fkind = pkStr(*(void**)((char*)hbt + 0x20));
        }
    }
}
static void pkPinFromExtract(void *extract) {
    if (!extract || !resolveAPI()) return;
    int color = 0, hkind = 0; NSString *fkind = nil;
    pkReadExtract(extract, &color, &hkind, &fkind);
    BOOL special = (fkind.length > 0) || (hkind != 0 && hkind != 5);
    if (!special) { pkPinNectar(@"", NO, nil, 0, color, @"골랐음"); return; }
    // Match on colour and the flower's name. The kind number is not comparable
    // across the two sides: the catalog's FlowerKind for lisianthus is 55,
    // while the inventory proto's honeyFlowerKind_ is a different encoding —
    // insisting they agree found nothing at all.
    NSArray *held = pkNectar();
    for (NSDictionary *d in held) {
        if ([d[@"type"] intValue] != color) continue;
        if (fkind.length && [d[@"kindName"] caseInsensitiveCompare:fkind] != NSOrderedSame) continue;
        if (!fkind.length && [d[@"hkind"] intValue] != hkind) continue;
        pkPinNectar(pkStr([d[@"id"] pointerValue]) ?: @"", YES, d[@"kindName"],
                    [d[@"hkind"] intValue], color, @"골랐음");
        return;
    }
    // Same flower, any colour, rather than give up entirely.
    for (NSDictionary *d in held) {
        if (!fkind.length || [d[@"kindName"] caseInsensitiveCompare:fkind] != NSOrderedSame) continue;
        pkPinNectar(pkStr([d[@"id"] pointerValue]) ?: @"", YES, d[@"kindName"],
                    [d[@"hkind"] intValue], [d[@"type"] intValue], @"골랐음(색 불일치)");
        return;
    }
    NSMutableArray *bits = [NSMutableArray array];
    for (NSDictionary *d in held)
        [bits addObject:[NSString stringWithFormat:@"색%@/k%@/'%@'x%@", d[@"type"], d[@"hkind"], d[@"kindName"], d[@"balls"]]];
    PKLOGC(@"sel.miss", ([NSString stringWithFormat:@"[feed] 고른 정수(색%d k%d '%@')를 보유목록에서 못 찾음. 보유: %@",
           color, hkind, fkind ?: @"", [bits componentsJoinedByString:@" "]]));
}
static void pkRememberSpecial(void *itemIdStr) {
    NSString *fed = pkStr(itemIdStr);
    if (!fed.length) return;
    for (NSDictionary *d in pkNectar()) {
        if (![pkStr([d[@"id"] pointerValue]) isEqualToString:fed]) continue;
        pkPinNectar(fed, [d[@"special"] boolValue], d[@"kindName"],
                    [d[@"hkind"] intValue], [d[@"type"] intValue], @"손으로 줌");
        return;
    }
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
    PKLOGC(@"number", ([NSString stringWithFormat:@"[number] total=%lu mismatches=%lu", (unsigned long)total, (unsigned long)todo.count]));
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

// A Pikmin's own head, PikminProto.flowerState_ @0x48 — not to be confused
// with the big-flower states of a map POI further down.
#define PK_PF_LEAF   1
#define PK_PF_BUD    3
#define PK_PF_FLOWER 4
#define PK_PF_PICK   5
#define PK_PF_WILTED 6

// ---------- feature: harvest flowers (all owned pikmin) ----------
static NSString *harvestPass(void) {
    if (!gMgr || !gRpc) return @"게임/서버 준비 대기";
    // Only Pikmin whose petals have actually fallen — wiltedCount_ above zero,
    // or the explicit FLOWER_READY_TO_PICK state. Sending the whole squad in
    // one request, most of them with flowers still growing, got the entire
    // batch ignored: 45 ids went out every minute and not one petal arrived.
    NSMutableArray *ids = [NSMutableArray array];
    NSUInteger squadN = 0, growing = 0;
    long long pickable = 0;
    for (NSDictionary *p in pkSquad()) {
        squadN++;
        int st = [p[@"state"] intValue], wilt = [p[@"wilt"] intValue];
        if (wilt > 0 || st == PK_PF_PICK) { [ids addObject:p[@"id"]]; pickable += wilt; }
        else growing++;
    }
    if (!squadN) return @"🌸 대열에 피크민 없음";
    if (!ids.count) return [NSString stringWithFormat:@"🌸 딸 꽃잎 없음 (자라는 중 %lu)", (unsigned long)growing];

    // The game's own path when we have it — it batches and keeps the client's
    // prediction bookkeeping straight.
    if (gAction) {
        void *m = pkMethod(f_object_get_class(gAction), "SchedulePickPikminFlowerBatchedRequest", 1);
        if (m) {
            for (NSValue *v in ids) { void *pid = [v pointerValue]; void *a[1] = { pid }; pkInvoke(m, gAction, a); }
            return [NSString stringWithFormat:@"🌸 수확(게임경로) %lu마리 / 꽃잎 %lld", (unsigned long)ids.count, pickable];
        }
    }
    // Otherwise the plain RPC — the variant the game's own batched harvest
    // awaits — five ids at a time, as feeding does.
    int sent = 0;
    for (NSUInteger i = 0; i < ids.count; i += 5) {
        NSRange r = NSMakeRange(i, MIN((NSUInteger)5, ids.count - i));
        void *cls = NULL;
        void *req = pkNewReq("PickPikminFlowersRequestProto", &cls);
        if (!req) break;
        for (NSValue *v in [ids subarrayWithRange:r]) {
            void *idStr = [v pointerValue];
            if (idStr) pkAddPikminId(req, cls, idStr);
        }
        if (pkSendRpc("SendPickPikminFlowersRpcAsync", req)) sent += (int)r.length;
    }
    return sent ? [NSString stringWithFormat:@"🌸 수확 %d마리 / 꽃잎 %lld (자라는 중 %lu)", sent, pickable, (unsigned long)growing]
                : @"🌸 수확 전송 실패";
}

// ---------- feature: 수집 — take what the Pikmin are carrying ----------
//
// Pikmin come home holding things: fruit and seedlings they carried, gifts,
// postcards. Each is a PikminTask in the inventory and each is claimed with
// CompletePikminTask — this is the game's 수집 button.
//
// PikminTaskProto.TaskOneofCase @0x50: 1 Carry, 6 Expedition, 8 Gift,
// 9 PoiChallenge. startTimeMs_ @0x18, finishTimeMs_ @0x20.
//
// An earlier cut narrowed this to expeditions the ExpeditionDataStore marked
// Returned, which dropped Carry and Gift tasks entirely — the very things a
// Pikmin is holding — and collection stopped. The task list is the right
// source: everything claimable is in it.
#define PK_TASK_CARRY       1
#define PK_TASK_EXPEDITION  6
#define PK_TASK_GIFT        8
#define PK_TASK_POICHALLENGE 9
static void *pkItemProto(void *item);
static NSArray *pkExpeditions(void);
static int pkIntProp(void *obj, const char *name);
#define PK_EXP_RETURNED 4                          // ExpeditionState.Returned
static NSMutableDictionary<NSString *, NSNumber *> *gCollectSent = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gCollectTries = nil;
static NSString *collectPass(void) {
    void *inv = gInv();
    if (!inv || !gRpc) return @"인벤토리/서버 준비 대기";
    if (!gCollectSent)  gCollectSent  = [NSMutableDictionary dictionary];
    if (!gCollectTries) gCollectTries = [NSMutableDictionary dictionary];
    void *list = pkInvoke(pkMethod(f_object_get_class(inv), "GetPikminTaskList", 0), inv, NULL);
    if (!list) return @"태스크 목록 없음";
    int size = *(int*)((char*)list + 0x18);            // List<T>._size
    void *arr = *(void**)((char*)list + 0x10);         // List<T>._items
    if (!arr || size <= 0 || size > 100000) return @"수집할 것 없음";
    char *adata = (char*)arr + 0x20;

    // An expedition is only claimable once the game's own state machine says
    // Returned. Its finish time passing is not enough — the Pikmin still have
    // to walk home, and the server refuses a completion until they have
    // (measured: 7 of 7 expedition completions refused on the finish-time
    // rule alone, while carried items went through). Collect the task ids the
    // store marks Returned and require expeditions to be among them.
    NSMutableSet<NSString *> *returned = [NSMutableSet set];
    for (NSValue *ev in pkExpeditions()) {
        void *d = [ev pointerValue];
        if (pkIntProp(d, "get_State") != PK_EXP_RETURNED) continue;
        void *ei = *(void**)((char*)d + 0x78);
        void *eid = ei ? pkInvoke(pkMethod(f_object_get_class(ei), "get_Id", 0), ei, NULL) : NULL;
        NSString *s = pkStr(eid);
        if (s.length) [returned addObject:s];
    }

    void *tCls = pkFindClass("Ichigo.Proto", "CompletePikminTaskRequestProto");
    long long nowMs = (long long)([NSDate date].timeIntervalSince1970 * 1000.0);
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    int sent = 0, running = 0, idle = 0, ready = 0;
    NSCountedSet *kinds = [NSCountedSet set];

    for (int i = 0; i < size; i++) {
        void *item = *(void**)(adata + (size_t)i * 8);
        if (!item) continue;
        void *idStr = pkInvoke(pkMethod(f_object_get_class(item), "get_Id", 0), item, NULL);
        void *proto = pkItemProto(item);
        if (!idStr || !proto) continue;
        int kase       = *(int*)((char*)proto + 0x50);
        long long stMs = *(long long*)((char*)proto + 0x18);
        long long finMs = *(long long*)((char*)proto + 0x20);
        [kinds addObject:@(kase)];

        NSString *tid = pkStr(idStr) ?: @"";
        if (kase == PK_TASK_EXPEDITION) {
            // Sent or not, an expedition is the 탐험 pass's business until the
            // game says the Pikmin are home.
            if (stMs == 0) { idle++; continue; }
            if (![returned containsObject:tid]) { running++; continue; }
        } else if (finMs > nowMs) {
            running++; continue;             // still being carried home
        }
        ready++;

        NSNumber *when = gCollectSent[tid];
        int tries = [gCollectTries[tid] intValue];
        // A task the server keeps refusing waits longer each time, up to 10 min.
        NSTimeInterval wait = MIN(30.0 * (tries > 0 ? (1 << MIN(tries, 5)) : 1), 600.0);
        if (when && now - when.doubleValue < wait) continue;

        void *req = tCls ? f_object_new(tCls) : NULL;
        if (!req) continue;
        void *ctor = pkMethod(tCls, ".ctor", 0);
        if (ctor) pkInvoke(ctor, req, NULL);
        *(void**)((char*)req + 0x18) = idStr;          // pikminTaskId_
        if (pkSendRpc("SendCompletePikminTaskRpcForResultAsync", req)) {
            sent++;
            gCollectSent[tid] = @(now);
            gCollectTries[tid] = @(tries + 1);
            PALOG(@"[collect] 수집 요청 종류%d task=%@%@", kase, tid,
                  tries ? [NSString stringWithFormat:@" (%d번째)", tries + 1] : @"");
        }
        if (sent >= 5) break;                          // a handful per pass
    }
    // Tasks that have gone away were collected; stop remembering them.
    if (gCollectSent.count > 200) { [gCollectSent removeAllObjects]; [gCollectTries removeAllObjects]; }

    NSMutableArray *cen = [NSMutableArray array];
    for (NSNumber *k in [kinds.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *name = k.intValue == PK_TASK_CARRY ? @"운반" :
                         k.intValue == PK_TASK_EXPEDITION ? @"탐험" :
                         k.intValue == PK_TASK_GIFT ? @"선물" :
                         k.intValue == PK_TASK_POICHALLENGE ? @"버섯" :
                         [NSString stringWithFormat:@"종류%@", k];
        [cen addObject:[NSString stringWithFormat:@"%@ %lu", name, (unsigned long)[kinds countForObject:k]]];
    }
    return [NSString stringWithFormat:@"📦 수집 요청 %d건 / 수령가능 %d, 진행중 %d, 미출발 %d [%@]",
            sent, ready, running, idle, [cen componentsJoinedByString:@", "]];
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
// PK_TASK_EXPEDITION is defined with the other task kinds above.
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
// The roster and the candidate list are the two expensive scans in here: each
// walks 250 Pikmin making two il2cpp calls apiece, and the candidate pass asks
// the game twice per Pikmin which way round its troop test takes arguments.
// That was roughly a thousand runtime invocations every ten seconds, all to
// answer a question whose answer barely changes. Both are cached briefly.
static NSArray *gCandCache = nil;
static NSTimeInterval gCandAt = 0;
static NSArray *pkExpeditionCandidatesUncachedList(void);
static NSArray *pkExpeditionCandidates(void) {
    NSTimeInterval now = CACurrentMediaTime();
    if (gCandCache && now - gCandAt < 20.0) return gCandCache;
    gCandCache = (NSArray *)(id)pkExpeditionCandidatesUncachedList();
    gCandAt = now;
    return gCandCache;
}
static NSArray *pkExpeditionCandidatesUncachedList(void) {
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
        PKLOGC(@"exp.pool", ([NSString stringWithFormat:@"[탐험] 후보 %lu마리 (부대원 포함 %d[%@ pi=%d ip=%d ent=%d], 부대유보 %d, 부대 %d, 최소 %d)",
              (unsigned long)out.count, poolInTroop, troopKey ?: @"ent", nPI, nIP, nEnt,
              held, troopTotal, minTroop]));
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
        PKLOGC(@"exp.census", ([NSString stringWithFormat:@"[탐험] 스토어 %lu건 / 탐험 %d건 / 미출발 %d건",
              (unsigned long)exps.count, nExp, nIdle]));
    }
    NSArray *cands = pkExpeditionCandidates();
    if (!cands.count) return @"보낼 피크민 없음";

    // Several send-offs per pass. One per pass meant an expedition every ten
    // seconds at best, half a minute in the background, so a full board took
    // minutes to clear. Pikmin already committed this pass are held back so
    // two expeditions never claim the same ones.
    NSMutableSet<NSValue *> *committed = [NSMutableSet set];
    const int kExpPerPass = 4;
    int launched = 0, lastParty = 0;
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
            if ([committed containsObject:c[@"id"]]) continue;
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
            PKLOGC(@"exp.weak", ([NSString stringWithFormat:@"[탐험] 힘 부족 — 후보 %lu, 뽑음 %lu, 최대 %d",
                  (unsigned long)cands.count, (unsigned long)picked.count, maxN]));
            continue;
        }
        // Now that a party is assigned, the game's own veto is meaningful: out of
        // range, inventory full, feature locked, still not strong enough, …
        void *why = pkInvoke(mWhy, d, NULL);
        if (why) {
            pkAssignPikmins(d, @[]);
                PKLOGC(@"exp.skip", ([NSString stringWithFormat:@"[탐험] 건너뜀 — %@", pkStr(why) ?: @"불가"]));
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
        [committed addObjectsFromArray:picked];
        gCandAt = 0;                            // the roster just changed
        lastParty = (int)picked.count;
        if (++launched >= kExpPerPass) break;
    }
    if (launched)
        return [NSString stringWithFormat:@"🚀 탐험 %d건 출발 (마지막 %d마리, 후보 %lu)",
                launched, lastParty, (unsigned long)cands.count];
    return seen ? [NSString stringWithFormat:@"보낼 수 있는 탐험 없음 (미출발 %d건)", seen]
                : @"대기 중인 탐험 없음";
}

// ---------- feature: auto-feed nectar ----------
// Each pass feeds up to kFeedPerTick Pikmin one nectar each, cycling through the
// nectar kinds we hold, until no nectar is left. Conservative batch size keeps
// the request rate ordinary and lets the log show nectar draining pass by pass.
// Feed the squad, matching the nectar to what each Pikmin's head is doing.
//
// PikminProto.flowerState_ @0x48: 1 LEAF, 3 BUD, 4 FLOWER,
// 5 FLOWER_READY_TO_PICK, 6 WILTED. A leaf or a bud has not decided which
// flower it will open into, and that is the only window in which
// flower-specific ("special") nectar does anything — spend it there. An open
// flower takes plain colour nectar to add petals. One already ready to pick
// is the harvest pass's business, not ours.
//
// Ids go five to a request, the shape the game's own feed uses, so the whole
// squad is served in a handful of calls instead of one Pikmin every few
// seconds. Feeding 39 Pikmin used to take five minutes of passes.
static NSString *feedPass(void) {
    if (!gMgr || !gRpc) return @"게임/서버 준비 대기";
    pkPinFromCurrentSelection();          // whatever is picked right now
    NSArray *nectar = pkNectar();
    NSMutableArray *plain = [NSMutableArray array], *special = [NSMutableArray array];
    long long totPlain = 0, totSpecial = 0;
    for (NSDictionary *d in nectar) {
        if ([d[@"special"] boolValue]) { [special addObject:d]; totSpecial += [d[@"balls"] longLongValue]; }
        else                           { [plain   addObject:d]; totPlain   += [d[@"balls"] longLongValue]; }
    }
    if (!totPlain && !totSpecial) return @"🍯 정수 없음";
    NSSortDescriptor *most = [NSSortDescriptor sortDescriptorWithKey:@"balls" ascending:NO];
    [plain sortUsingDescriptors:@[most]];
    [special sortUsingDescriptors:@[most]];
    // Which special nectar to spend. The game keeps the hotbar choice in the
    // UI only — it is in neither the server prefs nor a stored key — so the
    // kind we hold most of is the default, and pa_special (a flowerKind name
    // or a honeyFlowerKind number) pins it to the one the user wants.
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    NSString *wantId = [u stringForKey:@"pa_special_id"];
    NSString *want   = [u stringForKey:@"pa_special"];
    // The exact stack the user picked wins — that carries the colour too —
    // and its kind is the fallback once that stack runs out.
    for (NSDictionary *d in [special copy]) {
        BOOL hit = wantId.length && [pkStr([d[@"id"] pointerValue]) isEqualToString:wantId];
        if (!hit && want.length && !wantId.length)
            hit = [d[@"kindName"] caseInsensitiveCompare:want] == NSOrderedSame ||
                  [[d[@"hkind"] stringValue] isEqualToString:want];
        if (hit) { [special removeObject:d]; [special insertObject:d atIndex:0]; break; }
    }
    // What is actually on hand, so the right one can be named.
    if (special.count) {
        NSMutableArray *bits = [NSMutableArray array];
        for (NSDictionary *d in special)
            [bits addObject:[NSString stringWithFormat:@"%@ %@",
                             [d[@"kindName"] length] ? d[@"kindName"] : [NSString stringWithFormat:@"kind%@", d[@"hkind"]],
                             d[@"balls"]]];
        PKLOGC(@"feed.special", ([NSString stringWithFormat:@"[feed] 특수정수 보유: %@%@",
               [bits componentsJoinedByString:@", "],
               want.length ? [NSString stringWithFormat:@" (지정: %@)", want] : @" (지정 없음 — 많은 것부터)"]));
    }

    NSArray *squad = pkSquad();
    if (!squad.count) return @"🍯 대열에 피크민 없음 (배치/출격 필요)";
    // What the squad's heads are actually doing. Feeding and harvesting both
    // depend on it, and guessing was getting us nowhere: only
    // FLOWER_READY_TO_PICK can be picked, and a flower already at its full
    // petal count takes no more nectar.
    {
        int byState[8] = {0}; long long petals = 0;
        for (NSDictionary *p in squad) {
            int st = [p[@"state"] intValue];
            if (st >= 0 && st < 8) byState[st]++;
            petals += [p[@"cnt"] intValue] + [p[@"wilt"] intValue];
        }
        PKLOGC(@"feed.census", ([NSString stringWithFormat:
            @"[feed] 대열 %lu: 잎%d 봉오리%d 꽃%d 수확가능%d 시듦%d 기타%d / 지금 딸 수 있는 꽃잎 %lld",
            (unsigned long)squad.count, byState[PK_PF_LEAF], byState[PK_PF_BUD], byState[PK_PF_FLOWER],
            byState[PK_PF_PICK], byState[PK_PF_WILTED], byState[0] + byState[2] + byState[7], petals]));
    }
    NSMutableArray *budIds = [NSMutableArray array], *flowerIds = [NSMutableArray array];
    for (NSDictionary *p in squad) {
        int st = [p[@"state"] intValue];
        if (st == PK_PF_PICK || st == PK_PF_WILTED) continue;   // pick these first
        if (st == PK_PF_LEAF || st == PK_PF_BUD) [budIds addObject:p[@"id"]];
        else [flowerIds addObject:p[@"id"]];
    }

    // Five ids per request, as the game does.
    int (^feedGroup)(NSArray *, NSDictionary *) = ^int(NSArray *ids, NSDictionary *kind) {
        if (!ids.count || !kind) return 0;
        void *nid = [kind[@"id"] pointerValue];
        int budget = [kind[@"balls"] intValue];
        int done = 0;
        for (NSUInteger i = 0; i < ids.count && done < budget; i += 5) {
            NSRange r = NSMakeRange(i, MIN((NSUInteger)5, ids.count - i));
            NSArray *chunk = [ids subarrayWithRange:r];
            if (pkFeedBatch(chunk, nid, 1)) done += (int)chunk.count;
        }
        return done;
    };

    int fedBud = feedGroup(budIds, special.firstObject ?: plain.firstObject);
    int fedFlower = feedGroup(flowerIds, plain.firstObject);
    NSDictionary *sp = special.firstObject;
    return [NSString stringWithFormat:@"🍯 봉오리/잎 %d마리%@ · 꽃 %d마리(일반) / 일반 %lld 특수 %lld",
            fedBud,
            sp ? [NSString stringWithFormat:@"(특수 %@)", [sp[@"kindName"] length] ? sp[@"kindName"] : [NSString stringWithFormat:@"kind%@", sp[@"hkind"]]]
               : @"(일반)",
            fedFlower, totPlain, totSpecial];
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
// How the location feed is behaving. If the app is suspended these stop
// moving, which is the difference between "throttled" and "asleep" — the only
// way to tell why the app stopped working with the screen off.
static unsigned long gLocCount = 0;
static NSTimeInterval gLocLast = 0;
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
// One scan, shared. The big-flower pass and the dump both walk the manager's
// whole dictionary building a dictionary per object; doing it twice within a
// second or two of each other was pure waste.
static NSArray *gMapCache = nil;
static NSTimeInterval gMapAt = 0;
static NSArray *pkMapObjectsUncached(void);
static NSArray *pkMapObjects(void) {
    NSTimeInterval now = CACurrentMediaTime();
    if (gMapCache && now - gMapAt < 4.0) return gMapCache;
    gMapCache = pkMapObjectsUncached();
    gMapAt = now;
    return gMapCache;
}
static NSArray *pkMapObjectsUncached(void) {
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

// Hand GPS Wander the map objects it routes by. Only the kinds it can use are
// written — big flowers and mushrooms — and only when the set has actually
// changed. The first cut wrote all ~580 objects (79 KB) every five seconds to
// two files, about a gigabyte a day of writes inside an app iOS already had a
// diskwrites report against; the walk needs a couple of kilobytes a minute.
static void mapDumpPass(void) {
    NSArray *objs = pkMapObjects();
    if (!objs) return;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *o in objs) {
        int kind = [o[@"kind"] intValue];
        if (kind != PK_MO_POIFLOWER && kind != PK_MO_MUSHROOM) continue;
        [rows addObject:@{ @"id": o[@"id"], @"kind": o[@"kind"], @"lat": o[@"lat"], @"lng": o[@"lng"],
                           @"state": o[@"state"], @"color": o[@"color"], @"bloom": o[@"bloom"],
                           @"visited": o[@"visited"] }];
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingSortedKeys error:nil];
    if (!body) return;
    // Position moves constantly, so it must not count as a change on its own;
    // compare the objects alone and rewrite at most once a minute otherwise.
    static NSUInteger lastHash = 0;
    static NSTimeInterval lastWrite = 0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSUInteger h = body.hash;
    if (h == lastHash && now - lastWrite < 60.0) return;
    lastHash = h; lastWrite = now;

    NSDictionary *doc = @{ @"t": @(now),
                           @"lat": @(gLastLoc ? gLastLoc.coordinate.latitude : 0),
                           @"lng": @(gLastLoc ? gLastLoc.coordinate.longitude : 0),
                           @"objs": rows };
    NSData *json = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
    if (!json) return;
    // One copy, where GPS Wander looks first; the sandbox may refuse it, and
    // only then is the in-container path worth writing.
    static int sharedState = -1;
    NSError *e = nil;
    BOOL ok = [json writeToFile:@"/var/jb/var/mobile/Library/GPSWander/mapobjects.json"
                        options:NSDataWritingAtomic error:&e];
    if (!ok)
        [json writeToFile:[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                           stringByAppendingPathComponent:@"mapobjects.json"] atomically:YES];
    if ((int)ok != sharedState) {
        sharedState = ok;
        PALOG(@"[map] %lu개 기록, 공유 경로 %@%@", (unsigned long)rows.count, ok ? @"성공" : @"거부",
              ok ? @"" : [NSString stringWithFormat:@" — %@", e.localizedDescription]);
    }
}

// ---------- feature: 로스터 덤프 (버섯 전투 구성용 보유 피크민 현황) ----------
// Walks the full owned roster (pkAllPikmin) and reads the battle-relevant proto
// fields — colour (pikminType_@0x18 -> type_@0x18), flower stage (flowerState_@0x48),
// friendship hearts (friendship_@0xB0 -> numHearts_@0x1C), starred (@0x98), status
// (@0xD0), lifetime steps (@0x40). Writes both a machine JSON and a human summary to
// the shared GPSWander dir, at most once a minute unless the roster actually changed.
static NSString *pkColorName(int c) {
    switch (c) { case 1: return @"빨강"; case 2: return @"파랑"; case 3: return @"노랑";
        case 4: return @"하양"; case 5: return @"보라"; case 6: return @"바위"; case 7: return @"날개"; case 8: return @"얼음"; }
    return @"미상";
}
static NSString *pkFlowerName(int s) {
    switch (s) { case 1: return @"잎"; case 3: return @"봉우리"; case 4: return @"꽃";
        case 5: return @"수확대기"; case 6: return @"시듦"; }
    return @"?";
}
static NSString *pkStatusName(int s) {
    switch (s) { case 1: return @"대기"; case 2: return @"작업중"; case 32: return @"동행"; }
    return @"?";
}
static void rosterDumpPass(void) {
    NSArray *all = pkAllPikmin();
    if (!all) return;
    NSMutableArray *rows = [NSMutableArray array];
    // Histograms: colour, colour×flowerState, status.
    NSCountedSet *byColor = [NSCountedSet set];
    NSMutableDictionary *flowered = [NSMutableDictionary dictionary]; // colour -> flower/bud/leaf counts
    NSCountedSet *byStatus = [NSCountedSet set];
    int starredCnt = 0, decoCnt = 0;
    for (NSDictionary *p in all) {
        void *proto = [p[@"proto"] pointerValue];
        if (!proto) continue;
        int color = 0, asset = 0, category = 0;
        void *pt = *(void**)((char*)proto + 0x18);          // pikminType_
        if (pt) { color = *(int*)((char*)pt + 0x18);        // type_
                  category = *(int*)((char*)pt + 0x1C);     // categoryId_
                  asset = *(int*)((char*)pt + 0x20); }      // fullAssetId_ (>=2 = 코스튬)
        int fstate = *(int*)((char*)proto + 0x48);          // flowerState_
        int status = [p[@"status"] intValue];
        BOOL starred = [p[@"starred"] boolValue];
        float hearts = 0; int fpt = 0;
        void *fr = *(void**)((char*)proto + 0xB0);          // friendship_
        if (fr) { hearts = *(float*)((char*)fr + 0x1C); fpt = *(int*)((char*)fr + 0x18); }
        long long steps = *(long long*)((char*)proto + 0x40);
        NSString *name = pkStr(*(void**)((char*)proto + 0x30));
        [rows addObject:@{ @"name": name ?: @"", @"color": @(color), @"colorName": pkColorName(color),
                           @"flower": @(fstate), @"flowerName": pkFlowerName(fstate),
                           @"status": @(status), @"statusName": pkStatusName(status),
                           @"hearts": @(hearts), @"fpt": @(fpt),
                           @"asset": @(asset), @"category": @(category),
                           @"deco": @(asset >= 2),
                           @"starred": @(starred), @"steps": @(steps) }];
        [byColor addObject:pkColorName(color)];
        [byStatus addObject:pkStatusName(status)];
        if (starred) starredCnt++;
        if (asset >= 2) decoCnt++;
        NSString *ck = pkColorName(color);
        NSMutableDictionary *fc = flowered[ck];
        if (!fc) { fc = [@{ @"꽃":@0, @"봉우리":@0, @"잎":@0, @"기타":@0 } mutableCopy]; flowered[ck] = fc; }
        NSString *fk = fstate == 4 ? @"꽃" : fstate == 3 ? @"봉우리" : fstate == 1 ? @"잎" : @"기타";
        fc[fk] = @([fc[fk] intValue] + 1);
    }
    // Only rewrite when the roster meaningfully changed (position/steps aside).
    NSData *sig = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingSortedKeys error:nil];
    static NSUInteger lastHash = 0; static NSTimeInterval lastWrite = 0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSUInteger h = sig.hash;
    if (h == lastHash && now - lastWrite < 60.0) return;
    lastHash = h; lastWrite = now;

    NSDictionary *doc = @{ @"t": @(now), @"total": @(rows.count), @"starred": @(starredCnt),
                           @"pikmin": rows };
    NSData *json = [NSJSONSerialization dataWithJSONObject:doc options:NSJSONWritingPrettyPrinted error:nil];
    if (json) {
        if (![json writeToFile:@"/var/jb/var/mobile/Library/GPSWander/roster.json" options:NSDataWritingAtomic error:nil])
            [json writeToFile:[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"roster.json"] atomically:YES];
    }
    // Human summary.
    NSMutableString *txt = [NSMutableString string];
    [txt appendFormat:@"=== 보유 피크민 %lu마리 (즐겨찾기 %d) ===\n", (unsigned long)rows.count, starredCnt];
    [txt appendString:@"[색상별]\n"];
    for (NSString *c in @[@"빨강",@"파랑",@"노랑",@"하양",@"보라",@"바위",@"날개",@"얼음",@"미상"]) {
        NSUInteger n = [byColor countForObject:c];
        if (!n) continue;
        NSDictionary *fc = flowered[c];
        [txt appendFormat:@"  %@ %lu마리  (꽃 %@ / 봉우리 %@ / 잎 %@)\n", c, (unsigned long)n,
             fc[@"꽃"]?:@0, fc[@"봉우리"]?:@0, fc[@"잎"]?:@0];
    }
    [txt appendString:@"[상태별]\n"];
    for (NSString *s in @[@"대기",@"작업중",@"동행"]) {
        NSUInteger n = [byStatus countForObject:s];
        if (n) [txt appendFormat:@"  %@ %lu마리\n", s, (unsigned long)n];
    }
    [txt appendFormat:@"[데코] 코스튬 착용 %d마리 (방출 제외 권장)\n", decoCnt];
    if (![txt writeToFile:@"/var/jb/var/mobile/Library/GPSWander/roster.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil])
        [txt writeToFile:[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"roster.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    PALOG(@"[로스터] %lu마리 기록", (unsigned long)rows.count);
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
// The server judges the range against the location the game last reported to
// it, not the one we are standing on this instant, so asking from 99 m out
// mostly failed. Ask only from comfortably inside, and ask again soon — the
// walk is routed past the flower, so a closer approach is coming.
static const double kPoiSendM  = 65.0;
static const NSTimeInterval kPoiRetry = 45.0;
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
        if (d > kPoiSendM) continue;                  // wait until we are closer
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
    return [NSString stringWithFormat:@"🌼 큰꽃 %d / 만개 %d / 사정권(≤%.0fm) %d / 요청(≤%.0fm) %d / 채집됨 %lu",
            nFlower, nBloom, kPoiRangeM, nNear, kPoiSendM, sent, (unsigned long)claimed];
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
    __block NSMutableString *pdbg = [NSMutableString string];
    __block int nPlanters = 0;
    pkEachList(pkInvList("GetPlanterList"), ^(void *planter) {
        void *proto = pkItemProto(planter);
        if (!proto) return;
        nPlanters++;
        [pdbg appendFormat:@"P%d[", nPlanters];
        pkEachRepeated(*(void**)((char*)proto + 0x20), ^(void *slot) {
            nSlots++;
            NSString *sid = pkStr(*(void**)((char*)slot + 0x18));
            int remaining = *(int*)((char*)slot + 0x20), idx = *(int*)((char*)slot + 0x24), type = *(int*)((char*)slot + 0x28);
            [pdbg appendFormat:@"{i%d t%d r%d %@}", idx, type, remaining, sid.length ? @"점유" : @"빈"];
            if (sid.length) return;                              // occupied
            if (type == 1 && remaining <= 0) return;             // used-up disposable slot
            [freeSlots addObject:@(idx)];
        });
        [pdbg appendString:@"] "];
    });
    PKLOGC(@"seed.planters", ([NSString stringWithFormat:@"[모종] 화분%d 슬롯%d 빈%lu | %@",
          nPlanters, nSlots, (unsigned long)freeSlots.count, pdbg]));
    // Fill every free planter slot each pass. Planting is reliable now, so the
    // old "one per pass + 5-minute backoff" only starved the pluck→drain cycle
    // (leaving dozens of seedlings unplanted, which in turn kept expeditions
    // blocked on the seedling cap). The per-seed gSeedSent guard below still
    // stops the same seed being re-sent before the server answers.
    if (freeSlots.count && waiting.count && gLastLoc) {
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
            if (pkSendRpc("SendSetPikminSeedRpcAsync", req)) {
                gSeedSent[d[@"id"]] = @(now);
                PALOG(@"[모종] 심기 id=%@ req=%@ point=(%.6f,%.6f)", d[@"id"], d[@"req"], blat, blng);
                set++;
            }
            // no break: keep filling until every free slot has a seed
        }
    }
    return [NSString stringWithFormat:@"🌰 모종 %d (화분 %d, 익음 %lu, 대기 %lu) / 빈칸 %lu / 뽑기 %d 심기 %d",
            nSeeds, nPlanted, (unsigned long)ripe.count, (unsigned long)waiting.count,
            (unsigned long)freeSlots.count, pulled, set];
}

// ---------- feature: 부대 채우기 (동행 자동 편성) ----------
// Fill the active troop up to its max by a 4-tier priority (데코 우선, 성장 여지 순):
//   1) 데코·하트≤4  2) 일반·하트≤4  3) 데코·하트≥4  4) 일반·나머지 — see pkTier below.
// Decor Pikmin ARE now placed in the walking troop (tiers 1/3). The troop is
// the subset that walks with you, gains friendship, is fed and fights; its cap is
// PikminUtils.GetPikminInTroopCountMax (level-based). Members are moved in with
// ArrangePikminTroopRequestProto.moveToTroop (a MoveToTroopProto{pikminId} each).
static NSMutableDictionary<NSString *, NSNumber *> *gTroopSent = nil;
static const NSTimeInterval kTroopCooldown = 90.0;  // don't re-move the same Pikmin within this — the arrange RPC is async, so the local in-troop read lags a pass or two
static NSString *troopFillPass(void) {
    if (!gRpc || !gInv() || !resolveAPI()) return @"서버 대기";
    if (!gTroopSent) gTroopSent = [NSMutableDictionary dictionary];
    void *inv = gInv();
    void *utilCls = pkFindClass("Niantic.Ichigo.Game.Pikmins", "PikminUtils");
    void *mMax = pkMethod(utilCls, "GetPikminInTroopCountMax", 1);
    void *mCnt = pkMethod(utilCls, "GetPikminInTroopCount", 1);
    void *mInTroop = pkMethod(utilCls, "IsPikminInTroop", 2);
    if (!mMax || !mCnt) return @"부대 API 없음";
    int troopMax = 0, troopCnt = 0;
    { void *a[1] = { inv }; void *r = pkInvoke(mMax, NULL, a); if (r) troopMax = *(int*)((char*)r + 0x10); }
    { void *a[1] = { inv }; void *r = pkInvoke(mCnt, NULL, a); if (r) troopCnt = *(int*)((char*)r + 0x10); }
    if (troopMax <= 0) return @"부대 최대치 0";
    // No early return when full: we always recompute the ideal top-N and swap, so
    // a full troop still gets weaker/decor members replaced by better ones.

    NSArray *all = pkAllPikmin();
    if (!all.count) return @"로스터 대기";
    // Resolve IsPikminInTroop's ambiguous arg order the same way the expedition
    // pass does: try both, keep the tally that matches GetPikminInTroopCount.
    NSMutableArray *pool = [NSMutableArray array];
    int nPI = 0, nIP = 0, nEnt = 0;
    for (NSDictionary *d in all) {
        void *proto = [d[@"proto"] pointerValue];
        if (!proto) continue;
        int st = [d[@"status"] intValue];
        BOOL pi = NO, ip = NO;
        if (mInTroop) {
            void *a1[2] = { proto, inv }; void *r1 = pkInvoke(mInTroop, NULL, a1);
            pi = r1 && *(unsigned char*)((char*)r1 + 0x10) != 0;
            void *a2[2] = { inv, proto }; void *r2 = pkInvoke(mInTroop, NULL, a2);
            ip = r2 && *(unsigned char*)((char*)r2 + 0x10) != 0;
        }
        if (pi) nPI++;  if (ip) nIP++;  if (st == PK_STATUS_ENTOURAGE) nEnt++;
        void *pt = *(void**)((char*)proto + 0x18);
        int asset = pt ? *(int*)((char*)pt + 0x20) : 0;
        float hearts = 0; void *fr = *(void**)((char*)proto + 0xB0);
        if (fr) hearts = *(float*)((char*)fr + 0x1C);
        void *idp = *(void**)((char*)proto + 0x28);
        [pool addObject:@{ @"idp": idp ? [NSValue valueWithPointer:idp] : [NSNull null],
                           @"id": pkStr(idp) ?: @"", @"st": @(st), @"asset": @(asset),
                           @"hearts": @(hearts), @"pi": @(pi), @"ip": @(ip) }];
    }
    NSString *tk = @"pi";
    if (abs(nIP - troopCnt) < abs(nPI - troopCnt)) tk = @"ip";
    int tkCnt = [tk isEqualToString:@"pi"] ? nPI : nIP;
    BOOL useEnt = (troopCnt > 0 && tkCnt == 0 && nEnt > 0);

    // Desired troop = the top `troopMax` NON-decor, non-busy Pikmin by friendship.
    // Rather than only topping up the shortfall, we recompute the ideal set every
    // pass and SWAP: move out any current member not in it, move in any missing
    // one. That way weaker/decor members already in the troop get replaced by
    // better ones instead of lingering.
    NSMutableArray *elig = [NSMutableArray array];
    for (NSDictionary *d in pool) {
        if ([d[@"idp"] isKindOfClass:[NSNull class]]) continue;
        if ([d[@"st"] intValue] == PK_STATUS_TASK) continue;  // busy on a task — cannot move
        [elig addObject:d];                                    // 데코 포함 — 우선순위로 처리
    }
    // 재배치 우선순위 티어(낮을수록 먼저): asset≥2=데코,
    //   hearts=numHearts_ 0~8 (0~4=빨강하트 4칸, 4~8=노랑하트 4칸/만렙8). 4.0=빨강최대=경계.
    //   1) 데코 · 하트 ≤4   2) 일반 · 하트 ≤4   3) 데코 · 하트 ≥4   4) 일반 · 나머지(하트 ≥3 포함)
    // 성장 여지 큰(하트 낮은=빨강 단계) 데코를 최우선으로 부대에 유지.
    int (^pkTier)(NSDictionary *) = ^int(NSDictionary *d) {
        BOOL deco = [d[@"asset"] intValue] >= 2;
        float h = [d[@"hearts"] floatValue];
        if (deco  && h <= 4.0f) return 1;
        if (!deco && h <= 4.0f) return 2;
        if (deco  && h >= 4.0f) return 3;
        return 4;                                              // 일반 · 하트 >4
    };
    [elig sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        int ta = pkTier(a), tb = pkTier(b);
        if (ta != tb) return ta < tb ? NSOrderedAscending : NSOrderedDescending;  // 낮은 티어 먼저
        return [a[@"hearts"] compare:b[@"hearts"]];            // 같은 티어: 하트 적은 순(성장 우선)
    }];
    NSMutableSet<NSString *> *wantIds = [NSMutableSet set];
    NSMutableArray *want = [NSMutableArray array];
    for (NSDictionary *d in elig) {
        if ((int)want.count >= troopMax) break;
        [want addObject:d]; [wantIds addObject:d[@"id"]];
    }

    BOOL (^inTroop)(NSDictionary *) = ^BOOL(NSDictionary *d) {
        return useEnt ? ([d[@"st"] intValue] == PK_STATUS_ENTOURAGE) : [d[tk] boolValue];
    };
    // move OUT: currently in troop but not wanted (decor, low-friendship, surplus)
    NSTimeInterval nowT = [NSDate date].timeIntervalSince1970;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in pool) {
        if ([d[@"idp"] isKindOfClass:[NSNull class]]) continue;
        if ([d[@"st"] intValue] == PK_STATUS_TASK) continue;  // can't move a busy one
        if (inTroop(d) && ![wantIds containsObject:d[@"id"]]) {
            NSNumber *when = gTroopSent[d[@"id"]];
            if (when && nowT - when.doubleValue < kTroopCooldown) continue;
            [out addObject:d];
        }
    }
    // move IN: wanted but not currently in troop, and not moved very recently
    // (the arrange RPC is async so the in-troop read lags — without this guard the
    // same Pikmin is re-sent every pass, which is what made +3/-1 repeat forever).
    NSMutableArray *in = [NSMutableArray array];
    for (NSDictionary *d in want) {
        if (inTroop(d)) continue;
        NSNumber *when = gTroopSent[d[@"id"]];
        if (when && nowT - when.doubleValue < kTroopCooldown) continue;
        [in addObject:d];
    }

    if (!out.count && !in.count)
        return [NSString stringWithFormat:@"부대 %d/%d — 이미 최적(데코 우선 4티어)", troopCnt, troopMax];

    void *reqCls = NULL;
    void *req = pkNewReq("ArrangePikminTroopRequestProto", &reqCls);
    if (!req) return @"요청 생성 실패";
    void *fTroop = pkInvoke(pkMethod(reqCls, "get_MoveToTroop", 0), req, NULL);
    void *fEnt   = pkInvoke(pkMethod(reqCls, "get_MoveToEntourage", 0), req, NULL);
    if (!fTroop || !fEnt) return @"move 필드 없음";
    void *mAddT = pkMethod(f_object_get_class(fTroop), "Add", 1);
    void *mAddE = pkMethod(f_object_get_class(fEnt), "Add", 1);
    void *mtCls = pkNestedClass(reqCls, "MoveToTroopProto");
    void *meCls = pkNestedClass(reqCls, "MoveToEntourageProto");
    void *mSetT = mtCls ? pkMethod(mtCls, "set_PikminId", 1) : NULL;
    void *mSetE = meCls ? pkMethod(meCls, "set_PikminId", 1) : NULL;
    if (!mAddT || !mAddE || !mSetT || !mSetE) return @"Move proto 준비 실패";

    int nIn = 0, nOut = 0;
    for (NSDictionary *d in in) {
        void *item = pkNewObj(mtCls); if (!item) continue;
        void *sa[1] = { [d[@"idp"] pointerValue] }; pkInvoke(mSetT, item, sa);
        void *aa[1] = { item }; pkInvoke(mAddT, fTroop, aa); nIn++;
        gTroopSent[d[@"id"]] = @(nowT);
    }
    for (NSDictionary *d in out) {
        void *item = pkNewObj(meCls); if (!item) continue;
        void *sa[1] = { [d[@"idp"] pointerValue] }; pkInvoke(mSetE, item, sa);
        void *aa[1] = { item }; pkInvoke(mAddE, fEnt, aa); nOut++;
        gTroopSent[d[@"id"]] = @(nowT);
    }
    if (!nIn && !nOut) return [NSString stringWithFormat:@"부대 %d/%d — 변경 없음", troopCnt, troopMax];
    pkSendRpc("SendArrangePikminTroopRpcForResultAsync", req);
    PALOG(@"[부대] 교체: 넣기 +%d / 빼기 -%d (목표 %lu/%d, 순서=%@)",
          nIn, nOut, (unsigned long)want.count, troopMax, useEnt ? @"ent" : tk);
    return [NSString stringWithFormat:@"🚶 부대 교체 +%d/-%d (목표 %lu/%d)", nIn, nOut, (unsigned long)want.count, troopMax];
}

// ---------- keep the game from cooking the phone while it plays itself ----------
//
// The automation's own cost is negligible — a measured 50 ms of CPU per minute
// across every pass. The heat comes from Unity rendering a map nobody is
// watching at the platform frame rate. UnityEngine.Application.targetFrameRate
// caps that, and vSyncCount must be 0 or the cap is ignored.
//
// Applied only while 자동성장 is on, restored to the platform default (-1) when
// it goes off, and re-asserted periodically because the game resets it across
// scene changes.
static int pkWantedFps(void) {
    NSInteger v = [[NSUserDefaults standardUserDefaults] integerForKey:@"pa_fps"];
    if (v <= 0) v = 20;                       // enough to stay usable if glanced at
    return (int)MIN(MAX(v, 5), 60);
}
static void pkApplyFrameRate(BOOL automating) {
    if (!resolveAPI()) return;
    static void *appCls = NULL, *qsCls = NULL;
    if (!appCls) appCls = pkFindClass("UnityEngine", "Application");
    if (!qsCls)  qsCls  = pkFindClass("UnityEngine", "QualitySettings");
    if (!appCls) return;
    void *mGet = pkMethod(appCls, "get_targetFrameRate", 0);
    void *mSet = pkMethod(appCls, "set_targetFrameRate", 1);
    if (!mGet || !mSet) return;

    int want = automating ? pkWantedFps() : -1;
    void *r = pkInvoke(mGet, NULL, NULL);
    int cur = r ? *(int*)((char*)r + 0x10) : 0;
    if (cur == want) return;

    if (automating && qsCls) {                // a cap with vSync on does nothing
        void *mVs = pkMethod(qsCls, "set_vSyncCount", 1);
        int zero = 0; void *va[1] = { &zero };
        if (mVs) pkInvoke(mVs, NULL, va);
    }
    void *a[1] = { &want };
    pkInvoke(mSet, NULL, a);
    PALOG(@"[fps] 목표 프레임 %d → %d", cur, want);
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
    if (locs.lastObject) {
        gLastLoc = locs.lastObject;
        gLocCount++;
        gLocLast = [NSDate date].timeIntervalSince1970;
    }
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
static UIButton *gTroopBtn = nil;
static UIButton *gFab = nil;          // the one handle that is always visible
static UIView   *gPanel = nil;        // the toggles, shown only when it is tapped
static PAKeepAlive *gKeep = nil;
static const NSTimeInterval kActionPace = 1.0;   // driver tick
static const NSTimeInterval kFeedPace    = 15.0; // whole squad, five ids per request
static const NSTimeInterval kHarvestPace = 8.0;  // only the Pikmin holding petals
static const NSTimeInterval kCollectPace = 10.0; // complete returned expeditions
static const NSTimeInterval kExpedPace   = 8.0;  // up to four send-offs per pass
static const NSTimeInterval kPlantPace  = 30.0;  // planting session check
static const NSTimeInterval kPoiPace    = 6.0;   // big-flower scan
static const NSTimeInterval kSeedPace   = 10.0;  // seedling plant/pluck — snappier pluck/replant
static const NSTimeInterval kMapPace    = 30.0;  // mapobjects.json refresh
static const NSTimeInterval kTroopPace  = 30.0;  // fill the walking troop
static const NSTimeInterval kRosterPace = 30.0;  // roster.json/roster.txt refresh

static NSString * const kHarvestKey = @"pa_harvest";
static NSString * const kCollectKey = @"pa_collect";
static NSString * const kFeedKey    = @"pa_feed";
static NSString * const kExpedKey   = @"pa_expedition";
static NSString * const kPlantKey   = @"pa_plant";
static NSString * const kPoiKey     = @"pa_poi";
static NSString * const kSeedKey    = @"pa_seed";
static NSString * const kTroopKey   = @"pa_troop";     // 부대: fill the walking troop
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
    if (g.view == gFab && gPanel) {
        // Keep the panel under the handle, and on screen.
        CGFloat x = MIN(host.bounds.size.width - gPanel.bounds.size.width - 8, MAX(8.0, c.x - gPanel.bounds.size.width + 22));
        CGFloat y = MIN(host.bounds.size.height - gPanel.bounds.size.height - 8, c.y + 28);
        gPanel.frame = CGRectMake(x, y, gPanel.bounds.size.width, gPanel.bounds.size.height);
    }
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
// A pass result that has not changed says nothing new. Repeating it every few
// seconds is how pa.log reached three quarters of a megabyte in one session,
// and the writes count against the app's background disk budget.
+ (void)logPass:(NSString *)tag msg:(NSString *)msg {
    PKLOGC([@"pass." stringByAppendingString:tag], ([NSString stringWithFormat:@"[%@] %@", tag, msg]));
}

+ (void)runDue {
    static NSTimeInterval last = 0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    // Backgrounded, everything runs a third as often. Sustained work with the
    // screen off is what gets a background app suspended and then terminated,
    // and nothing here needs second-by-second attention.
    BOOL background = [UIApplication sharedApplication].applicationState != UIApplicationStateActive;
    double pace = background ? 1.0 : 1.0;  // full speed even backgrounded: screen-off = Unity draws nothing = no render heat, and passes are ~50ms/min. App stays alive on the location callback.
    if (now - last < kActionPace * pace - 0.3) return;
    last = now;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // Each pass on its own cadence. The old driver ran every pass every second,
    // which meant dozens of RPCs a second while feeding — a request pattern no
    // real player produces. These paces keep the pipeline moving at a rate
    // indistinguishable from a busy human.
    static NSTimeInterval lastFeed = 0, lastHarvest = 0, lastCollect = 0, lastExped = 0;
    static NSTimeInterval lastPlant = 0, lastPoi = 0, lastSeed = 0, lastMap = 0, lastBg = 0, lastRoster = 0, lastTroop = 0;
    if (background && now - lastBg >= 300.0) { lastBg = now; PALOG(@"[bg] 백그라운드에서 계속 동작 중"); }
    // Only worth doing in the foreground — a backgrounded Unity draws nothing.
    static NSTimeInterval lastFps = 0;
    if (!background && now - lastFps >= 20.0) {
        lastFps = now;
        pkApplyFrameRate([d boolForKey:kAutoKey] || [d boolForKey:kFeedKey] || [d boolForKey:kExpedKey]);
    }
    if ([d boolForKey:kFeedKey]    && now - lastFeed    >= kFeedPace * pace)    { lastFeed    = now; [self logPass:@"feed"    msg:pkTime(@"feed", ^{ return feedPass(); })]; }
    if ([d boolForKey:kHarvestKey] && now - lastHarvest >= kHarvestPace * pace) { lastHarvest = now; [self logPass:@"harvest" msg:pkTime(@"harvest", ^{ return harvestPass(); })]; }
    if ([d boolForKey:kCollectKey] && now - lastCollect >= kCollectPace * pace) { lastCollect = now; [self logPass:@"collect" msg:pkTime(@"collect", ^{ return collectPass(); })]; }
    if ([d boolForKey:kExpedKey]   && now - lastExped   >= kExpedPace * pace)   { lastExped   = now; [self logPass:@"탐험"  msg:pkTime(@"탐험", ^{ return expeditionPass(); })]; }
    if ([d boolForKey:kPlantKey]   && now - lastPlant   >= kPlantPace * pace)   { lastPlant   = now; [self logPass:@"심기"  msg:pkTime(@"심기", ^{ return plantPass(); })]; }
    if ([d boolForKey:kPoiKey]     && now - lastPoi     >= kPoiPace * pace)     { lastPoi     = now; [self logPass:@"큰꽃"  msg:pkTime(@"큰꽃", ^{ return bigFlowerPass(); })]; }
    if ([d boolForKey:kSeedKey]    && now - lastSeed    >= kSeedPace * pace)    { lastSeed    = now; [self logPass:@"모종"  msg:pkTime(@"모종", ^{ return seedPass(); })]; }
    if ([d boolForKey:kTroopKey]   && now - lastTroop   >= kTroopPace * pace)   { lastTroop   = now; [self logPass:@"부대"  msg:pkTime(@"부대", ^{ return troopFillPass(); })]; }
    if (gMapObj && now - lastMap >= kMapPace * pace) { lastMap = now; pkTime(@"map", ^{ mapDumpPass(); return @""; }); }
    if (gMgr && now - lastRoster >= kRosterPace * pace) { lastRoster = now; pkTime(@"로스터", ^{ rosterDumpPass(); return @""; }); }
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
    [self styleBtn:gTroopBtn   on:[d boolForKey:kTroopKey]   base:@"부대"];
    BOOL all = [d boolForKey:kFeedKey] && [d boolForKey:kHarvestKey] && [d boolForKey:kCollectKey] &&
               [d boolForKey:kExpedKey] && [d boolForKey:kPlantKey] && [d boolForKey:kPoiKey] && [d boolForKey:kSeedKey] && [d boolForKey:kTroopKey];
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
+ (void)toggleTroop { [self toggleKey:kTroopKey]; if ([[NSUserDefaults standardUserDefaults] boolForKey:kTroopKey]) PALOG(@"[부대] %@", troopFillPass()); }
// 자동성장: the whole pipeline on or off in one tap.
+ (void)toggleAuto {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL on = ![d boolForKey:kAutoKey];
    for (NSString *k in @[kFeedKey, kHarvestKey, kCollectKey, kExpedKey, kPlantKey, kPoiKey, kSeedKey, kTroopKey]) [d setBool:on forKey:k];
    [self syncAllButtons];
    PALOG(@"[자동성장] %@", on ? @"ON — 정수/수확/수집/탐험/심기/큰꽃/모종/부대 전부" : @"OFF");
    pkApplyFrameRate(on);
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

// Eight buttons pinned down the side covered the map. Now a single small
// handle sits out of the way and everything lives in a panel it opens.
+ (UIButton *)button:(NSString *)base y:(CGFloat)y sel:(SEL)sel key:(NSString *)key root:(UIView *)root width:(CGFloat)w {
    BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(8, y, w - 16, 36);
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    b.layer.cornerRadius = 9;
    b.backgroundColor = on ? [[UIColor systemGreenColor] colorWithAlphaComponent:0.9]
                           : [[UIColor systemGrayColor] colorWithAlphaComponent:0.85];
    [b setTitle:[NSString stringWithFormat:@"%@ %@", on ? @"☑" : @"☐", base] forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:b];
    return b;
}

+ (void)togglePanel {
    gPanel.hidden = !gPanel.hidden;
    if (!gPanel.hidden) {
        [self syncAllButtons];
        [gPanel.superview bringSubviewToFront:gPanel];
    }
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

    // The handle: small, draggable, always on top, and the only thing on
    // screen until it is tapped.
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeSystem];
    fab.frame = CGRectMake(w - 56, 70, 44, 44);
    fab.layer.cornerRadius = 22;
    fab.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    fab.titleLabel.font = [UIFont systemFontOfSize:20];
    [fab setTitle:@"🌱" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    fab.layer.zPosition = 100001;
    [root addSubview:fab];
    gFab = fab;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(w - 190, 120, 178, 8 + 9 * 40)];
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    panel.layer.cornerRadius = 12;
    panel.layer.zPosition = 100000;
    panel.hidden = YES;
    [root addSubview:panel];
    gPanel = panel;
    CGFloat pw = panel.bounds.size.width;

    gAutoBtn    = [self button:@"자동성장" y:8   sel:@selector(toggleAuto)    key:kAutoKey    root:panel width:pw];
    gFeedBtn    = [self button:@"정수"    y:48  sel:@selector(toggleFeed)    key:kFeedKey    root:panel width:pw];
    gHarvestBtn = [self button:@"수확"    y:88  sel:@selector(toggleHarvest) key:kHarvestKey root:panel width:pw];
    gCollectBtn = [self button:@"수집"    y:128 sel:@selector(toggleCollect) key:kCollectKey root:panel width:pw];
    gExpedBtn   = [self button:@"탐험"    y:168 sel:@selector(toggleExped)   key:kExpedKey   root:panel width:pw];
    gPlantBtn   = [self button:@"심기"    y:208 sel:@selector(togglePlant)   key:kPlantKey   root:panel width:pw];
    gPoiBtn     = [self button:@"큰꽃"    y:248 sel:@selector(togglePoi)     key:kPoiKey     root:panel width:pw];
    gSeedBtn    = [self button:@"모종"    y:288 sel:@selector(toggleSeed)    key:kSeedKey    root:panel width:pw];
    gTroopBtn   = [self button:@"부대"    y:328 sel:@selector(toggleTroop)   key:kTroopKey   root:panel width:pw];
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
    // The position every consumer sees is substituted anyway, so asking the
    // GPS chip for its best fix only heats the phone. Hundred-metre accuracy
    // is served from wifi and cell and still counts as an active location
    // session, which is what keeps us alive in the background.
    gLoc.desiredAccuracy = kCLLocationAccuracyHundredMeters;
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
        if (gFab.superview) [gFab.superview bringSubviewToFront:gFab];
        if (gPanel && !gPanel.hidden && gPanel.superview) [gPanel.superview bringSubviewToFront:gPanel];
        pkInstallHooks();
        if (++hb % 60 == 0) {
            // %s takes a C string in the system encoding, which mangles Korean;
            // NSString arguments go through %@ intact.
            NSArray *therm = @[ @"정상", @"주의", @"높음", @"위험" ];
            NSProcessInfoThermalState ts = NSProcessInfo.processInfo.thermalState;
            UIDevice.currentDevice.batteryMonitoringEnabled = YES;
            PALOG(@"[hb] rpc=%d mgr=%d inv=%d pikmin=%lu | 위치 %lu회, 마지막 %.0f초 전 | 발열 %@, 배터리 %.0f%% | 패스 %@",
                  gRpc!=NULL, gMgr!=NULL, gInv()!=NULL, (unsigned long)pkAllPikmin().count,
                  gLocCount, gLocLast ? [NSDate date].timeIntervalSince1970 - gLocLast : -1,
                  therm[MIN((int)ts, 3)], UIDevice.currentDevice.batteryLevel * 100.0,
                  pkPassTimings());
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
