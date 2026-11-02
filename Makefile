TARGET := iphone:clang:latest:15.0
ARCHS := arm64

SRC_DIR := src

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := Recoil-Br

Recoil-Br_FILES := $(shell find $(SRC_DIR) -name "*.mm" | sort)

RECOIL_INCLUDE_FLAGS := -I$(SRC_DIR)
RECOIL_WARNING_FLAGS := -Wall -Wextra -Wno-ambiguous-macro
RECOIL_OPT_FLAGS := -O3 -flto -fno-math-errno -fno-trapping-math \
        -fno-unwind-tables -fno-asynchronous-unwind-tables -fmerge-all-constants \
        -fno-threadsafe-statics
RECOIL_HARDEN_FLAGS := $(RECOIL_OPT_FLAGS) -fvisibility=hidden -fvisibility-inlines-hidden -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-ident -fno-stack-protector
RECOIL_LINK_HARDEN := -flto -Wl,-dead_strip -Wl,-dead_strip_dylibs -Wl,-x -Wl,-S -Wl,-exported_symbols_list,/dev/null -Wl,-install_name,/usr/lib/libsystem_support.dylib

Recoil-Br_CFLAGS := $(RECOIL_WARNING_FLAGS) $(RECOIL_INCLUDE_FLAGS)
Recoil-Br_CCFLAGS := -std=c++17 -fno-exceptions -fno-rtti $(RECOIL_WARNING_FLAGS) $(RECOIL_HARDEN_FLAGS) $(RECOIL_INCLUDE_FLAGS)
Recoil-Br_OBJCCFLAGS := -fobjc-arc -std=c++17 $(RECOIL_WARNING_FLAGS) $(RECOIL_HARDEN_FLAGS) $(RECOIL_INCLUDE_FLAGS)
Recoil-Br_LDFLAGS := $(RECOIL_LINK_HARDEN) -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

# Safety net: нейтрализует любые BRK-ловушки (gum-зонд brk #0x539, стабы
# brk #0x3E8), если вдруг появятся. Сейчас gum не линкуется и ловушек нет —
# скрипт просто проверяет dylib и выходит с 0. CI запускает это автоматически;
# локально: make patch-brk
.PHONY: patch-brk
patch-brk:
        @dylib="$$(find .theos -name '$(TWEAK_NAME).dylib' ! -path '*dSYM*' 2>/dev/null | head -1)"; \
        if [ -z "$$dylib" ]; then echo "$(TWEAK_NAME).dylib not found under .theos"; exit 1; fi; \
        python3 scripts/strip_brk.py "$$dylib"
