#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// mem.mm — тонкий слой памяти без frida-gum.
//
// Раньше здесь стоял gum (gum_process_find_module_by_name / gum_memory_read /
// gum_memory_patch_code / gum_mprotect / gum_init_embedded). gum тянул за собой
// mach exception server, мониторы потоков и self-test `brk #0x539` — источник
// падений в игре (у твиков без gum таких проблем нет). Все операции заменены
// публичными API dyld/mach, поведение то же.

// Адрес загрузки (base) исполняемого образа blackrussia-client; 0 — не найден.
uintptr_t game_base(void);

// Чтение памяти процесса (same-task: обычный memcpy).
bool mem_read(uintptr_t addr, void *out, size_t len);

// Перевод страниц диапазона в RW (VM_PROT_COPY для read-only __DATA_CONST и т.п.).
bool mem_make_rw(uintptr_t addr, size_t len);

// Патч исполняемого кода: RW через VM_PROT_COPY -> запись -> возврат RX ->
// сброс кэша инструкций. Фолбэк — mach_vm_remap(copy) поверх страницы.
bool mem_patch_code(uintptr_t addr, const void *buf, size_t len);
