// ptrauth.h — shim для theos-тулчейна (в нём нет builtin-заголовка ptrauth.h).
//
// Твик собирается под plain arm64 (не arm64e): в arm64-процессах указатели
// функций не подписаны, поэтому все ptrauth_* операции — identity. При появлении
// arm64e-цели этот shim нужно заменить на builtin-заголовок clang.

#pragma once

#define ptrauth_key_asia 0
#define ptrauth_key_asib 1
#define ptrauth_key_asda 2
#define ptrauth_key_asdb 3
#define ptrauth_key_function_pointer ptrauth_key_asia
#define ptrauth_key_return_address ptrauth_key_asia
#define ptrauth_key_process_independent_code ptrauth_key_asdb

#define ptrauth_strip(value, key) ((void *)(value))
#define ptrauth_auth_function(value, key, discriminator) ((void *)(value))
#define ptrauth_auth_data(value, key, discriminator) ((void *)(value))
#define ptrauth_sign_unauthenticated(value, key, discriminator) ((void *)(value))
#define ptrauth_auth_and_resign(value, old_key, old_disc, new_key, new_disc) ((void *)(value))
#define ptrauth_blend_discriminator(value, discriminator) ((void *)(value))
#define ptrauth_sign_generic_data(value, data) ((void *)(value))
#define ptrauth_auth_generic_data(value, data) ((void *)(value))
