// Runs EverPlay's RPG Maker save editor against stand-ins for the MV/MZ storage and save objects.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const json = (value) => JSON.parse(JSON.stringify(value));
const source = readFileSync(new URL('../App/Resources/RPGMakerSaves.js', import.meta.url), 'utf8');

function engine(name) {
  const context = {};
  // Like the engine's JsonEx: classes survive a round trip through "@c".
  const classes = {};
  class Game_Party {
    maxGold() { return 99999999; }
    maxItems() { return 99; }
  }
  class Game_Actor {
    maxLevel() { return 50; }
    expForLevel(level) { return level * 100; }
    get mhp() { return this._level * 10; }
    get mmp() { return this._level * 2; }
  }
  class Game_Variables {}
  class Game_Switches {}
  class Game_Actors {}
  Object.assign(classes, { Game_Party, Game_Actor, Game_Variables, Game_Switches, Game_Actors });
  const JsonEx = {
    stringify: (value) => JSON.stringify(value, function (key, item) {
      if (item && typeof item === 'object' && !Array.isArray(item) && classes[item.constructor.name]) {
        return { '@c': item.constructor.name, ...item };
      }
      return item;
    }),
    parse: (text) => JSON.parse(text, (key, item) => {
      if (item && typeof item === 'object' && item['@c']) {
        const object = Object.create(classes[item['@c']].prototype);
        delete item['@c'];
        return Object.assign(object, item);
      }
      return item;
    }),
  };
  const make = (Class, fields) => Object.assign(new Class(), fields);
  const save = () => ({
    party: make(Game_Party, { _gold: 300, _actors: [2, 1], _items: { 1: 3 }, _weapons: {}, _armors: {} }),
    actors: make(Game_Actors, { _data: [null,
      make(Game_Actor, { _actorId: 1, _name: 'Reid', _level: 4, _classId: 1, _exp: { 1: 400 }, _hp: 5, _mp: 1 }),
      make(Game_Actor, { _actorId: 2, _name: 'Mia', _level: 7, _classId: 2, _exp: { 2: 700 }, _hp: 5, _mp: 1 })] }),
    variables: make(Game_Variables, { _data: [null, 3, 0, 9] }),
    switches: make(Game_Switches, { _data: [null, false, true] }),
  });
  const files = new Map();
  const backups = [];
  if (name === 'MV') {
    files.set(1, JsonEx.stringify(save()));
    context.StorageManager = {
      exists: (id) => files.has(id),
      load: (id) => files.get(id),
      save: (id, text) => files.set(id, text),
      backup: (id) => backups.push(id),
    };
    context.DataManager = {
      maxSavefiles: () => 20,
      loadSavefileInfo: (id) => (files.has(id) ? { title: 'Lantern', playtime: '01:02:03', timestamp: 5 } : null),
    };
  } else {
    files.set('file0', save());
    files.set('file3', save());
    context.StorageManager = {
      loadObject: async (saveName) => JsonEx.parse(JsonEx.stringify(files.get(saveName))),
      saveObject: async (saveName, object) => { files.set(saveName, JsonEx.parse(JsonEx.stringify(object))); },
    };
    context.DataManager = {
      maxSavefiles: () => 20,
      makeSavename: (id) => `file${id}`,
      savefileInfo: (id) => (files.has(`file${id}`) ? { title: 'Lantern', playtime: '00:10:00', timestamp: id } : null),
    };
  }
  Object.assign(context, {
    Utils: { RPGMAKER_NAME: name },
    JsonEx,
    $dataSystem: { variables: ['', 'Affection', '', 'Day'], switches: ['', 'Met Anna', 'Door open'] },
    $dataItems: [null, { id: 1, name: 'Potion' }, { id: 2, name: 'Ether' }],
    $dataWeapons: [null, { id: 1, name: 'Sword' }],
    $dataArmors: [null],
  });
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  return { saves: context.__everplaySaves, files, backups, JsonEx };
}

test('MV: lists slots and edits one slot through StorageManager with a backup first', async () => {
  const { saves, files, backups, JsonEx } = engine('MV');
  assert.deepEqual(json(await saves.slots()), [{ id: 1, title: 'Lantern', playtime: '01:02:03', timestamp: 5, autosave: false }]);
  const summary = await saves.summary(1);
  assert.equal(summary.gold, 300);
  assert.deepEqual(json(summary.actors.map((a) => [a.name, a.level])), [['Mia', 7], ['Reid', 4]]);
  assert.equal((await saves.setGold(1, 1e12)).gold, 99999999);
  assert.deepEqual(backups, [1]);
  const leveled = await saves.setLevel(1, 1, 80);
  assert.equal(leveled.actors[1].level, 50);
  const actor = JsonEx.parse(files.get(1)).actors._data[1];
  assert.equal(actor._exp[1], 5000);
  assert.equal(actor._hp, 500);
  // The written file still restores the engine's classes.
  assert.equal(typeof JsonEx.parse(files.get(1)).party.maxGold, 'function');
  await assert.rejects(saves.summary(2), /empty/);
  await assert.rejects(saves.summary(99), /no such save slot/);
});

test('MV: variables, switches and items with name, id and value search', async () => {
  const { saves } = engine('MV');
  assert.deepEqual(json((await saves.variables(1, '')).map((v) => [v.id, v.value])), [[1, 3], [3, 9]]);
  assert.deepEqual(json((await saves.variables(1, '=9')).map((v) => v.id)), [3]);
  await saves.setVariable(1, 2, 42);
  assert.equal((await saves.variables(1, '#2'))[0].value, 42);
  assert.deepEqual(json((await saves.switches(1, '')).map((s) => [s.id, s.value])), [[1, false], [2, true]]);
  await saves.setSwitch(1, 1, true);
  assert.equal((await saves.switches(1, 'met'))[0].value, true);
  assert.deepEqual(json((await saves.items(1, 'item', '')).map((i) => [i.name, i.count])), [['Potion', 3], ['Ether', 0]]);
  await saves.gainItem(1, 'item', 2, 500);
  await saves.gainItem(1, 'item', 1, -10);
  assert.deepEqual(json((await saves.items(1, 'item', '')).map((i) => i.count)), [0, 99]);
  await saves.gainItem(1, 'weapon', 1, 1);
  assert.equal((await saves.items(1, 'weapon', ''))[0].count, 1);
  await assert.rejects(saves.items(1, 'spell', ''), /unknown item kind/);
});

test('MZ: slot 0 is the autosave; edits go through loadObject and saveObject', async () => {
  const { saves, files } = engine('MZ');
  assert.deepEqual(json((await saves.slots()).map((s) => [s.id, s.autosave])), [[0, true], [3, false]]);
  await saves.setGold(3, 1234);
  assert.equal(files.get('file3').party._gold, 1234);
  assert.equal(files.get('file0').party._gold, 300);
  await saves.setVariable(3, 1, 8);
  assert.equal(files.get('file3').variables._data[1], 8);
});

test('waits for the engine', async () => {
  const context = { Utils: { RPGMAKER_NAME: 'MZ' } };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  assert.deepEqual(json(await context.__everplaySaves.slots()), []);
});
