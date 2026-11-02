#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

uintptr_t game_base(void);

bool mem_read(uintptr_t addr, void *out, size_t len);

bool mem_make_rw(uintptr_t addr, size_t len);

bool mem_patch_code(uintptr_t addr, const void *buf, size_t len);
