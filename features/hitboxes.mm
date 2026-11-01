#import <string.h>
#import <stdint.h>
#import <frida-gum/gum.h>
#import "offsets.h"

namespace {

struct PedHitboxSphere {
    int32_t bone_id;
    uint8_t part_index;
    float off_x;
    float off_y;
    float radius;
};

constexpr int kSphereCount = 10;
constexpr float kMultiplier = 1.5f;

uintptr_t game_base() {
    static uintptr_t base = 0;
    if (base == 0)
        base = reinterpret_cast<uintptr_t>(gum_module_find_base_address("blackrussia-client"));
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
    uintptr_t table_addr = game_base() + RVA_PED_HITBOX_SPHERES;
    auto *table = reinterpret_cast<PedHitboxSphere *>(table_addr);
    if (!table) return;

    snapshot(table);

    gum_mprotect(reinterpret_cast<gpointer>(table_addr & ~static_cast<gsize>(0xFFF)),
                 kSphereCount * sizeof(PedHitboxSphere) + static_cast<gsize>(0xFFF),
                 GUM_PAGE_RW);

    for (int i = 0; i < kSphereCount; ++i)
        table[i].radius = g_base[i] * kMultiplier;

    gum_mprotect(reinterpret_cast<gpointer>(table_addr & ~static_cast<gsize>(0xFFF)),
                 kSphereCount * sizeof(PedHitboxSphere) + static_cast<gsize>(0xFFF),
                 GUM_PAGE_READ);
}

__attribute__((constructor)) static void hitboxes_boot() {
    gum_init_embedded();
    hitboxes_apply();
}