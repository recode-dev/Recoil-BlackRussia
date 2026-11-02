import { hitboxesApply } from './hitboxes.js';

const MODULE_NAME = 'blackrussia-client';
const POLL_INTERVAL_MS = 1000;

export function pollForGame() {
  const mod = Process.findModuleByName(MODULE_NAME);
  if (mod === null) {
    setTimeout(pollForGame, POLL_INTERVAL_MS);
    return;
  }
  hitboxesApply(mod.base);
}
