// Drive an assembled real Ren'Py desktop game (scripts/assemble-renpy-desktop-data.py)
// in Chromium under EverPlay's CSP, using only EverPlay's virtual-key events.
// Game state is observed read-only through the runtime's own renpy_get().
// The bundle contains a third-party game: keep it and every output private.
// Logs contain statement positions and counts only, never game text.
//
//   node scripts/test-renpy-desktop-game-browser.mjs --bundle <zip> --out <private dir> [--language ger]
import { chromium } from 'playwright';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { parseArgs } from 'node:util';

const { values } = parseArgs({ options: {
  bundle: { type: 'string' }, out: { type: 'string' }, language: { type: 'string', default: 'ger' },
} });
assert.ok(values.bundle && values.out, '--bundle and --out are required');
await mkdir(values.out, { recursive: true });
const work = await mkdtemp(path.join(tmpdir(), 'everplay-renpy-game-'));
const root = path.join(work, 'web');
execFileSync('python3', ['-I', '-m', 'zipfile', '-e', values.bundle, root]);
const router = await readFile('Sources/EverPlayCore/HTTPResourceRouter.swift', 'utf8');
const policy = router.match(/"Content-Security-Policy": "([^"]+)"/)[1];
const mime = {'.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.jpg':'image/jpeg'};
const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://localhost');
    const file = path.resolve(root, decodeURIComponent(url.pathname.slice('/game/'.length)) || 'index.html');
    if (!url.pathname.startsWith('/game/') || !file.startsWith(root + path.sep)) throw new Error('outside');
    response.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Content-Security-Policy': policy, 'Cache-Control': 'no-store'});
    response.end(await readFile(file));
  } catch { response.writeHead(404); response.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;

// Read-only Python expressions (shared with AppUnitTests/RenPyDesktopGameTests.swift).
const FOCUS = "(lambda f: [] if f is None else [(type(a).__name__, str(getattr(a, 'name', '')), str(getattr(a, 'screen', '')), str(getattr(a, 'value', ''))) for a in (f.action if isinstance(getattr(f, 'action', None), list) else [getattr(f, 'action', None)])])(renpy.display.focus.get_focused())";
const SCREENS = "[n for n in ('langset', 'main_menu', 'say', 'save', 'load', 'confirm') if renpy.get_screen(n)]";
const POSITION = "list(renpy.get_filename_line()) + [len(_history_list)]";
const SAVES = 'len(renpy.list_saved_games(fast=True))';
const KEYS = {ArrowUp:['ArrowUp',38], ArrowDown:['ArrowDown',40], ArrowLeft:['ArrowLeft',37], ArrowRight:['ArrowRight',39], Enter:['Enter',13], Escape:['Escape',27]};

let context, page;
const diagnostics = [];
const trace = [];
const started = Date.now();
async function open() {
  context = await chromium.launchPersistentContext(path.join(work, 'profile'), {
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
    headless: true, viewport: {width: 844, height: 390}, args: ['--enable-unsafe-swiftshader'],
  });
  await context.route(url => !url.href.startsWith(origin + '/'), route => route.abort());
  page = context.pages()[0];
  page.on('pageerror', error => diagnostics.push(error.message.slice(0, 300)));
  await page.goto(`${origin}/game/index.html`);
  await page.waitForFunction(() => typeof window.renpy_get === 'function', {}, {timeout: 180000});
}
async function get(expression) {
  return page.evaluate(e => Promise.race([window.renpy_get(e),
    new Promise((_, reject) => setTimeout(() => reject(new Error('renpy_get timeout')), 5000))]), expression);
}
async function until(expression, predicate, label, timeout = 120000) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    try { last = await get(expression); if (predicate(last)) return last; } catch { /* runtime still starting */ }
    await page.waitForTimeout(250);
  }
  throw new Error(`Timed out waiting for ${label}; last ${JSON.stringify(last)}`);
}
// Same synthetic dispatch as GameSession.sendKey (EverPlay's virtual controls).
async function key(name) {
  const [code, number] = KEYS[name];
  for (const type of ['keydown', 'keyup']) {
    await page.evaluate(([type, key, code, n]) => {
      const event = new KeyboardEvent(type, {key, code, bubbles: true, cancelable: true, keyCode: n, which: n});
      Object.defineProperty(event, 'keyCode', {get: () => n});
      Object.defineProperty(event, 'which', {get: () => n});
      (document.activeElement || document.body || document).dispatchEvent(event);
    }, [type, name, code, number]);
    await page.waitForTimeout(50);
  }
  await page.waitForTimeout(300);
}
// Move focus with arrows until a focused button carries a matching action.
// Try the expected moves first. Ren'Py's spatial navigation is not symmetric, so the
// fallback is a vertical pass, then a snake from the top entering rows from both edges.
const repeat = (move, count) => Array(count).fill(move);
async function focus(matches, label, hint = []) {
  const focused = async () => (await get(FOCUS)).some(matches);
  if (await focused()) return;
  const moves = [...hint, ...repeat('ArrowDown', 8), ...repeat('ArrowUp', 16)];
  for (let row = 0; row < 10; row++) {
    moves.push(...repeat(row % 2 ? 'ArrowLeft' : 'ArrowRight', 6), 'ArrowDown');
  }
  moves.push(...repeat('ArrowLeft', 6), ...repeat('ArrowUp', 16));
  for (const move of moves) {
    await key(move);
    if (await focused()) return;
  }
  throw new Error(`Could not focus ${label}`);
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
// One Enter may only finish the text animation; press until a new line is shown.
async function advance(from) {
  for (let attempt = 0; attempt < 20; attempt++) {
    await key('Enter');
    try {
      return await until(POSITION, p => p[2] > from[2] && (p[0] !== from[0] || p[1] !== from[1]), 'dialogue advance', 1500);
    } catch { /* still animating or between statements */ }
  }
  throw new Error('Dialogue did not advance');
}

try {
  await open();
  // First launch: the game's own language picker, then its OK button.
  await until(SCREENS, s => s.includes('langset'), 'language picker');
  await focus(([type, , , value]) => type === 'SetScreenVariable' && value === values.language, 'language button', repeat('ArrowRight', 8));
  await key('Enter');
  await focus(([type]) => type === 'Language', 'language confirmation', repeat('ArrowDown', 8));
  await key('Enter');
  await until('_preferences.language', l => l === values.language, 'language preference');
  // Title menu buttons animate in; they are only usable once focusable.
  await until(SCREENS, s => s.includes('main_menu'), 'title menu');
  await focus(([type]) => type === 'Start', 'start button', [...repeat('ArrowRight', 5), ...repeat('ArrowLeft', 5)]);
  await key('Enter');
  let position = await until(POSITION, p => p[2] >= 1, 'first dialogue', 60000);
  position = await advance(position);
  position = await advance(position);
  trace.push({event: 'before-save', position, seconds: Math.round((Date.now() - started) / 1000)});
  await page.screenshot({path: path.join(values.out, 'desktop-game-before-save.png')});

  await key('Escape');
  await until(SCREENS, s => s.includes('save'), 'save screen');
  await focus(([type]) => type === 'FileSave', 'save slot', repeat('ArrowDown', 3));
  await key('Enter');
  await until(SAVES, n => n === 1, 'save file');
  await key('Escape');
  await until(SCREENS, s => s.includes('say') && !s.includes('save'), 'return to dialogue');
  assert.deepEqual(await get(POSITION), position, 'saving changed the dialogue position');
  const saved = position;
  position = await advance(position);
  position = await advance(position);
  trace.push({event: 'progressed', position, seconds: Math.round((Date.now() - started) / 1000)});

  // Close the whole browser process, reopen with the same profile and load.
  await context.close(); context = null;
  await open();
  await until(SCREENS, s => s.includes('main_menu'), 'title menu after restart (language remembered)');
  assert.equal(await get('_preferences.language'), values.language);
  await focus(([type, , screen]) => type === 'ShowMenu' && screen === 'load', 'load menu button', [...repeat('ArrowRight', 5), ...repeat('ArrowLeft', 5)]);
  await key('Enter');
  await until(SCREENS, s => s.includes('load'), 'load screen');
  await focus(([type]) => type === 'FileLoad', 'saved slot', repeat('ArrowDown', 3));
  await key('Enter');
  position = await until(POSITION, p => same(p, saved), 'restored dialogue position', 60000);
  trace.push({event: 'restored-after-restart', position, seconds: Math.round((Date.now() - started) / 1000)});
  await page.screenshot({path: path.join(values.out, 'desktop-game-restored.png')});

  // Play on, then load the same save again from inside the running game.
  position = await advance(position);
  await key('Escape');
  await until(SCREENS, s => s.includes('save'), 'game menu');
  await focus(([type, , screen]) => type === 'ShowMenu' && screen === 'load', 'load tab', [...repeat('ArrowDown', 4), ...repeat('ArrowLeft', 12), ...repeat('ArrowUp', 8)]);
  await key('Enter');
  await until(SCREENS, s => s.includes('load'), 'load screen in game');
  await focus(([type]) => type === 'FileLoad', 'saved slot in game', [...repeat('ArrowRight', 3), ...repeat('ArrowDown', 3)]);
  await key('Enter');
  const confirm = await until(SCREENS, s => s.includes('confirm') || s.includes('say'), 'load confirmation');
  if (confirm.includes('confirm')) {
    await focus(([type]) => type === 'FileLoad' || type === 'Return' || type === 'Function', 'confirm yes');
  }
  if (confirm.includes('confirm')) await key('Enter');
  position = await until(POSITION, p => same(p, saved), 'restored dialogue position in game', 60000);
  trace.push({event: 'restored-in-game', position, seconds: Math.round((Date.now() - started) / 1000)});
  assert.deepEqual(diagnostics, [], 'Unexpected JavaScript errors');
  console.log('PASS: real desktop game data ran under EverPlay CSP with virtual keys: language, title menu, dialogue, save, browser restart, load and in-game reload.');
} catch (error) {
  if (page) await page.screenshot({path: path.join(values.out, 'desktop-game-failure.png')}).catch(() => {});
  throw error;
} finally {
  await writeFile(path.join(values.out, 'desktop-game-trace.json'), JSON.stringify({trace, diagnostics}, null, 2));
  if (context) await context.close();
  await new Promise(resolve => server.close(resolve));
  await rm(work, {recursive: true, force: true});
}
