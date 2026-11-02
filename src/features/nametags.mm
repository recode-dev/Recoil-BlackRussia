#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <math.h>
#import <dispatch/dispatch.h>
#import <frida-gum.h>
#import "../core/offsets.h"

// nametags.mm — редактируемый вариант.
//
// Дистанция ников/HP задаётся в конфиге и меняется на лету (опрос раз в секунду):
//   <HOME>/Documents/nametags.txt          — основной путь (контейнер приложения, удобно править из Filza)
//   /var/mobile/Library/Preferences/br-nametags.cfg — запасной путь
// Формат: первое число в файле.
//   0   — без лимита (по умолчанию)
//   N>0 — показывать ники/HP до N
//   N<0 — вести себя как ваниль (серверное значение)
//
// Два режима, выбираются автоматически при старте:
//   kSlot     — на ванильном бинарнике переписываем гейт RVA_NAMETAG_GATE (7 слов):
//               maxDist читается не из структуры [x20+0xC], а из RW-слота
//               RVA_NAMETAG_DISTANCE (мёртвый паддинг в конце __DATA).
//               Значение слота можно менять и извне (memory editor: base+0x19E3B84).
//   kListener — если байты гейта неизвестны (обновилась игра): gum-слушатель на
//               RVA_NAMETAG_RENDERER перезаписывает поле +0xC структуры тега
//               на каждый вызов (проверено на ванили и на старом безлимитном патче).

namespace {

constexpr float kDefaultDistance = 0.0f; // без лимита, пока конфиг не прочитан

// g_distance > 0 -> лимит; == 0 -> без лимита; g_follow_server -> не трогать (сервер)
volatile float g_distance = kDefaultDistance;
volatile bool g_follow_server = false;

enum class Mode { kNone, kSlot, kListener };
Mode g_mode = Mode::kNone;
bool g_gate_patched = false;
uintptr_t g_gate = 0;
uintptr_t g_slot = 0;

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

// ---------- кодирование инструкций ----------

uint32_t enc_adrp(uintptr_t pc, uintptr_t target, unsigned rd) {
    int64_t delta = (static_cast<int64_t>(target & ~0xFFFull) -
                     static_cast<int64_t>(pc & ~0xFFFull)) >> 12;
    if (delta < -(1 << 20) || delta >= (1 << 20))
        return 0;
    uint32_t imm = static_cast<uint32_t>(delta) & 0x1FFFFFu;
    return 0x90000000u | ((imm & 3u) << 29) | ((imm >> 2) << 5) | rd;
}

uint32_t enc_ldr_s(uintptr_t target, unsigned rn, unsigned rt) {
    if ((target & 3) != 0)
        return 0;
    return 0xBD400000u | (((target & 0xFFFull) >> 2) << 10) | (rn << 5) | rt;
}

uint32_t enc_b(uintptr_t pc, uintptr_t target) {
    int64_t off = (static_cast<int64_t>(target) - static_cast<int64_t>(pc)) >> 2;
    if (off < -(1 << 25) || off >= (1 << 25))
        return 0;
    return 0x14000000u | (static_cast<uint32_t>(off) & 0x03FFFFFFu);
}

uint32_t enc_bcond(uintptr_t pc, uintptr_t target, unsigned cond) {
    int64_t off = (static_cast<int64_t>(target) - static_cast<int64_t>(pc)) >> 2;
    if (off < -(1 << 18) || off >= (1 << 18))
        return 0;
    return 0x54000000u | ((static_cast<uint32_t>(off) & 0x7FFFFu) << 5) | cond;
}

// ---------- режим kSlot: переписанный гейт + RW-слот ----------

// Оригинальный гейт (ван):
//   ldr   s0, [x20, #0xc]      ; серверный maxDist
//   fcmp  s0, #0.0
//   b.le  limit_check          ; maxDist <= 0 -> сравнение с 1.0
//   fcmp  s13, s0              ; dist vs maxDist
//   fmov  s0, #1.0
//   fccmp s13, s0, #0, le
//   b.hi  draw                 ; 1.0 < dist <= maxDist -> рисовать
const uint32_t kGateOriginal[7] = {
    0xBD400E80u, 0x1E202008u, 0x540000CDu, 0x1E2021A0u,
    0x1E2E1000u, 0x1E20D5A0u, 0x540000A8u,
};

// Новый гейт: maxDist = float из слота; семантика прежняя:
//   slot <= 0 -> рисовать при dist > 1.0; slot > 0 -> при 1.0 < dist <= slot
// (эквивалентность оригиналу подтверждена посимуляторно, включая NaN/inf)
struct GatePatch {
    uint32_t words[7];
};

bool build_gate_patch(uint32_t out[7]) {
    out[0] = enc_adrp(g_gate + 0x00, g_slot, 8);                        // adrp x8, slot
    out[1] = enc_ldr_s(g_slot, 8, 0);                                   // ldr  s0, [x8, #off]
    out[2] = 0x1E202008u;                                               // fcmp s0, #0.0
    out[3] = enc_bcond(g_gate + 0x0C, g_gate + RVA_NAMETAG_LIMIT_CHECK - RVA_NAMETAG_GATE, 0xD); // b.le limit_check
    out[4] = 0x1E2021A0u;                                               // fcmp s13, s0
    out[5] = enc_bcond(g_gate + 0x14, g_gate + RVA_NAMETAG_EPILOG - RVA_NAMETAG_GATE, 0x8);      // b.hi эпилог
    out[6] = enc_b(g_gate + 0x18, g_gate + RVA_NAMETAG_LIMIT_CHECK - RVA_NAMETAG_GATE);          // b limit_check
    for (int i : {0, 3, 5, 6}) {
        if (out[i] == 0)
            return false;
    }
    return true;
}

void gate_write_cb(gpointer mem, gpointer user_data) {
    const GatePatch *p = static_cast<const GatePatch *>(user_data);
    memcpy(mem, p->words, sizeof(p->words));
}

bool gate_set_patched(bool patched) {
    uint32_t words[7];
    if (patched) {
        if (!build_gate_patch(words))
            return false;
    } else {
        memcpy(words, kGateOriginal, sizeof(words));
    }
    GatePatch p;
    memcpy(p.words, words, sizeof(p.words));
    gum_memory_patch_code(static_cast<GumAddress>(g_gate), sizeof(p.words), gate_write_cb, &p);
    g_gate_patched = patched;
    return true;
}

bool slot_mode_apply() {
    const uintptr_t base = game_base();
    if (base == 0)
        return false;
    g_gate = base + RVA_NAMETAG_GATE;
    g_slot = base + RVA_NAMETAG_DISTANCE;

    uint32_t cur[7];
    if ((g_slot & 3) != 0)
        return false;
    if (gum_memory_read(reinterpret_cast<gpointer>(g_gate), sizeof(cur), cur) != sizeof(cur))
        return false;

    const bool vanilla = memcmp(cur, kGateOriginal, sizeof(cur)) == 0;
    // старый статический патч "b.le -> b" (безлимит): отличается только слово 2
    const bool old_unlimited = memcmp(cur, kGateOriginal, 8) == 0 &&
                               cur[2] == 0x14000006u &&
                               memcmp(cur + 3, kGateOriginal + 3, sizeof(cur) - 12) == 0;
    // наш редактируемый патч уже стоит (например, бинарник собран со статической
    // перезаписью гейта) — тогда достаточно просто писать слот из конфига
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

void slot_write(float value) {
    if (g_slot != 0)
        *reinterpret_cast<volatile float *>(g_slot) = value;
}

// ---------- режим kListener: gum-слушатель (fallback) ----------

void on_nametag_enter(GumInvocationContext *ctx, gpointer) {
    if (g_follow_server)
        return;
    auto *tag = static_cast<uint8_t *>(gum_invocation_context_get_nth_argument(ctx, 3));
    if (tag != nullptr)
        *reinterpret_cast<volatile float *>(tag + 0xC) = g_distance;
}

bool listener_mode_apply() {
    const uintptr_t base = game_base();
    if (base == 0)
        return false;

    GumInterceptor *interceptor = gum_interceptor_obtain();
    GumInvocationListener *listener = gum_make_call_listener(on_nametag_enter, nullptr, nullptr, nullptr);
    if (!gum_interceptor_attach(interceptor,
                                reinterpret_cast<gpointer>(base + RVA_NAMETAG_RENDERER),
                                listener, nullptr)) {
        g_object_unref(listener);
        g_object_unref(interceptor);
        return false;
    }
    g_object_unref(interceptor);
    return true;
}

// ---------- конфиг ----------

void apply_mode();

bool read_value(FILE *fp, float *out) {
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

void poll_config() {
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

void apply_mode() {
    if (g_mode == Mode::kSlot) {
        if (g_follow_server) {
            // серверное значение: вернуть оригинальный гейт
            if (g_gate_patched)
                gate_set_patched(false);
        } else {
            if (!g_gate_patched)
                gate_set_patched(true);
            slot_write(g_distance);
        }
    }
    // kListener: значение берётся на каждом вызове в on_nametag_enter
}

void config_timer_start() {
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

} // namespace

void nametags_apply() {
    if (game_base() == 0 || g_mode != Mode::kNone)
        return;

    poll_config(); // первичное чтение значения (apply_mode ещё неактивен)

    if (slot_mode_apply()) {
        g_mode = Mode::kSlot;
    } else if (listener_mode_apply()) {
        g_mode = Mode::kListener;
    } else {
        return;
    }

    apply_mode();      // записать значение в слот / выставить состояние гейта
    config_timer_start();
}
