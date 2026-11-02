// uuid/uuid.h — shim для урезанного theos-SDK (нет <uuid/uuid.h>).
// dyld_cache_format.h использует только тип uuid_t.

#pragma once

typedef unsigned char uuid_t[16];
