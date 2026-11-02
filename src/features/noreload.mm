#import "../core/hook.h"
#import "../core/mem.h"
#import "../core/offsets.h"

namespace {

void *g_orig_reload = nullptr;

void noreload_reload_stub()
{
}

}

bool noreload_apply()
{
    if (g_orig_reload != nullptr)
        return true;

    const uintptr_t base = game_base();
    if (base == 0)
        return false;

    return hook_function(base + RVA_WEAPON_RELOAD_REQUEST,
                         reinterpret_cast<void *>(&noreload_reload_stub),
                         &g_orig_reload);
}
