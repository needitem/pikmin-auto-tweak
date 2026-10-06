// Looking inside the game's classes: fields and methods by name, the reference
// fields of an object, enum constants, a class by its simple name, an instance of a
// ScriptableObject. Built on Runtime.h; none of it belongs in a hot path (the class
// walk is for diagnostics and one-off lookups, the reference-field walk for the
// singleton finder).
#pragma once
#import <Foundation/Foundation.h>
#include <stddef.h>

void *pkNestedClass(void *outer, const char *name);              // Outer.Types.Inner

// Offset of a named instance field of `cls` (own class or a parent), or NULL when
// it has none.
void *pkRawFieldOffsetByName(void *cls, const char *name, ptrdiff_t *off);

// A class by its simple name alone (any namespace, any assembly); the namespace
// comes back in `ns`. Walks every class once per distinct name, so it is for
// diagnostics, not for passes.
void *pkFindClassByName(const char *name, NSString **ns);

// An enum's named constants as value -> name (empty when it cannot be read).
NSDictionary<NSNumber *, NSString *> *pkEnumMap(void *enumClass);
// First live instance of a UnityEngine.Object subclass (ScriptableObject
// catalogs and the like), via Resources.FindObjectsOfTypeAll. NULL if none.
void *pkFindObjectOfClass(void *cls);

// Reflection over overloads (used to tell apart same-arity overloads).
void pkEachMethod(void *cls, void (^fn)(void *method, const char *name, int argc));
NSString *pkParamTypeName(void *method, int index);

// Every non-null reference-typed instance field of `obj` (own class and parents),
// as the referenced objects. Value-type fields are never read as pointers.
void pkEachRefField(void *obj, void (^fn)(void *child));
