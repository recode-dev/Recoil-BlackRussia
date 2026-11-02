#pragma once

#include <stdbool.h>
#include <stdint.h>

// hook.mm — хук-движок tweak'а: API CydiaSubstrate (MSHookFunction), который на
// устройстве обслуживает ElleKit (libellekit.dylib экспортирует MSHookFunction и
// ставится как libsubstrate/libhooker — TrollFools, Dopamine, palera1n и т.д.).
//
// Никакой линковки: символ резолвится в рантайме через dlsym, поэтому dylib
// грузится всегда; если хук-движка в процессе нет — хукующие фичи просто
// выключены, остальное (патчи байт) работает как раньше. Никаких brk-зондов и
// mach exception server, в отличие от frida-gum.

// Указатель на MSHookFunction либо nullptr, если движок не найден (повторные
// вызовы повторяют поиск — движок может догрузиться позже).
typedef void *(*ms_hook_function_t)(void *symbol, void *replace, void **result);
ms_hook_function_t hook_engine(void);

// Хук функции по адресу; *out_orig получает trampoline оригинала (можно nullptr).
// false — движка нет или хук не удался (можно повторить позже).
bool hook_function(uintptr_t target, void *replace, void **out_orig);
