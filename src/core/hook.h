#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef void *(*ms_hook_function_t)(void *symbol, void *replace, void **result);
ms_hook_function_t hook_engine(void);

bool hook_function(uintptr_t target, void *replace, void **out_orig);
