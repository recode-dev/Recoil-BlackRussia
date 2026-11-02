#pragma once

#include <stdint.h>

#define RVA_PED_HITBOX_SPHERES 0x19DA210
#define RVA_WEAPON_RELOAD_REQUEST 0x9AD710
#define RVA_NAMETAG_RENDERER 0xA5085C
#define RVA_NAMETAG_GATE 0xA50910
#define RVA_NAMETAG_LIMIT_CHECK 0xA50930 // fmov s0,#1.0; fcmp dist; b.ls -> эпилог
#define RVA_NAMETAG_DRAW_PATH 0xA5093C
#define RVA_NAMETAG_EPILOG 0xA50E74
#define RVA_NAMETAG_DISTANCE 0x19E3B84 // RW-слот maxDist (мёртвый паддинг __DATA)