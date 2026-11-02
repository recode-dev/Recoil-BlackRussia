#import <string.h>
#import <stdint.h>
#import "../core/mem.h"
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
constexpr float kMultiplier = 10.0f;

float g_base[kSphereCount];
bool g_snapshotted = false;

void snapshot(PedHitboxSphere *table)
{
    if (g_snapshotted) return;
    for (int i = 0; i < kSphereCount; ++i)
        g_base[i] = table[i].radius;
    g_snapshotted = true;
}

} // namespace

void hitboxes_apply()
{
    const uintptr_t base = game_base();
    if (base == 0) return;

    auto *table = reinterpret_cast<PedHitboxSphere *>(base + RVA_PED_HITBOX_SPHERES);

    snapshot(table);

    mem_make_rw(base + RVA_PED_HITBOX_SPHERES,
                static_cast<size_t>(kSphereCount) * sizeof(PedHitboxSphere));

    for (int i = 0; i < kSphereCount; ++i)
        table[i].radius = g_base[i] * kMultiplier;
}
