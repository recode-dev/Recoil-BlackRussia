#include "./core/scan.h"
#include <dispatch/dispatch.h>

static __attribute__((constructor)) void start()
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{ poll_for_game(0); });
}
