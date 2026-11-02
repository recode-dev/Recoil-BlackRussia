import { RVA_PED_HITBOX_SPHERES } from '../core/offsets.js';

const SPHERE_SIZE = 32;
const RADIUS_OFFSET = 16;
const SPHERE_COUNT = 10;
const MULTIPLIER = 10.0;
const PAGE_MASK = '0xfffffffffffff000';

let originals = null;

export function hitboxesApply(base) {
  const table = base.add(RVA_PED_HITBOX_SPHERES);

  if (originals === null) {
    originals = [];
    for (let i = 0; i < SPHERE_COUNT; i++)
      originals.push(table.add(i * SPHERE_SIZE + RADIUS_OFFSET).readFloat());
  }

  Memory.protect(table.and(ptr(PAGE_MASK)), SPHERE_COUNT * SPHERE_SIZE + 0xFFF, 'rw-');

  for (let i = 0; i < SPHERE_COUNT; i++)
    table.add(i * SPHERE_SIZE + RADIUS_OFFSET).writeFloat(originals[i] * MULTIPLIER);
}
