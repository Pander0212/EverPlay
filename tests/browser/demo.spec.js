import { test, expect } from '@playwright/test';

test('touch play, Japanese dialogue, inventory, variable and save survive closing and reopening', async ({ page, context }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await expect(page.locator('[data-translate]')).toHaveText('こんばんは。小さな光を集めましょう。');
  await page.getByRole('button', { name: 'Collect a lantern', exact: true }).tap();
  await page.getByRole('button', { name: 'Collect light +10', exact: true }).tap();
  await expect(page.locator('#gold')).toHaveText('20');
  await page.getByRole('button', { name: 'Buy seed', exact: false }).tap();
  await expect(page.locator('#inventory')).toHaveText('Seeds: 1');
  await page.getByRole('button', { name: 'Next day' }).tap();
  await page.getByRole('button', { name: 'Talk / 話す', exact: true }).tap();
  await page.getByRole('button', { name: 'Save game', exact: true }).tap();
  await expect(page.locator('#saveStatus')).toHaveText('Saved on this device');
  await page.close();
  const reopened = await context.newPage();
  await reopened.goto('/');
  await expect(reopened.locator('body')).toHaveAttribute('data-ready', 'true');
  await expect(reopened.locator('#gold')).toHaveText('0');
  await expect(reopened.locator('#inventory')).toHaveText('Seeds: 1');
  await expect(reopened.locator('#day')).toHaveText('2');
  await expect(reopened.locator('#dialogue')).toHaveText('この庭には、まだ物語が眠っています。');
  expect(errors).toEqual([]);
});

test('keyboard movement and action work in landscape', async ({ page }) => {
  await page.setViewportSize({ width: 844, height: 390 });
  await page.goto('/');
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#player')).toHaveCSS('left', /px$/);
  expect(await page.locator('#player').evaluate(el => el.style.left)).toBe('55%');
  await page.keyboard.press('z');
  await expect(page.locator('#gold')).toHaveText('10');
  await expect(page.getByRole('button', { name: 'Save game' })).toBeVisible();
});

test('a malformed existing save is preserved and reported', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('everplay.lantern-garden.v1', '{bad-save'));
  await page.goto('/');
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await page.getByRole('button', { name: 'Collect light +10' }).tap();
  await expect(page.locator('#saveStatus')).toContainText('automatic saving disabled');
  expect(await page.evaluate(() => localStorage.getItem('everplay.lantern-garden.v1'))).toBe('{bad-save');
});

test('saves survive a complete browser process restart with a persistent profile', async () => {
  const { chromium } = await import('@playwright/test');
  const { mkdtemp, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const profile = await mkdtemp(join(tmpdir(), 'everplay-profile-'));
  const options = { headless: true, hasTouch: true, viewport: { width: 390, height: 844 } };
  if (process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH) options.executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
  let browser;
  try {
    browser = await chromium.launchPersistentContext(profile, options);
    let page = await browser.newPage();
    await page.goto('http://127.0.0.1:4173/');
    await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
    await page.getByRole('button', { name: 'Collect light +10' }).tap();
    await page.getByRole('button', { name: 'Save game' }).tap();
    await browser.close();
    browser = await chromium.launchPersistentContext(profile, options);
    page = await browser.newPage();
    await page.goto('http://127.0.0.1:4173/');
    await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
    await expect(page.locator('#gold')).toHaveText('10');
  } finally {
    await browser?.close();
    await rm(profile, { recursive: true, force: true });
  }
});
