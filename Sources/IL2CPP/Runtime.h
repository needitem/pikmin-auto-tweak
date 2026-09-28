// Thin, cached bridge to the game's il2cpp runtime. Knows nothing about
// Pikmin Bloom: classes, methods, strings, hooks, collections.
//
// Rule for callers: an il2cpp pointer is valid only for the pass that obtained
// it. Never keep one across passes or timers (the GC owns those objects);
// keep ids as NSString and rebuild the managed string when it is needed.
#pragma once
#import <Foundation/Foundation.h>
#include <stddef.h>
#include <stdint.h>

// One field of a game class, located by name at runtime. `fallback` is the
// offset seen in the reference dump; it is used only while the layout is
// trusted (see Layout.h).
typedef struct PKField {
    const char *name;    // il2cpp field name, NULL when not known
    const char *alt;     // alternative name (other corlib flavours)
    ptrdiff_t fallback;  // reference-dump offset, -1 = none
    ptrdiff_t off;       // >=0 resolved, -2 not yet tried, -1 failed
} PKField;
#define PKF(n, a, fb) { n, a, fb, -2 }

// ---- runtime ----
// Nothing here touches il2cpp until the app arms the bridge (the game has
// created its scene, so Unity has finished initialising). Every il2cpp call
// path goes through pkRuntimeReady(), so this one gate covers them all; before
// it opens, il2cpp calls crash (a null deref inside UnityFramework at launch).
void pkRuntimeArm(void);
BOOL pkRuntimeReady(void);   // resolves the API once; false until armed and Unity is loaded

void *pkClass(const char *ns, const char *name);                 // cached
void *pkClassOf(void *obj);
void *pkMethod(void *cls, const char *name, int argc);           // cached
void *pkMethodOf(void *obj, const char *name, int argc);
void *pkNestedClass(void *outer, const char *name);              // Outer.Types.Inner

// Invocation. Exceptions are logged (throttled) and reported as NULL/NO.
void *pkInvoke(void *method, void *obj, void **args);
void *pkInvokeEx(void *method, void *obj, void **args, BOOL *ok);
void *pkCall0(void *obj, const char *name);                      // instance, no args
int   pkUnboxInt(void *boxed);
BOOL  pkUnboxBool(void *boxed);

// Managed strings and objects.
NSString *pkStr(void *il2cppString);
void *pkNewString(NSString *s);
void *pkNewObj(void *cls);                                       // new + .ctor()
void *pkNewProto(const char *name, void **outCls);               // Ichigo.Proto.<name>
void  pkWriteRef(void *obj, void **slot, void *value);           // GC write barrier when available

// Reflection over overloads (used to tell apart same-arity overloads).
void pkEachMethod(void *cls, void (^fn)(void *method, const char *name, int argc));
NSString *pkParamTypeName(void *method, int index);

// Hooks.
BOOL pkHookMethod(void *cls, const char *method, int argc, void *hook, void **orig);

// GC handles (keep a captured singleton alive).
uint32_t pkGcPin(void *obj);
void pkGcUnpin(uint32_t handle);

// ---- collections (List<T>, RepeatedField<T>, Dictionary<K,V>) ----
void pkListEach(void *list, void (^fn)(void *item));
int  pkListCount(void *list);
void pkRepeatedEach(void *repeated, void (^fn)(void *item));
int  pkRepeatedCount(void *repeated);
void pkRepeatedAdd(void *repeated, void *item);
void pkRepeatedClear(void *repeated);
void pkDictEachValue(void *dict, void (^fn)(void *value));       // reference-type values
