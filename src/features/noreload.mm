#import <mach/mach.h>
#import <stdint.h>
#import <litehook.h>
#import "../core/mem.h"
#import "../core/offsets.h"

// noreload.mm — отключение перезарядки через litehook.
//
// RVA_WEAPON_RELOAD_REQUEST (0x9AD710) — функция-запрос перезарядки. Хук
// litehook_hook_function пишет на её вход 20-байтовый прыжок (movk x16 x4 + br
// x16) на пустую заглушку: функция никогда не выполняется, перезарядка не
// запускается. Оригинал не нужен (litehook не умеет trampoline — и здесь он не
// требуется). Никаких brk/mach exception server — в отличие от старой версии на
// frida-gum.

namespace {

volatile uintptr_t g_hooked_at = 0;

void noreload_reload_stub()
{
    // запрос перезарядки полностью игнорируется
}

} // namespace

void noreload_apply()
{
    if (g_hooked_at != 0)
        return;

    const uintptr_t base = game_base();
    if (base == 0)
        return;

    const uintptr_t target = base + RVA_WEAPON_RELOAD_REQUEST;
    const kern_return_t kr =
        litehook_hook_function(reinterpret_cast<void *>(target),
                               reinterpret_cast<void *>(&noreload_reload_stub));
    if (kr == KERN_SUCCESS)
        g_hooked_at = target;
}
