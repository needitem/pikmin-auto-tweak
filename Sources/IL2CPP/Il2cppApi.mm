// Definitions of the il2cpp entry points and the one place that resolves them.
#import "Il2cppApi.h"
#import <dlfcn.h>

t_domain_get f_domain_get;
t_thread_attach f_thread_attach;
t_domain_get_assemblies f_domain_get_assemblies;
t_assembly_get_image f_assembly_get_image;
t_class_from_name f_class_from_name;
t_class_get_method_from_name f_class_get_method_from_name;
t_class_get_field_from_name f_class_get_field_from_name;
t_field_get_offset f_field_get_offset;
t_object_new f_object_new;
t_object_get_class f_object_get_class;
t_runtime_invoke f_runtime_invoke;
t_string_new f_string_new;
t_MSHookFunction f_MSHookFunction;
t_gchandle_new f_gchandle_new;
t_gchandle_free f_gchandle_free;
t_class_get_nested_types f_class_get_nested_types;
t_class_get_name f_class_get_name;
t_class_get_methods f_class_get_methods;
t_method_get_name f_method_get_name;
t_method_get_param_count f_method_get_param_count;
t_method_get_param f_method_get_param;
t_type_get_name f_type_get_name;
t_free f_free;
t_format_exception f_format_exception;
t_wbarrier_set_field f_wbarrier_set_field;
t_class_get_fields f_class_get_fields;
t_field_get_type f_field_get_type;
t_type_get_type f_type_get_type;
t_field_get_flags f_field_get_flags;
t_class_from_type f_class_from_type;
t_class_is_valuetype f_class_is_valuetype;
t_class_get_parent f_class_get_parent;
t_field_get_name f_field_get_name;
t_image_get_class_count f_image_get_class_count;
t_image_get_class f_image_get_class;
t_class_get_namespace f_class_get_namespace;
t_field_static_get_value f_field_static_get_value;
t_class_get_type f_class_get_type;
t_type_get_object f_type_get_object;

static void *gUnity = NULL;
#define SYM(v, name) v = (decltype(v))dlsym(gUnity ? gUnity : RTLD_DEFAULT, name)

BOOL pkIl2cppResolve(void) {
    static BOOL done = NO;
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
    SYM(f_field_static_get_value, "il2cpp_field_static_get_value");
    SYM(f_class_get_type, "il2cpp_class_get_type");
    SYM(f_type_get_object, "il2cpp_type_get_object");
    done = f_domain_get && f_domain_get_assemblies && f_assembly_get_image &&
           f_class_from_name && f_class_get_method_from_name &&
           f_class_get_field_from_name && f_field_get_offset && f_object_new &&
           f_object_get_class && f_runtime_invoke && f_string_new && f_MSHookFunction;
    return done;
}

void pkIl2cppAttachThread(void) {
    static thread_local bool attached = false;
    if (attached || !f_domain_get || !f_thread_attach) return;
    void *dom = f_domain_get();
    if (dom) { f_thread_attach(dom); attached = true; }
}

