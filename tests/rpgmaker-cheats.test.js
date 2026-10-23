// Runs EverPlay's RPG Maker cheat script against a small stand-in for the MV/MZ engine objects.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// EverPlay reads results as JSON; comparing the same way also leaves the VM's realm behind.
const json = (value) => JSON.parse(JSON.stringify(value));
const source = readFileSync(new URL('../App/Resources/RPGMakerCheats.js', import.meta.url), 'utf8');

function engine() {
  class Actor {
    constructor(id, name) { this._id = id; this._name = name; this.level = 5; this.hp = 10; this.mhp = 100; this.mp = 1; this.mmp = 20; }
    actorId() { return this._id; }
    name() { return this._name; }
    maxLevel() { return 99; }
    recoverAll() { this.hp = this.mhp; this.mp = this.mmp; }
    changeLevel(level) { this.level = level; }
  }
  const items = [null, { id: 1, name: 'Potion' }, { id: 2, name: 'Ether' }, { id: 3, name: '' }];
  const weapons = [null, { id: 1, name: 'Sword' }];
  const counts = new Map();
  const party = {
    _gold: 120,
    _members: [new Actor(1, 'Reid'), new Actor(2, 'Mia')],
    gold() { return this._gold; },
    maxGold() { return 99999999; },
    gainGold(n) { this._gold = Math.max(0, Math.min(this.maxGold(), this._gold + n)); },
    members() { return this._members; },
    numItems(item) { return counts.get(item) || 0; },
    maxItems() { return 99; },
    gainItem(item, n) { counts.set(item, Math.max(0, Math.min(99, (counts.get(item) || 0) + n))); },
  };
  const store = (values) => ({ value: (id) => values[id] || 0, setValue: (id, v) => { values[id] = v; } });
  const sceneCalls = { scene: 0, input: 0 };
  class GamePlayer {}
  GamePlayer.prototype.isDebugThrough = function () { return false; };
  GamePlayer.prototype.canEncounter = function () { return true; };
  const context = {
    Utils: { RPGMAKER_NAME: 'MV' },
    $gameParty: party,
    $dataSystem: { variables: ['', 'Affection', '', 'Day'], switches: ['', 'Met Anna', 'Door open'] },
    $gameVariables: store({ 1: 3, 2: 7 }),
    $gameSwitches: store({ 2: true }),
    $dataItems: items,
    $dataWeapons: weapons,
    $dataArmors: [null],
    SceneManager: {
      updateScene() { sceneCalls.scene++; },
      updateInputData() { sceneCalls.input++; },
    },
    Game_Player: GamePlayer,
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  return { context, cheats: context.__everplayCheats, party, sceneCalls, items, counts };
}

test('reports party and gold, and changes them through the engine', () => {
  const { cheats, party } = engine();
  const status = cheats.status();
  assert.equal(status.ready, true);
  assert.equal(status.engine, 'MV');
  assert.equal(status.gold, 120);
  assert.deepEqual(json(status.party.map((a) => a.name)), ['Reid', 'Mia']);
  assert.equal(cheats.addGold(1000).gold, 1120);
  assert.equal(cheats.setGold(50).gold, 50);
  assert.equal(cheats.addGold(1e12).gold, 99999999);
  cheats.heal();
  assert.equal(party.members()[0].hp, 100);
  cheats.levelUp(200);
  assert.equal(party.members()[1].level, 99);
  assert.throws(() => cheats.addGold('ten'));
});

test('lists and edits variables and switches with name, id and value search', () => {
  const { cheats } = engine();
  assert.deepEqual(json(cheats.variables('').map((v) => v.id)), [1, 2, 3]);
  assert.deepEqual(json(cheats.variables('aff').map((v) => v.id)), [1]);
  assert.deepEqual(json(cheats.variables('#2').map((v) => v.id)), [2]);
  assert.deepEqual(json(cheats.variables('=7').map((v) => v.id)), [2]);
  cheats.setVariable(3, 42);
  assert.equal(cheats.variables('day')[0].value, 42);
  assert.deepEqual(json(cheats.switches('').map((s) => [s.id, s.value])), [[1, false], [2, true]]);
  cheats.setSwitch(1, true);
  assert.equal(cheats.switches('met')[0].value, true);
});

test('lists named items and adds them within the stack limit', () => {
  const { cheats } = engine();
  assert.deepEqual(json(cheats.items('item', '').map((i) => i.name)), ['Potion', 'Ether']);
  cheats.gainItem('item', 1, 150);
  assert.equal(cheats.items('item', 'potion')[0].count, 99);
  cheats.gainItem('weapon', 1, 1);
  assert.equal(cheats.items('weapon', '')[0].count, 1);
  assert.throws(() => cheats.items('spell', ''));
});

test('speed runs extra scene updates with fresh input; walk-through and encounters toggle', () => {
  const { context, cheats, sceneCalls } = engine();
  cheats.setSpeed(3);
  context.SceneManager.updateScene();
  assert.equal(sceneCalls.scene, 3);
  assert.equal(sceneCalls.input, 2);
  cheats.setSpeed(99);
  assert.equal(cheats.status().speed, 8);
  const player = new context.Game_Player();
  assert.equal(player.isDebugThrough(), false);
  cheats.setThrough(true);
  assert.equal(player.isDebugThrough(), true);
  cheats.setNoEncounters(true);
  assert.equal(player.canEncounter(), false);
});

test('waits for a running game', () => {
  const context = { Utils: { RPGMAKER_NAME: 'MZ' } };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  assert.deepEqual(json(context.__everplayCheats.status()), { engine: 'MZ', ready: false });
});
