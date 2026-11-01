#import <stdint.h>
#import <frida-gum.h>
#import "../core/offsets.h"

namespace {

constexpr uint32_t kRet = 0xD65F03C0u;

uintptr_t game_base() {
    static uintptr_t base = 0;
    if (base == 0) {
        GumModule *module = gum_process_find_module_by_name("blackrussia-client");
        if (module != nullptr) {
            base = static_cast<uintptr_t>(gum_module_get_range(module)->base_address);
            g_object_unref(module);
        }
    }
    return base;
}

}

void noreload_apply() {
    uintptr_t base = game_base();
    if (base == 0) return;

    auto *target = reinterpret_cast<uint32_t *>(base + RVA_WEAPON_RELOAD_REQUEST);
    if (*target == kRet) return;

    gsize page_size = gum_query_page_size();
    auto *page = reinterpret_cast<gpointer>(
        reinterpret_cast<uintptr_t>(target) & ~static_cast<uintptr_t>(page_size - 1));

    if (!gum_try_mprotect(page, page_size, GUM_PAGE_RW)) return;

    *target = kRet;

    gum_clear_cache(target, sizeof(kRet));

    gum_try_mprotect(page, page_size, GUM_PAGE_RX);
}
