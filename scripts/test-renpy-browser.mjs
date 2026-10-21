// Test the generated desktop-data fixture under EverPlay's current CSP.
// This browser server is only a harness; native CI tests the production server.
import { chromium } from 'playwright';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const work = await mkdtemp(path.join(tmpdir(), 'everplay-renpy-'));
const root = path.join(work, 'web');
execFileSync('python3', ['-m', 'zipfile', '-e', 'App/Resources/EverPlayRenPyProbe.zip', root]);
const router = await readFile('Sources/EverPlayCore/HTTPResourceRouter.swift', 'utf8');
const policy = router.match(/"Content-Security-Policy": "([^"]+)"/)[1];
const mime = {'.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.jpg':'image/jpeg'};
const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://localhost');
    if (!url.pathname.startsWith('/probe/')) throw new Error('Wrong prefix');
    const file = path.resolve(root, decodeURIComponent(url.pathname.slice('/probe/'.length)) || 'index.html');
    if (!file.startsWith(root + path.sep)) throw new Error('Outside fixture');
    const data = await readFile(file);
    response.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Content-Security-Policy': policy, 'Cache-Control':'no-store'});
    response.end(data);
  } catch { response.writeHead(404); response.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}/probe/index.html`;
let context;
let currentPage;
const consoleMessages = [];
const diagnostics = [];
async function open() {
  context = await chromium.launchPersistentContext(path.join(work, 'profile'), {
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
    headless: true, viewport: {width:800, height:600}, args:['--enable-unsafe-swiftshader'],
  });
  const page = context.pages()[0];
  currentPage = page;
  page.on("console", message => consoleMessages.push(message.text().slice(0, 1000)));
  page.on('pageerror', error => diagnostics.push(error.message));
  await page.goto(url);
  await page.waitForFunction(() => window.everplayProbe?.ready, {}, {timeout:120000});
  return page;
}
try {
  let page = await open();
  assert.equal(await page.evaluate(() => window.everplayProbe.gold), 10);
  await page.mouse.click(110,250);
  await page.waitForFunction(() => window.everplayProbe.gold === 20);
  await page.mouse.click(110,315);
  await page.waitForFunction(() => window.everplayProbe.route === 'garden');
  await page.mouse.click(110,385);
  await page.waitForFunction(() => window.everplayProbe.saved === true);
  await page.mouse.click(110,250);
  await page.waitForFunction(() => window.everplayProbe.gold === 30);
  await page.mouse.click(110,455);
  await page.waitForFunction(() => window.everplayProbe.gold === 20 && window.everplayProbe.route === 'garden');
  await page.screenshot({path:'artifacts/renpy-desktop-data-browser.png'});
  await context.close(); context = null;
  page = await open();
  await page.waitForFunction(() => window.everplayProbe.saved === true);
  await page.mouse.click(110,455);
  await page.waitForFunction(() => window.everplayProbe.gold === 20 && window.everplayProbe.route === 'garden');
  assert.deepEqual(diagnostics, [], 'Unexpected JavaScript errors');
  console.log('PASS: archived desktop scripts render, respond to clicks, select a route, save/load and restore after browser-process restart under EverPlay CSP.');
} catch (error) {
  if (currentPage) await currentPage.screenshot({path:"artifacts/renpy-browser-failure.png"}).catch(() => {});
  throw error;
} finally {
  await writeFile("artifacts/renpy-browser-console.json", JSON.stringify(consoleMessages, null, 2));
  if (context) await context.close();
  await new Promise(resolve => server.close(resolve));
  await writeFile('artifacts/renpy-browser-errors.json', JSON.stringify(diagnostics));
  await rm(work, {recursive:true, force:true});
}
