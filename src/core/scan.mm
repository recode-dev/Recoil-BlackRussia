#include "./scan.h"
#include "./mem.h"
#include <dispatch/dispatch.h>
#include "../features/hitboxes.h"
#include "../features/nametags.h"
#include "../features/noreload.h"

static bool boot_features()
{
    bool pending = false;

    if (!noreload_apply())
        pending = true;
    hitboxes_apply();
    if (!nametags_apply())
        pending = true;

    return !pending;
}

void poll_for_game(int attempt)
{
    if (game_base() == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       ^{ poll_for_game(attempt + 1); });
        return;
    }

    if (!boot_features() && attempt < 120) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       ^{ poll_for_game(attempt + 1); });
    }
}
