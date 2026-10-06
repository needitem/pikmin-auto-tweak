// The il2cpp C API as the tweak sees it: function pointers resolved by name from
// UnityFramework, once. INTERNAL to the IL2CPP layer (Runtime, Reflection): every
// other module goes through Runtime.h / Reflection.h, which add the caching, the
// null checks and the exception handling.
#pragma once
#import <Foundation/Foundation.h>

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
typedef void         (*t_field_static_get_value)(void*, void*);
typedef const void*  (*t_class_get_type)(void*);
typedef void*        (*t_type_get_object)(const void*);

extern t_domain_get f_domain_get;
extern t_thread_attach f_thread_attach;
extern t_domain_get_assemblies f_domain_get_assemblies;
extern t_assembly_get_image f_assembly_get_image;
extern t_class_from_name f_class_from_name;
extern t_class_get_method_from_name f_class_get_method_from_name;
extern t_class_get_field_from_name f_class_get_field_from_name;
extern t_field_get_offset f_field_get_offset;
extern t_object_new f_object_new;
extern t_object_get_class f_object_get_class;
extern t_runtime_invoke f_runtime_invoke;
extern t_string_new f_string_new;
extern t_MSHookFunction f_MSHookFunction;
extern t_gchandle_new f_gchandle_new;
extern t_gchandle_free f_gchandle_free;
extern t_class_get_nested_types f_class_get_nested_types;
extern t_class_get_name f_class_get_name;
extern t_class_get_methods f_class_get_methods;
extern t_method_get_name f_method_get_name;
extern t_method_get_param_count f_method_get_param_count;
extern t_method_get_param f_method_get_param;
extern t_type_get_name f_type_get_name;
extern t_free f_free;
extern t_format_exception f_format_exception;
extern t_wbarrier_set_field f_wbarrier_set_field;
extern t_class_get_fields f_class_get_fields;
extern t_field_get_type f_field_get_type;
extern t_type_get_type f_type_get_type;
extern t_field_get_flags f_field_get_flags;
extern t_class_from_type f_class_from_type;
extern t_class_is_valuetype f_class_is_valuetype;
extern t_class_get_parent f_class_get_parent;
extern t_field_get_name f_field_get_name;
extern t_image_get_class_count f_image_get_class_count;
extern t_image_get_class f_image_get_class;
extern t_class_get_namespace f_class_get_namespace;
extern t_field_static_get_value f_field_static_get_value;
extern t_class_get_type f_class_get_type;
extern t_type_get_object f_type_get_object;

// Resolve every entry point (idempotent, cheap once resolved). YES when the ones
// everything depends on were found. Called only through pkRuntimeReady(), which
// also waits until the game has a scene: before that, il2cpp calls crash.
BOOL pkIl2cppResolve(void);

// Make the calling thread known to il2cpp (once per thread).
void pkIl2cppAttachThread(void);
