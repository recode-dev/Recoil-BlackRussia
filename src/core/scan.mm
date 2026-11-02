#include "./scan.h"
#include "./mem.h"
#include <dispatch/dispatch.h>
#include "../features/hitboxes.h"
#include "../features/nametags.h"

static void boot_features()
{
    hitboxes_apply();
    nametags_apply();
}

void poll_for_game(int attempt)
{
    if (game_base() != 0) {
        boot_features();
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{ poll_for_game(attempt + 1); });
}
