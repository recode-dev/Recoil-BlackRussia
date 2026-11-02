#import <cstdio>
#import <cstdlib>
#import <cstring>
#import <cmath>
#import <initializer_list>
#import <dispatch/dispatch.h>
#import "../core/hook.h"
#import "../core/mem.h"
#import "../core/offsets.h"

namespace {

constexpr float kDefaultDistance = 0.0f;

volatile float g_distance = kDefaultDistance;
volatile bool g_follow_server = false;

enum class Mode { kNone, kSlot, kListener };
Mode g_mode = Mode::kNone;
bool g_gate_patched = false;
uintptr_t g_gate = 0;
uintptr_t g_slot = 0;

uint32_t enc_adrp(uintptr_t pc, uintptr_t target, unsigned rd)
{
    int64_t delta = (static_cast<int64_t>(target & ~0xFFFull) -
                     static_cast<int64_t>(pc & ~0xFFFull)) >> 12;
    if (delta < -(1 << 20) || delta >= (1 << 20))
        return 0;
    uint32_t imm = static_cast<uint32_t>(delta) & 0x1FFFFFu;
    return 0x90000000u | ((imm & 3u) << 29) | ((imm >> 2) << 5) | rd;
}

uint32_t enc_ldr_s(uintptr_t target, unsigned rn, unsigned rt)
{
    if ((target & 3) != 0)
        return 0;
    return 0xBD400000u | (((target & 0xFFFull) >> 2) << 10) | (rn << 5) | rt;
}

uint32_t enc_b(uintptr_t pc, uintptr_t target)
{
    int64_t off = (static_cast<int64_t>(target) - static_cast<int64_t>(pc)) >> 2;
    if (off < -(1 << 25) || off >= (1 << 25))
        return 0;
    return 0x14000000u | (static_cast<uint32_t>(off) & 0x03FFFFFFu);
}

uint32_t enc_bcond(uintptr_t pc, uintptr_t target, unsigned cond)
{
    int64_t off = (static_cast<int64_t>(target) - static_cast<int64_t>(pc)) >> 2;
    if (off < -(1 << 18) || off >= (1 << 18))
        return 0;
    return 0x54000000u | ((static_cast<uint32_t>(off) & 0x7FFFFu) << 5) | cond;
}

const uint32_t kGateOriginal[7] = {
    0xBD400E80u, 0x1E202008u, 0x540000CDu, 0x1E2021A0u,
    0x1E2E1000u, 0x1E20D5A0u, 0x540000A8u,
};

bool build_gate_patch(uint32_t out[7])
{
    out[0] = enc_adrp(g_gate + 0x00, g_slot, 8);
    out[1] = enc_ldr_s(g_slot, 8, 0);
    out[2] = 0x1E202008u;
    out[3] = enc_bcond(g_gate + 0x0C, g_gate + RVA_NAMETAG_LIMIT_CHECK - RVA_NAMETAG_GATE, 0xD);
    out[4] = 0x1E2021A0u;
    out[5] = enc_bcond(g_gate + 0x14, g_gate + RVA_NAMETAG_EPILOG - RVA_NAMETAG_GATE, 0x8);
    out[6] = enc_b(g_gate + 0x18, g_gate + RVA_NAMETAG_LIMIT_CHECK - RVA_NAMETAG_GATE);
    for (int i : {0, 3, 5, 6}) {
        if (out[i] == 0)
            return false;
    }
    return true;
}

bool gate_set_patched(bool patched)
{
    uint32_t words[7];
    if (patched) {
        if (!build_gate_patch(words))
            return false;
    } else {
        memcpy(words, kGateOriginal, sizeof(words));
    }
    if (!mem_patch_code(g_gate, words, sizeof(words)))
        return false;
    g_gate_patched = patched;
    return true;
}

bool slot_mode_apply()
{
    const uintptr_t base = game_base();
    if (base == 0)
        return false;
    g_gate = base + RVA_NAMETAG_GATE;
    g_slot = base + RVA_NAMETAG_DISTANCE;

    uint32_t cur[7];
    if ((g_slot & 3) != 0)
        return false;
    if (!mem_read(g_gate, cur, sizeof(cur)))
        return false;

    const bool vanilla = memcmp(cur, kGateOriginal, sizeof(cur)) == 0;
    const bool old_unlimited = memcmp(cur, kGateOriginal, 8) == 0 &&
                               cur[2] == 0x14000006u &&
                               memcmp(cur + 3, kGateOriginal + 3, sizeof(cur) - 12) == 0;
    uint32_t want[7];
    const bool ours = build_gate_patch(want) && memcmp(cur, want, sizeof(cur)) == 0;
    if (!vanilla && !old_unlimited && !ours)
        return false;

    if (ours) {
        g_gate_patched = true;
        return true;
    }
    return gate_set_patched(true);
}

void slot_write(float value)
{
    if (g_slot != 0)
        *reinterpret_cast<volatile float *>(g_slot) = value;
}

void *g_orig_renderer = nullptr;

void *on_renderer(void *a0, void *a1, void *a2, void *tag, void *a4, void *a5,
                  void *a6, void *a7)
{
    if (tag != nullptr && !g_follow_server)
        *reinterpret_cast<volatile float *>(static_cast<uint8_t *>(tag) + 0xC) = g_distance;

    using renderer_t = void *(*)(void *, void *, void *, void *, void *, void *, void *, void *);
    return reinterpret_cast<renderer_t>(g_orig_renderer)(a0, a1, a2, tag, a4, a5, a6, a7);
}

bool listener_mode_apply()
{
    if (g_orig_renderer != nullptr)
        return true;
    const uintptr_t base = game_base();
    if (base == 0)
        return false;
    return hook_function(base + RVA_NAMETAG_RENDERER,
                         reinterpret_cast<void *>(&on_renderer), &g_orig_renderer);
}

void apply_mode();

bool read_value(FILE *fp, float *out)
{
    char line[128];
    while (fgets(line, sizeof(line), fp) != nullptr) {
        const char *p = line;
        while (*p == ' ' || *p == '\t')
            ++p;
        if (*p == '\0' || *p == '\n' || *p == '#' || *p == '/')
            continue;
        char *end = nullptr;
        const float v = strtof(p, &end);
        if (end != p && !isnan(v)) {
            *out = v;
            return true;
        }
    }
    return false;
}

void poll_config()
{
    float v = 0.0f;
    bool have = false;

    const char *home = getenv("HOME");
    char path[512];
    FILE *fp = nullptr;
    if (home != nullptr) {
        snprintf(path, sizeof(path), "%s/Documents/nametags.txt", home);
        fp = fopen(path, "r");
    }
    if (fp == nullptr)
        fp = fopen("/var/mobile/Library/Preferences/br-nametags.cfg", "r");
    if (fp != nullptr) {
        have = read_value(fp, &v);
        fclose(fp);
    } else {
        static bool g_created = false;
        if (!g_created && home != nullptr) {
            g_created = true;
            if (FILE *w = fopen(path, "w")) {
                fputs("# nametags: дистанция ников и HP\n"
                      "# 0   - без лимита (по умолчанию)\n"
                      "# N>0 - показывать до N\n"
                      "# N<0 - как на сервере\n", w);
                fputs("0\n", w);
                fclose(w);
            }
        }
    }
    if (!have)
        return;

    if (v < 0.0f) {
        g_follow_server = true;
    } else {
        g_follow_server = false;
        g_distance = v;
    }
    apply_mode();
}

void apply_mode()
{
    if (g_mode == Mode::kSlot) {
        if (g_follow_server) {
            if (g_gate_patched)
                gate_set_patched(false);
        } else {
            if (!g_gate_patched)
                gate_set_patched(true);
            slot_write(g_distance);
        }
    }
}

void config_timer_start()
{
    static dispatch_source_t timer = nullptr;
    if (timer != nullptr)
        return;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW,
                              static_cast<uint64_t>(1.0 * NSEC_PER_SEC),
                              static_cast<uint64_t>(0.2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{ poll_config(); });
    dispatch_resume(timer);
}

}

bool nametags_apply()
{
    if (g_mode != Mode::kNone)
        return true;
    if (game_base() == 0)
        return false;

    poll_config();

    if (slot_mode_apply()) {
        g_mode = Mode::kSlot;
        apply_mode();
        config_timer_start();
        return true;
    }

    if (listener_mode_apply()) {
        g_mode = Mode::kListener;
        return true;
    }

    return false;
}
