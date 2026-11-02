#import "./mem.h"

#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <libkern/OSCacheControl.h>
#import <cstring>
#import <strings.h>
#import <unistd.h>

#ifndef VM_FLAGS_OVERWRITE
#define VM_FLAGS_OVERWRITE 0x4000
#endif

uintptr_t game_base()
{
    static uintptr_t base = 0;
    if (base != 0)
        return base;

    const uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *path = _dyld_get_image_name(i);
        if (path == nullptr)
            continue;
        // basename без модификации path
        const char *slash = strrchr(path, '/');
        const char *name = (slash != nullptr) ? slash + 1 : path;
        if (strcasecmp(name, "blackrussia-client") == 0) {
            const struct mach_header *header = _dyld_get_image_header(i);
            if (header != nullptr)
                base = reinterpret_cast<uintptr_t>(header);
            break;
        }
    }
    return base;
}

bool mem_read(uintptr_t addr, void *out, size_t len)
{
    if (addr == 0 || out == nullptr || len == 0)
        return false;
    memcpy(out, reinterpret_cast<const void *>(addr), len);
    return true;
}

static size_t page_size()
{
    static size_t ps = 0;
    if (ps == 0) {
        const long v = sysconf(_SC_PAGESIZE);
        ps = (v > 0) ? static_cast<size_t>(v) : 0x4000;
    }
    return ps;
}

static bool page_range(uintptr_t addr, size_t len, uintptr_t *page, size_t *plen)
{
    if (addr == 0 || len == 0)
        return false;
    const size_t ps = page_size();
    const uintptr_t begin = addr & ~(static_cast<uintptr_t>(ps) - 1);
    const uintptr_t end = (addr + len + ps - 1) & ~(static_cast<uintptr_t>(ps) - 1);
    *page = begin;
    *plen = static_cast<size_t>(end - begin);
    return true;
}

bool mem_make_rw(uintptr_t addr, size_t len)
{
    uintptr_t page = 0;
    size_t plen = 0;
    if (!page_range(addr, len, &page, &plen))
        return false;
    const kern_return_t kr = vm_protect(mach_task_self(), page, plen, 0,
                                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    return kr == KERN_SUCCESS;
}

bool mem_patch_code(uintptr_t addr, const void *buf, size_t len)
{
    uintptr_t page = 0;
    size_t plen = 0;
    if (addr == 0 || buf == nullptr || len == 0 || !page_range(addr, len, &page, &plen))
        return false;

    // 1) Прямой путь: COW-перевод страниц (__TEXT) в RW, запись, возврат RX.
    if (vm_protect(mach_task_self(), page, plen, 0,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) == KERN_SUCCESS) {
        memcpy(reinterpret_cast<void *>(addr), buf, len);
        vm_protect(mach_task_self(), page, plen, 0, VM_PROT_READ | VM_PROT_EXECUTE);
        sys_icache_invalidate(reinterpret_cast<void *>(addr), len);
        return true;
    }

    // 2) Фолбэк: собранную страницу ремапим поверх оригинала (copy-on-remap).
    // На iOS (arm64) vm_* — это 64-битные mach_vm_* (mach_vm.h в SDK запрещён).
    vm_address_t scratch = 0;
    if (vm_allocate(mach_task_self(), &scratch, plen, VM_FLAGS_ANYWHERE) != KERN_SUCCESS)
        return false;
    memcpy(reinterpret_cast<void *>(scratch), reinterpret_cast<const void *>(page), plen);
    memcpy(reinterpret_cast<void *>(scratch + (addr - page)), buf, len);
    vm_protect(mach_task_self(), scratch, plen, 0, VM_PROT_READ | VM_PROT_EXECUTE);

    vm_address_t target = page;
    vm_prot_t cur = VM_PROT_NONE;
    vm_prot_t maxp = VM_PROT_NONE;
    const kern_return_t kr = vm_remap(mach_task_self(), &target, plen, 0,
                                      VM_FLAGS_OVERWRITE | VM_FLAGS_FIXED,
                                      mach_task_self(), scratch, TRUE, &cur, &maxp,
                                      VM_INHERIT_COPY);
    if (kr != KERN_SUCCESS) {
        vm_deallocate(mach_task_self(), scratch, plen);
        return false;
    }
    vm_deallocate(mach_task_self(), scratch, plen);
    sys_icache_invalidate(reinterpret_cast<void *>(addr), len);
    return true;
}
