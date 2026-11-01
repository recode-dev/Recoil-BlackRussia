#import <stdint.h>
#import <frida-gum.h>
#import "../core/offsets.h"

namespace {

constexpr uintptr_t kGate = RVA_NAMETAG_GATE;
constexpr uintptr_t kSlot = RVA_NAMETAG_DISTANCE;
constexpr float kDrawDistance = 0.0f;

constexpr uint32_t adrp_word(uintptr_t pc, uintptr_t target, uint32_t rd)
{
    int64_t imm = static_cast<int64_t>((target & ~static_cast<uintptr_t>(0xFFF)) -
                                       (pc & ~static_cast<uintptr_t>(0xFFF))) >> 12;
    imm &= 0x1FFFFF;
    return 0x90000000u | (static_cast<uint32_t>(imm & 0x3) << 29) |
           (static_cast<uint32_t>(imm >> 2) << 5) | rd;
}

constexpr uint32_t ldr_word(uintptr_t slot)
{
    return 0xBD400000u | (8u << 5) | (((slot & 0xFFF) >> 2) << 10);
}

constexpr uint32_t kGateWords[7] = {
    adrp_word(kGate, kSlot, 8),
    ldr_word(kSlot),
    0x1E202008u,
    0x540000A9u,
    0x1E2021A0u,
    0x54002A88u,
    0x14000002u,
};

constexpr uint32_t kGateOriginal[7] = {
    0xBD400E80u, 0x1E202008u, 0x540000CDu,
    0x1E2021A0u, 0x1E2E1000u, 0x1E20D5A0u, 0x540000A8u,
};

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

bool g_applied = false;

}

void nametags_apply()
{
    uintptr_t base = game_base();
    if (base == 0 || g_applied) return;

    auto *gate = reinterpret_cast<volatile uint32_t *>(base + kGate);
    for (int i = 0; i < 7; ++i)
        if (gate[i] != kGateOriginal[i]) return;

    if (!gum_mprotect(reinterpret_cast<gpointer>((base + kGate) & ~static_cast<guintptr>(0xFFF)),
                      static_cast<gsize>(0x1000), GUM_PAGE_RW))
        return;

    *reinterpret_cast<volatile float *>(base + kSlot) = kDrawDistance;

    for (int i = 0; i < 7; ++i)
        gate[i] = kGateWords[i];

    __builtin___clear_cache(reinterpret_cast<char *>(base + kGate),
                            reinterpret_cast<char *>(base + kGate + 28));

    g_applied = true;
}
