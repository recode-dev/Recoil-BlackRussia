#import <stdint.h>
#import <frida-gum.h>
#import "../core/offsets.h"

namespace {

constexpr float kDrawDistance = 0.0f;

uintptr_t game_base()
{
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

void on_nametag_enter(GumInvocationContext *ctx, gpointer)
{
    auto *tag = static_cast<uint8_t *>(gum_invocation_context_get_nth_argument(ctx, 3));
    if (tag != nullptr)
        *reinterpret_cast<volatile float *>(tag + 0xC) = kDrawDistance;
}

bool g_applied = false;

}

void nametags_apply()
{
    uintptr_t base = game_base();
    if (base == 0 || g_applied) return;

    GumInterceptor *interceptor = gum_interceptor_obtain();
    GumInvocationListener *listener = gum_make_call_listener(
        on_nametag_enter, nullptr, nullptr, nullptr);
    GumAttachOptions options = {};

    if (!gum_interceptor_attach(interceptor,
                                reinterpret_cast<gpointer>(base + RVA_NAMETAG_RENDERER),
                                listener, &options)) {
        g_object_unref(listener);
        g_object_unref(interceptor);
        return;
    }

    g_object_unref(interceptor);
    g_applied = true;
}
