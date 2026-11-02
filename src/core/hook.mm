#import "./hook.h"

#import <dlfcn.h>

ms_hook_function_t hook_engine()
{
    static ms_hook_function_t cached = nullptr;
    static bool resolved = false;
    if (resolved)
        return cached;

    // ElleKit/TrollFools/джейлбрейки: MSHookFunction уже в глобальном скоупе
    cached = reinterpret_cast<ms_hook_function_t>(dlsym(RTLD_DEFAULT, "MSHookFunction"));

    if (cached == nullptr) {
        // стандартные пути установки; RTLD_NOLOAD — не грузим лишнее, только ищем
        const char *paths[] = {
            "/usr/lib/libellekit.dylib",
            "/var/jb/usr/lib/libellekit.dylib",
            "/usr/lib/libsubstrate.dylib",
            "/var/jb/usr/lib/libsubstrate.dylib",
            "/usr/lib/libhooker.dylib",
            "/var/jb/usr/lib/libhooker.dylib",
        };
        for (const char *path : paths) {
            void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL | RTLD_NOLOAD);
            if (handle == nullptr)
                continue;
            cached = reinterpret_cast<ms_hook_function_t>(dlsym(handle, "MSHookFunction"));
            if (cached != nullptr)
                break;
        }
    }

    if (cached != nullptr)
        resolved = true; // неудачный поиск не кэшируем: движок мог догрузиться позже
    return cached;
}

bool hook_function(uintptr_t target, void *replace, void **out_orig)
{
    ms_hook_function_t fn = hook_engine();
    if (fn == nullptr)
        return false;

    void *orig = nullptr;
    fn(reinterpret_cast<void *>(target), replace, &orig);
    if (orig == nullptr)
        return false;
    if (out_orig != nullptr)
        *out_orig = orig;
    return true;
}
