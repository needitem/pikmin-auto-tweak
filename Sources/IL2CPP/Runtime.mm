// The runtime bridge's core: the gate that keeps il2cpp untouched until the game is
// ready, cached class/method lookups, invoking managed methods, strings and
// objects, hooks and GC handles. The raw API is Il2cppApi's; looking inside classes
// is Reflection's.
#import "Runtime.h"
#import "Il2cppApi.h"
#import "Log.h"
#import <os/lock.h>
#import <mutex>
#import <string>
#import <unordered_map>

// ---------- readiness ----------
static volatile BOOL gArmed = NO;
void pkRuntimeArm(void) { gArmed = YES; }

BOOL pkRuntimeReady(void) {
    if (!gArmed) return NO;
    return pkIl2cppResolve();
}

// ---------- classes / methods (cached) ----------
static std::mutex gCacheMu;
static std::unordered_map<std::string, void *> gClassCache, gMethodCache;

// Lookups happen in tight loops with string literals, and the maps below are
// keyed by std::string — a heap allocation and a lock per call. These small
// direct-mapped tables are keyed by the ADDRESS of the name strings (callers
// pass literals) and checked by content, so a reused buffer can never alias a
// different name. A miss falls through to the maps.
struct ClassSlot  { const char *ns, *name; char *nsCopy, *nameCopy; void *cls; };
struct MethodSlot { void *cls; const char *name; char *nameCopy; int argc; void *method; };
static const size_t kFastSlots = 256;
static ClassSlot gClassFast[kFastSlots];
static MethodSlot gMethodFast[kFastSlots];
static os_unfair_lock gFastLock = OS_UNFAIR_LOCK_INIT;

static inline size_t slotOf(uintptr_t a, uintptr_t b, uintptr_t c) {
    uint64_t h = a * 0x9E3779B97F4A7C15ull;
    h ^= (b + 0x7F4A7C15ull) * 0xC2B2AE3D27D4EB4Full;
    h ^= c * 0x165667B19E3779F9ull;
    return (size_t)((h >> 29) & (kFastSlots - 1));
}

static void *classSlow(const char *ns, const char *name);
void *pkClass(const char *ns, const char *name) {
    if (!ns || !name) return NULL;
    size_t i = slotOf((uintptr_t)ns, (uintptr_t)name, 0);
    os_unfair_lock_lock(&gFastLock);
    ClassSlot &s = gClassFast[i];
    if (s.cls && s.ns == ns && s.name == name && !strcmp(s.nsCopy, ns) && !strcmp(s.nameCopy, name)) {
        void *c = s.cls;
        os_unfair_lock_unlock(&gFastLock);
        return c;
    }
    os_unfair_lock_unlock(&gFastLock);
    void *cls = classSlow(ns, name);
    if (!cls) return NULL;                       // not loaded yet: do not remember
    char *nsCopy = strdup(ns), *nameCopy = strdup(name);
    os_unfair_lock_lock(&gFastLock);
    ClassSlot &t = gClassFast[i];
    free(t.nsCopy); free(t.nameCopy);
    t = { ns, name, nsCopy, nameCopy, cls };
    os_unfair_lock_unlock(&gFastLock);
    return cls;
}

static void *classSlow(const char *ns, const char *name) {
    if (!f_domain_get || !ns || !name) return NULL;
    std::string key = std::string(ns) + "|" + name;
    {
        std::lock_guard<std::mutex> g(gCacheMu);
        auto it = gClassCache.find(key);
        if (it != gClassCache.end()) return it->second;
    }
    pkIl2cppAttachThread();
    void *dom = f_domain_get();
    if (!dom) return NULL;
    size_t n = 0; void **as = f_domain_get_assemblies(dom, &n);
    for (size_t i = 0; i < n; i++) {
        const void *im = f_assembly_get_image(as[i]);
        if (!im) continue;
        void *k = f_class_from_name(im, ns, name);
        if (k) {
            std::lock_guard<std::mutex> g(gCacheMu);
            gClassCache[key] = k;
            return k;
        }
    }
    return NULL;   // not cached: the class may simply not be loaded yet
}

void *pkClassOf(void *obj) { return obj ? f_object_get_class(obj) : NULL; }

static void *methodSlow(void *cls, const char *name, int argc);
void *pkMethod(void *cls, const char *name, int argc) {
    if (!cls || !name) return NULL;
    size_t i = slotOf((uintptr_t)cls, (uintptr_t)name, (uintptr_t)argc);
    os_unfair_lock_lock(&gFastLock);
    MethodSlot &s = gMethodFast[i];
    if (s.nameCopy && s.cls == cls && s.name == name && s.argc == argc && !strcmp(s.nameCopy, name)) {
        void *m = s.method;
        os_unfair_lock_unlock(&gFastLock);
        return m;
    }
    os_unfair_lock_unlock(&gFastLock);
    void *m = methodSlow(cls, name, argc);       // a NULL answer is remembered too, as before
    char *nameCopy = strdup(name);
    os_unfair_lock_lock(&gFastLock);
    MethodSlot &t = gMethodFast[i];
    free(t.nameCopy);
    t = { cls, name, nameCopy, argc, m };
    os_unfair_lock_unlock(&gFastLock);
    return m;
}

static void *methodSlow(void *cls, const char *name, int argc) {
    std::string key;
    key.append((const char *)&cls, sizeof(cls));
    key.append(name);
    key.push_back('/');
    key.push_back((char)('0' + argc));
    {
        std::lock_guard<std::mutex> g(gCacheMu);
        auto it = gMethodCache.find(key);
        if (it != gMethodCache.end()) return it->second;
    }
    void *m = f_class_get_method_from_name(cls, name, argc);
    std::lock_guard<std::mutex> g(gCacheMu);
    gMethodCache[key] = m;
    return m;
}

void *pkMethodOf(void *obj, const char *name, int argc) { return pkMethod(pkClassOf(obj), name, argc); }

// ---------- invocation ----------
static void logException(void *method, void *exc) {
    NSString *mname = @"?";
    if (f_method_get_name && method) mname = @(f_method_get_name(method) ?: "?");
    char buf[512] = {0};
    if (f_format_exception) f_format_exception(exc, buf, sizeof(buf) - 1);
    PKLOGC([@"exc." stringByAppendingString:mname],
           [NSString stringWithFormat:@"[il2cpp] %@ 예외: %s", mname, buf[0] ? buf : "(형식 불가)"]);
}

void *pkInvokeEx(void *method, void *obj, void **args, BOOL *ok) {
    if (ok) *ok = NO;
    if (!method) return NULL;
    pkIl2cppAttachThread();
    void *exc = NULL;
    void *r = f_runtime_invoke(method, obj, args, &exc);
    if (exc) { logException(method, exc); return NULL; }
    if (ok) *ok = YES;
    return r;
}
void *pkInvoke(void *method, void *obj, void **args) { return pkInvokeEx(method, obj, args, NULL); }
void *pkCall0(void *obj, const char *name) { return obj ? pkInvoke(pkMethodOf(obj, name, 0), obj, NULL) : NULL; }

// il2cpp boxes value-type returns; the payload sits right after the object header.
int  pkUnboxInt(void *boxed)  { return boxed ? *(int *)((char *)boxed + 0x10) : 0; }
BOOL pkUnboxBool(void *boxed) { return boxed ? *(unsigned char *)((char *)boxed + 0x10) != 0 : NO; }

// ---------- strings / objects ----------
// Il2CppString: length @0x10, UTF-16 chars @0x14.
NSString *pkStr(void *s) {
    if (!s) return nil;
    int len = *(int *)((char *)s + 0x10);
    if (len < 0 || len > 4096) return nil;
    return [NSString stringWithCharacters:(const unichar *)((char *)s + 0x14) length:(NSUInteger)len];
}
int pkStrCopy(void *s, unichar *out, int cap) {
    if (!s || !out) return 0;
    int len = *(int *)((char *)s + 0x10);
    if (len <= 0 || len > cap) return 0;
    memcpy(out, (char *)s + 0x14, (size_t)len * sizeof(unichar));
    return len;
}
void *pkNewString(NSString *s) { return s ? f_string_new(s.UTF8String) : NULL; }

void *pkNewObj(void *cls) {
    if (!cls) return NULL;
    void *o = f_object_new(cls);
    if (!o) return NULL;
    void *ctor = pkMethod(cls, ".ctor", 0);
    if (ctor) pkInvoke(ctor, o, NULL);
    return o;
}
void *pkNewProto(const char *name, void **outCls) {
    void *cls = pkClass("Ichigo.Proto", name);
    if (outCls) *outCls = cls;
    return pkNewObj(cls);
}

void pkWriteRef(void *obj, void **slot, void *value) {
    if (f_wbarrier_set_field) f_wbarrier_set_field(obj, slot, value);
    else *slot = value;
}

// ---------- hooks / GC ----------
BOOL pkHookMethod(void *cls, const char *method, int argc, void *hook, void **orig) {
    void *m = pkMethod(cls, method, argc);
    void *fp = m ? *(void **)m : NULL;              // MethodInfo.methodPointer
    if (!fp || !f_MSHookFunction) return NO;
    f_MSHookFunction(fp, hook, orig);
    return YES;
}

uint32_t pkGcPin(void *obj) { return (obj && f_gchandle_new) ? f_gchandle_new(obj, 0) : 0; }
void pkGcUnpin(uint32_t h) { if (h && f_gchandle_free) f_gchandle_free(h); }
