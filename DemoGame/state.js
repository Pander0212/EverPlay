export const SAVE_KEY = 'everplay.lantern-garden.v1';
export function freshState() { return { version: 1, gold: 0, seeds: 0, day: 1, dialogue: 0, x: 50 }; }
export function restoreState(raw) {
  if (!raw) return freshState();
  const state = JSON.parse(raw);
  if (state.version !== 1) throw new Error('Unsupported save version');
  for (const key of ['gold', 'seeds', 'day', 'dialogue', 'x']) {
    if (!Number.isSafeInteger(state[key]) || state[key] < 0 || state[key] > 1_000_000) throw new Error('Invalid save');
  }
  if (state.day < 1 || state.x > 90) throw new Error('Invalid save');
  return state;
}
export function act(state, action) {
  const next = { ...state };
  if (action === 'collect') next.gold = Math.min(1_000_000, next.gold + 10);
  if (action === 'seed' && next.gold >= 20 && next.seeds < 1_000_000) { next.gold -= 20; next.seeds++; }
  if (action === 'day') next.day = Math.min(1_000_000, next.day + 1);
  if (action === 'talk') next.dialogue = (next.dialogue + 1) % 3;
  if (action === 'left') next.x = Math.max(10, next.x - 5);
  if (action === 'right') next.x = Math.min(90, next.x + 5);
  return next;
}
