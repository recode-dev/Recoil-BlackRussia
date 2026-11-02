#import "../core/hook.h"
#import "../core/mem.h"
#import "../core/offsets.h"

// noreload.mm — отключение перезарядки через ElleKit (MSHookFunction).
//
// RVA_WEAPON_RELOAD_REQUEST (0x9AD710) — функция-запрос перезарядки. Хук
// ставит на её вход прыжок на пустую заглушку: функция не выполняется,
// перезарядка не запускается. Оригинал сохраняется в g_orig_reload (trampoline
// ElleKit), движок резолвится в рантайме — без него фича просто не включается.

namespace {

void *g_orig_reload = nullptr;

void noreload_reload_stub()
{
    // запрос перезарядки полностью игнорируется
}

} // namespace

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
