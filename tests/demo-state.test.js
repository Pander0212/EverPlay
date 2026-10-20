import test from 'node:test';
import assert from 'node:assert/strict';
import { freshState, act, restoreState } from '../DemoGame/state.js';

test('touch action model collects gold and buys inventory without mutating its input', () => {
  const original = freshState();
  const collected = act(act(original, 'collect'), 'collect');
  assert.equal(original.gold, 0);
  const purchased = act(collected, 'seed');
  assert.equal(purchased.seeds, 1);
  assert.equal(purchased.gold, 0);
});
test('insufficient gold cannot buy a seed', () => assert.equal(act(freshState(), 'seed').seeds, 0));
test('save round-trip retains variable, position, dialogue and inventory', () => {
  let state = freshState();
  for (const action of ['collect', 'collect', 'seed', 'day', 'right', 'talk']) state = act(state, action);
  assert.deepEqual(restoreState(JSON.stringify(state)), state);
});
test('corrupt and future saves are rejected instead of silently overwritten', () => {
  for (const raw of ['broken', '{}', '{"version":2}', JSON.stringify({ ...freshState(), gold: -1 }), JSON.stringify({ ...freshState(), x: 500 })]) {
    assert.throws(() => restoreState(raw));
  }
});
test('dialogue cycles and movement stays inside the scene', () => {
  let state = freshState();
  for (let i = 0; i < 100; i++) state = act(state, 'left');
  assert.equal(state.x, 10);
  for (let i = 0; i < 3; i++) state = act(state, 'talk');
  assert.equal(state.dialogue, 0);
});
