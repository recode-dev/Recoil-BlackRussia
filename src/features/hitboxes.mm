#import <string.h>
#import <stdint.h>
#import <frida-gum.h>
#import "../core/offsets.h"

namespace {

struct PedHitboxSphere {
    int32_t bone_id;
    uint8_t part_index;
    float off_x;
    float off_y;
    float radius;
    uint8_t pad[12];
};

constexpr int kSphereCount = 10;
constexpr float kMultiplier = 3.5f;

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

float g_base[kSphereCount];
bool g_snapshotted = false;

void snapshot(PedHitboxSphere *table) {
    if (g_snapshotted) return;
    for (int i = 0; i < kSphereCount; ++i)
        g_base[i] = table[i].radius;
    g_snapshotted = true;
}

}

void hitboxes_apply() {
    uintptr_t base = game_base();
    if (base == 0) return;

    auto *table = reinterpret_cast<PedHitboxSphere *>(base + RVA_PED_HITBOX_SPHERES);

    snapshot(table);

    gum_mprotect(reinterpret_cast<gpointer>((base + RVA_PED_HITBOX_SPHERES) & ~static_cast<gsize>(0xFFF)),
                 kSphereCount * sizeof(PedHitboxSphere) + static_cast<gsize>(0xFFF),
                 GUM_PAGE_RW);

    for (int i = 0; i < kSphereCount; ++i)
        table[i].radius = g_base[i] * kMultiplier;
}