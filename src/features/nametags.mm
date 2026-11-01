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

typedef struct {
    GObject parent;
} NametagListener;

typedef struct {
    GObjectClass parent;
} NametagListenerClass;

static void nametag_listener_class_init(NametagListenerClass *)
{
}

static void nametag_listener_init(NametagListener *)
{
}

static void nametag_listener_iface_init(gpointer iface, gpointer)
{
    auto *listener_iface = static_cast<GumInvocationListenerIface *>(iface);
    listener_iface->on_enter = [](GumInvocationListener *, GumInvocationContext *ctx) {
        auto *tag = static_cast<uint8_t *>(gum_invocation_context_get_nth_argument(ctx, 3));
        if (tag != nullptr)
            *reinterpret_cast<volatile float *>(tag + 0xC) = kDrawDistance;
    };
}

G_DEFINE_TYPE_WITH_CODE(NametagListener, nametag_listener, G_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(GUM_TYPE_INVOCATION_LISTENER, nametag_listener_iface_init))

bool g_applied = false;

}

void nametags_apply()
{
    uintptr_t base = game_base();
    if (base == 0 || g_applied) return;

    auto *listener = static_cast<NametagListener *>(
        g_object_new(NAMETAG_TYPE_LISTENER, nullptr));

    GumInterceptor *interceptor = gum_interceptor_acquire();
    if (!gum_interceptor_attach(interceptor,
                                reinterpret_cast<gpointer>(base + RVA_NAMETAG_RENDERER),
                                GUM_INVOCATION_LISTENER(listener), nullptr)) {
        g_object_unref(listener);
        g_object_unref(interceptor);
        return;
    }

    g_object_unref(interceptor);
    g_applied = true;
}
