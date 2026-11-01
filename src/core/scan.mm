#include "./scan.h"
#include <frida-gum.h>
#include <dispatch/dispatch.h>
#include "../features/hitboxes.h"

static void boot_features()
{
    hitboxes_apply();
}

void poll_for_game(int attempt)
{
    if (gum_module_find_base_address("blackrussia-client") != nullptr) {
        gum_process_set_teardown_requirement(GUM_TEARDOWN_REQUIREMENT_MINIMAL);
        gum_init_embedded();
        boot_features();
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{ poll_for_game(attempt + 1); });
}