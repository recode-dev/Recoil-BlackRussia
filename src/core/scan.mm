#include "./scan.h"
#include <frida-gum.h>
#include <dispatch/dispatch.h>
#include "../features/hitboxes.h"
#include "../features/noreload.h"

static void boot_features()
{
    hitboxes_apply();
    noreload_apply();
}

void poll_for_game(int attempt)
{
    static bool gum_ready = false;
    if (!gum_ready) {
        gum_process_set_teardown_requirement(GUM_TEARDOWN_REQUIREMENT_MINIMAL);
        gum_init_embedded();
        gum_ready = true;
    }

    GumModule *module = gum_process_find_module_by_name("blackrussia-client");
    if (module != nullptr) {
        g_object_unref(module);
        boot_features();
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{ poll_for_game(attempt + 1); });
}