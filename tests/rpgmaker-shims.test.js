// EverPlay's Node/NW.js stand-ins for desktop RPG Maker plugins.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../App/Resources/RPGMakerShims.js', import.meta.url), 'utf8');

function page() {
  const warnings = [];
  const context = { document: { title: 'Game' }, innerWidth: 816, innerHeight: 624, console: { warn: (m) => warnings.push(m) } };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  return { context, warnings };
}

test('plugins that call require load, and the engine still runs in browser mode', () => {
  const { context, warnings } = page();
  // RPG Maker's own check (Utils.isNwjs) must stay false so saves use browser storage.
  assert.equal(vm.runInContext("typeof require === 'function' && typeof process === 'object'", context), false);
  const fs = context.require('fs');
  assert.equal(fs.existsSync('save/file1.rpgsave'), false);
  assert.throws(() => fs.readFileSync('save/global.rpgsave'), /ENOENT/);
  assert.equal(fs.readdirSync('img').length, 0);
  const path = context.require('node:path');
  assert.equal(path.join('www', 'img/', 'pictures', 'a.png'), 'www/img/pictures/a.png');
  assert.equal(path.basename('img/pictures/a.png', '.png'), 'a');
  assert.equal(path.extname('a.rpgmvp'), '.rpgmvp');
  const gui = context.require('nw.gui');
  gui.Window.get().on('close', () => {});
  gui.Window.get().toggleFullscreen();
  let called = false;
  context.require('fs').readFile('x', 'utf8', (error) => { called = error.code === 'ENOENT'; });
  assert.equal(called, true);
  assert.deepEqual(JSON.parse(JSON.stringify(context.require('steamworks'))), {});
  assert.equal(warnings.length, 1);
});

test('an existing require is left alone', () => {
  const context = { document: { title: '' }, require: () => 'native' };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  assert.equal(context.require('fs'), 'native');
});
