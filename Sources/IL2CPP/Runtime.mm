#import "Runtime.h"
#import "Log.h"
#import <dlfcn.h>
#import <os/lock.h>
#import <mutex>
#import <string>
#import <unordered_map>

// ---------- il2cpp C API ----------
typedef void*        (*t_domain_get)(void);
typedef void*        (*t_thread_attach)(void*);
typedef void**       (*t_domain_get_assemblies)(void*, size_t*);
typedef const void*  (*t_assembly_get_image)(const void*);
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
typedef void         (*t_gchandle_free)(uint32_t);
typedef void*        (*t_class_get_nested_types)(void*, void**);
typedef const char*  (*t_class_get_name)(void*);
typedef void*        (*t_class_get_methods)(void*, void**);
typedef const char*  (*t_method_get_name)(const void*);
typedef uint32_t     (*t_method_get_param_count)(const void*);
typedef const void*  (*t_method_get_param)(const void*, uint32_t);
typedef char*        (*t_type_get_name)(const void*);
typedef void         (*t_free)(void*);
typedef void         (*t_format_exception)(const void*, char*, int);
typedef void         (*t_wbarrier_set_field)(void*, void**, void*);
typedef void*        (*t_class_get_fields)(void*, void**);
typedef const void*  (*t_field_get_type)(void*);
typedef int          (*t_type_get_type)(const void*);
typedef int          (*t_field_get_flags)(void*);
typedef void*        (*t_class_from_type)(const void*);
typedef bool         (*t_class_is_valuetype)(const void*);
typedef void*        (*t_class_get_parent)(void*);
typedef const char*  (*t_field_get_name)(void*);
typedef size_t       (*t_image_get_class_count)(const void*);
typedef const void*  (*t_image_get_class)(const void*, size_t);
typedef const char*  (*t_class_get_namespace)(void*);
typedef const void*  (*t_method_get_return_type)(const void*);

static t_domain_get f_domain_get;
static t_thread_attach f_thread_attach;
static t_domain_get_assemblies f_domain_get_assemblies;
static t_assembly_get_image f_assembly_get_image;
static t_class_from_name f_class_from_name;
static t_class_get_method_from_name f_class_get_method_from_name;
static t_class_get_field_from_name f_class_get_field_from_name;
static t_field_get_offset f_field_get_offset;
static t_object_new f_object_new;
static t_object_get_class f_object_get_class;
static t_runtime_invoke f_runtime_invoke;
static t_string_new f_string_new;
static t_MSHookFunction f_MSHookFunction;
static t_gchandle_new f_gchandle_new;
static t_gchandle_free f_gchandle_free;
static t_class_get_nested_types f_class_get_nested_types;
static t_class_get_name f_class_get_name;
static t_class_get_methods f_class_get_methods;
static t_method_get_name f_method_get_name;
static t_method_get_param_count f_method_get_param_count;
static t_method_get_param f_method_get_param;
static t_type_get_name f_type_get_name;
static t_free f_free;
static t_format_exception f_format_exception;
static t_wbarrier_set_field f_wbarrier_set_field;
static t_class_get_fields f_class_get_fields;
static t_field_get_type f_field_get_type;
static t_type_get_type f_type_get_type;
static t_field_get_flags f_field_get_flags;
static t_class_from_type f_class_from_type;
static t_class_is_valuetype f_class_is_valuetype;
static t_class_get_parent f_class_get_parent;
static t_field_get_name f_field_get_name;
static t_image_get_class_count f_image_get_class_count;
static t_image_get_class f_image_get_class;
static t_class_get_namespace f_class_get_namespace;
static t_method_get_return_type f_method_get_return_type;

static void *gUnity = NULL;
#define SYM(v, name) v = (decltype(v))dlsym(gUnity ? gUnity : RTLD_DEFAULT, name)

// Field lookup lives here so Layout.mm can stay free of the raw C API.
void *pkRawFieldOffsetByName(void *cls, const char *name, ptrdiff_t *off) {
    if (!cls || !name || !f_class_get_field_from_name) return NULL;
    void *fld = f_class_get_field_from_name(cls, name);
    if (fld && off) *off = (ptrdiff_t)f_field_get_offset(fld);
    return fld;
}

void *pkRefFieldOffsetByName(void *cls, const char *name, ptrdiff_t *off) {
    if (!cls || !name || !f_class_get_field_from_name || !f_field_get_type || !f_type_get_type || !f_field_get_flags) return NULL;
    void *fld = f_class_get_field_from_name(cls, name);
    if (!fld || (f_field_get_flags(fld) & 0x10)) return NULL;               // missing, or static
    const void *t = f_field_get_type(fld);
    int ty = t ? f_type_get_type(t) : 0;
    BOOL isRef = ty == 0x0e || ty == 0x12 || ty == 0x1c;                    // string, class, object
    if (ty == 0x15 && f_class_from_type && f_class_is_valuetype) {          // Foo<T>: a reference unless it is a struct
        void *gk = f_class_from_type(t);
        isRef = gk && !f_class_is_valuetype(gk);
    }
    if (!isRef) return NULL;
    if (off) *off = (ptrdiff_t)f_field_get_offset(fld);
    return fld;
}

static volatile BOOL gArmed = NO;
void pkRuntimeArm(void) { gArmed = YES; }

BOOL pkRuntimeReady(void) {
    static BOOL done = NO;
    if (!gArmed) return NO;
    if (done) return YES;
    if (!gUnity) {
        NSString *fw = [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
        gUnity = dlopen(fw.fileSystemRepresentation, RTLD_NOLOAD);
    }
    SYM(f_domain_get, "il2cpp_domain_get");
    SYM(f_thread_attach, "il2cpp_thread_attach");
    SYM(f_domain_get_assemblies, "il2cpp_domain_get_assemblies");
    SYM(f_assembly_get_image, "il2cpp_assembly_get_image");
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
    SYM(f_gchandle_free, "il2cpp_gchandle_free");
    SYM(f_class_get_nested_types, "il2cpp_class_get_nested_types");
    SYM(f_class_get_name, "il2cpp_class_get_name");
    SYM(f_class_get_methods, "il2cpp_class_get_methods");
    SYM(f_method_get_name, "il2cpp_method_get_name");
    SYM(f_method_get_param_count, "il2cpp_method_get_param_count");
    SYM(f_method_get_param, "il2cpp_method_get_param");
    SYM(f_type_get_name, "il2cpp_type_get_name");
    SYM(f_free, "il2cpp_free");
    SYM(f_format_exception, "il2cpp_format_exception");
    SYM(f_wbarrier_set_field, "il2cpp_gc_wbarrier_set_field");
    SYM(f_class_get_fields, "il2cpp_class_get_fields");
    SYM(f_field_get_type, "il2cpp_field_get_type");
    SYM(f_type_get_type, "il2cpp_type_get_type");
    SYM(f_field_get_flags, "il2cpp_field_get_flags");
    SYM(f_class_from_type, "il2cpp_class_from_type");
    SYM(f_class_is_valuetype, "il2cpp_class_is_valuetype");
    SYM(f_class_get_parent, "il2cpp_class_get_parent");
    SYM(f_field_get_name, "il2cpp_field_get_name");
    SYM(f_image_get_class_count, "il2cpp_image_get_class_count");
    SYM(f_image_get_class, "il2cpp_image_get_class");
    SYM(f_class_get_namespace, "il2cpp_class_get_namespace");
    SYM(f_method_get_return_type, "il2cpp_method_get_return_type");
    done = f_domain_get && f_domain_get_assemblies && f_assembly_get_image &&
           f_class_from_name && f_class_get_method_from_name &&
           f_class_get_field_from_name && f_field_get_offset && f_object_new &&
           f_object_get_class && f_runtime_invoke && f_string_new && f_MSHookFunction;
    return done;
}

static void ensureAttached(void) {
    static thread_local bool attached = false;
    if (attached || !f_domain_get || !f_thread_attach) return;
    void *dom = f_domain_get();
    if (dom) { f_thread_attach(dom); attached = true; }
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
    ensureAttached();
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
NSString *pkClassName(void *obj) {
    void *k = pkClassOf(obj);
    return (k && f_class_get_name) ? @(f_class_get_name(k) ?: "?") : nil;
}

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

void *pkNestedClass(void *outer, const char *name) {
    if (!outer || !f_class_get_nested_types || !f_class_get_name) return NULL;
    void *iter = NULL, *k;
    while ((k = f_class_get_nested_types(outer, &iter))) {
        if (!strcmp(f_class_get_name(k), name)) return k;
        if (!strcmp(f_class_get_name(k), "Types")) {          // Outer.Types.Inner
            void *it2 = NULL, *k2;
            while ((k2 = f_class_get_nested_types(k, &it2)))
                if (!strcmp(f_class_get_name(k2), name)) return k2;
        }
    }
    return NULL;
}

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
    ensureAttached();
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

// ---------- reflection over overloads ----------
void pkEachMethod(void *cls, void (^fn)(void *, const char *, int)) {
    if (!cls || !f_class_get_methods || !f_method_get_name || !f_method_get_param_count) return;
    void *iter = NULL, *m;
    while ((m = f_class_get_methods(cls, &iter)))
        fn(m, f_method_get_name(m), (int)f_method_get_param_count(m));
}
NSString *pkParamTypeName(void *method, int index) {
    if (!method || !f_method_get_param || !f_type_get_name) return nil;
    const void *t = f_method_get_param(method, (uint32_t)index);
    if (!t) return nil;
    char *n = f_type_get_name(t);
    NSString *s = n ? @(n) : nil;
    if (n && f_free) f_free(n);
    return s;
}

// Il2CppTypeEnum: CLASS 0x12, GENERICINST 0x15, OBJECT 0x1c. (VALUETYPE 0x11 is
// an inline struct — its bytes are not a pointer.) FIELD_ATTRIBUTE_STATIC = 0x10.
void pkEachRefField(void *obj, void (^fn)(void *child)) {
    if (!obj || !f_class_get_fields || !f_field_get_type || !f_type_get_type || !f_field_get_flags) return;
    for (void *k = pkClassOf(obj); k; k = f_class_get_parent ? f_class_get_parent(k) : NULL) {
        void *iter = NULL, *fld;
        while ((fld = f_class_get_fields(k, &iter))) {
            if (f_field_get_flags(fld) & 0x10) continue;
            const void *t = f_field_get_type(fld);
            int ty = t ? f_type_get_type(t) : 0;
            BOOL isRef = ty == 0x12 || ty == 0x1c;
            if (ty == 0x15 && f_class_from_type && f_class_is_valuetype) {      // Foo<T>: a reference unless it is a struct
                void *gk = f_class_from_type(t);
                isRef = gk && !f_class_is_valuetype(gk);
            }
            if (!isRef) continue;
            void *child = *(void **)((char *)obj + f_field_get_offset(fld));
            if (child) fn(child);
        }
    }
}

void *pkFindClassByName(const char *name, NSString **ns) {
    if (!name || !f_domain_get || !f_image_get_class_count || !f_image_get_class || !f_class_get_name) return NULL;
    ensureAttached();
    void *dom = f_domain_get();
    if (!dom) return NULL;
    size_t n = 0; void **as = f_domain_get_assemblies(dom, &n);
    for (size_t i = 0; i < n; i++) {
        const void *im = f_assembly_get_image(as[i]);
        if (!im) continue;
        size_t count = f_image_get_class_count(im);
        for (size_t c = 0; c < count; c++) {
            void *k = (void *)f_image_get_class(im, c);
            const char *kn = k ? f_class_get_name(k) : NULL;
            if (kn && !strcmp(kn, name)) {
                if (ns) *ns = f_class_get_namespace ? @(f_class_get_namespace(k) ?: "") : @"";
                return k;
            }
        }
    }
    return NULL;
}

static NSString *typeText(const void *t) {
    if (!t || !f_type_get_name) return @"?";
    char *n = f_type_get_name(t);
    NSString *s = n ? @(n) : @"?";
    if (n && f_free) f_free(n);
    return s;
}

NSString *pkDescribeClass(void *cls) {
    if (!cls || !f_class_get_name) return @"(no class)";
    void *parent = f_class_get_parent ? f_class_get_parent(cls) : NULL;
    NSMutableString *out = [NSMutableString stringWithFormat:@"%s.%s : %s", f_class_get_namespace ? f_class_get_namespace(cls) : "",
                            f_class_get_name(cls), parent ? f_class_get_name(parent) : "-"];
    [out appendString:@" | fields:"];
    if (f_class_get_fields && f_field_get_name && f_field_get_type) {
        void *it = NULL, *fld; int n = 0;
        while ((fld = f_class_get_fields(cls, &it)) && n++ < 120)
            [out appendFormat:@" %s%s@0x%zx:%@;", (f_field_get_flags && (f_field_get_flags(fld) & 0x10)) ? "static " : "",
             f_field_get_name(fld) ?: "?", (size_t)f_field_get_offset(fld), typeText(f_field_get_type(fld))];
    }
    [out appendString:@" | methods:"];
    if (f_class_get_methods && f_method_get_name && f_method_get_param_count) {
        void *it = NULL, *m; int n = 0;
        while ((m = f_class_get_methods(cls, &it)) && n++ < 160) {
            NSMutableArray *ps = [NSMutableArray array];
            uint32_t pc = f_method_get_param_count(m);
            for (uint32_t i = 0; i < pc && f_method_get_param; i++) [ps addObject:typeText(f_method_get_param(m, i))];
            [out appendFormat:@" %@ %s(%@);", f_method_get_return_type ? typeText(f_method_get_return_type(m)) : @"?",
             f_method_get_name(m) ?: "?", [ps componentsJoinedByString:@","]];
        }
    }
    return out;
}

NSString *pkDescribeFields(void *cls) {
    if (!cls || !f_class_get_fields || !f_field_get_name || !f_field_get_type || !f_type_get_name) return @"(reflection unavailable)";
    NSMutableArray *bits = [NSMutableArray array];
    for (void *k = cls; k && bits.count < 80; k = f_class_get_parent ? f_class_get_parent(k) : NULL) {
        void *iter = NULL, *fld;
        while ((fld = f_class_get_fields(k, &iter))) {
            if (f_field_get_flags && (f_field_get_flags(fld) & 0x10)) continue;
            char *tn = f_type_get_name(f_field_get_type(fld));
            [bits addObject:[NSString stringWithFormat:@"%s@0x%zx:%s", f_field_get_name(fld) ?: "?", (size_t)f_field_get_offset(fld), tn ?: "?"]];
            if (tn && f_free) f_free(tn);
        }
    }
    return [bits componentsJoinedByString:@"; "];
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
