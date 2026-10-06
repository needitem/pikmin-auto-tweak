#import "Reflection.h"
#import "Il2cppApi.h"
#import "Runtime.h"

// Field lookup lives here so Layout.mm can stay free of the raw C API.
void *pkRawFieldOffsetByName(void *cls, const char *name, ptrdiff_t *off) {
    if (!cls || !name || !f_class_get_field_from_name) return NULL;
    void *fld = f_class_get_field_from_name(cls, name);
    if (fld && off) *off = (ptrdiff_t)f_field_get_offset(fld);
    return fld;
}

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

// ---------- methods, fields, classes by name ----------
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
    pkIl2cppAttachThread();
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

NSDictionary<NSNumber *, NSString *> *pkEnumMap(void *cls) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (!cls || !f_class_get_fields || !f_field_get_flags || !f_field_get_name || !f_field_static_get_value) return out;
    void *it = NULL, *fld;
    while ((fld = f_class_get_fields(cls, &it))) {
        int flags = f_field_get_flags(fld);
        if (!(flags & 0x10) || !(flags & 0x40)) continue;            // static literal = an enum constant
        int64_t v = 0;
        f_field_static_get_value(fld, &v);
        out[@((int)v)] = @(f_field_get_name(fld) ?: "?");
    }
    return out;
}

void *pkFindObjectOfClass(void *cls) {
    if (!cls || !f_class_get_type || !f_type_get_object) return NULL;
    void *res = pkClass("UnityEngine", "Resources");
    void *m = res ? pkMethod(res, "FindObjectsOfTypeAll", 1) : NULL;
    const void *t = f_class_get_type(cls);
    void *tobj = t ? f_type_get_object(t) : NULL;
    if (!m || !tobj) return NULL;
    void *args[1] = { tobj };
    void *arr = pkInvoke(m, NULL, args);                              // Object[]: length @0x18, items @0x20
    if (!arr) return NULL;
    size_t n = *(size_t *)((char *)arr + 0x18);
    void **items = (void **)((char *)arr + 0x20);
    for (size_t i = 0; i < n && i < 64; i++) if (items[i]) return items[i];
    return NULL;
}

