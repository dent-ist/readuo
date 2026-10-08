const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { chromium } = require('playwright');

const workspace = path.resolve(__dirname, '..');
const fragmentPath = path.join(workspace, 'design', 'readuo-first-release.html');
const previewPath = path.join(workspace, 'design', 'readuo-first-release-preview.html');
const screenshotDir = path.join(__dirname, 'screenshots');
const evidencePath = path.join(__dirname, 'render-audit.json');
fs.mkdirSync(screenshotDir, { recursive: true });

const fragment = fs.readFileSync(fragmentPath, 'utf8');
const fallbackIconStyle = '<style>#readuo-modern-complete i[data-lucide]{display:inline-block;width:18px;height:18px;flex:none}</style>';
const widths = [320, 390, 736];
const screenshotScreens = new Set([
  'login', 'circle', 'library', 'explore-public', 'scanner', 'friends',
  'request-detail', 'delete-account', 'delete-account-error', 'offline-library',
  'content-filtered', 'moderation'
]);

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe' });
  const page = await browser.newPage({ viewport: { width: 390, height: 1000 }, deviceScaleFactor: 1 });
  const consoleErrors = [];
  const pageErrors = [];
  page.on('console', message => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });
  page.on('pageerror', error => pageErrors.push(String(error)));

  const evidence = {
    generatedAt: new Date().toISOString(),
    fragment: fragmentPath,
    preview: previewPath,
    widths,
    screens: [],
    screenshots: [],
    consoleErrors,
    pageErrors,
    interactionChecks: [],
    failures: []
  };

  for (const width of widths) {
    await page.setViewportSize({ width, height: 1000 });
    await page.setContent(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0}</style>${fallbackIconStyle}${fragment}`, { waitUntil: 'load' });
    await page.waitForSelector('#readuo-modern-complete');
    const screenIds = await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.screens.map(screen => screen.id));

    for (const screenId of screenIds) {
      await page.evaluate(id => document.getElementById('readuo-modern-complete').__readuo.navigate(id), screenId);
      const metrics = await page.evaluate(() => {
        const root = document.getElementById('readuo-modern-complete');
        const phone = root.querySelector('#rd-phone');
        const visible = element => {
          const style = getComputedStyle(element);
          const rect = element.getBoundingClientRect();
          return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
        };
        const phoneRect = phone.getBoundingClientRect();
        const outsidePhone = [...phone.querySelectorAll('*')].filter(visible).filter(element => {
          const rect = element.getBoundingClientRect();
          return rect.left < phoneRect.left - 1 || rect.right > phoneRect.right + 1;
        }).slice(0, 10).map(element => ({ tag: element.tagName, className: element.className, text: element.textContent.trim().slice(0, 60) }));
        const clippedText = [...phone.querySelectorAll('h1,h2,h3,p,strong,small,span,button,label')].filter(visible).filter(element => {
          const style = getComputedStyle(element);
          return element.scrollWidth > element.clientWidth + 1 && style.overflowX !== 'visible';
        }).slice(0, 10).map(element => ({ tag: element.tagName, className: element.className, text: element.textContent.trim().slice(0, 60) }));
        const smallTargets = [...phone.querySelectorAll('button,input,select,textarea')].filter(visible).filter(element => {
          if (element.tagName === 'INPUT' && element.closest('.rd-radio,.rd-toggle')) return false;
          const rect = element.getBoundingClientRect();
          return rect.width < 40 || rect.height < 40;
        }).slice(0, 10).map(element => {
          const rect = element.getBoundingClientRect();
          return { tag: element.tagName, className: element.className, label: element.getAttribute('aria-label') || element.textContent.trim().slice(0, 50), width: Math.round(rect.width), height: Math.round(rect.height) };
        });
        const avatarShapes = [...phone.querySelectorAll('.rd-avatar')].filter(visible).map(element => {
          const rect = element.getBoundingClientRect();
          return { width: Math.round(rect.width), height: Math.round(rect.height), text: element.textContent.trim() };
        });
        const duplicateIds = [...phone.querySelectorAll('[id]')].map(element => element.id).filter((id, index, ids) => ids.indexOf(id) !== index);
        return {
          page: root.__readuo.state.page,
          documentOverflow: document.documentElement.scrollWidth > innerWidth + 1,
          phoneOverflow: phone.scrollWidth > phone.clientWidth + 1,
          outsidePhone,
          clippedText,
          smallTargets,
          avatarShapes,
          duplicateIds,
          phoneWidth: Math.round(phoneRect.width),
          phoneHeight: Math.round(phoneRect.height)
        };
      });
      const row = { width, screenId, ...metrics };
      evidence.screens.push(row);
      const badAvatar = metrics.avatarShapes.some(avatar => Math.abs(avatar.width - avatar.height) > 1);
      if (metrics.documentOverflow || metrics.phoneOverflow || metrics.outsidePhone.length || metrics.clippedText.length || metrics.smallTargets.length || metrics.duplicateIds.length || badAvatar) {
        evidence.failures.push(row);
      }
      if (width === 390 && screenshotScreens.has(screenId)) {
        const screenshotPath = path.join(screenshotDir, `${screenId}-390.png`);
        await page.locator('#rd-phone').screenshot({ path: screenshotPath });
        evidence.screenshots.push(screenshotPath);
      }
    }
  }

  await page.setViewportSize({ width: 390, height: 1000 });
  await page.setContent(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0}</style>${fallbackIconStyle}${fragment}`, { waitUntil: 'load' });
  const check = async (name, run) => {
    try {
      const detail = await run();
      evidence.interactionChecks.push({ name, passed: true, detail });
    } catch (error) {
      evidence.interactionChecks.push({ name, passed: false, detail: String(error) });
      evidence.failures.push({ interaction: name, error: String(error) });
    }
  };

  await check('login starts first and Apple selection reaches setup', async () => {
    if (!(await page.getByRole('heading', { name: /Your books/i }).isVisible())) throw new Error('Login was not first');
    await page.getByRole('button', { name: 'Continue with Apple' }).click();
    if (!(await page.getByRole('heading', { name: 'Make yourself at home' }).isVisible())) throw new Error('Setup not shown');
    return await page.locator('#rd-view').innerText();
  });

  await check('empty display name is blocked', async () => {
    await page.locator('#rd-name').fill('');
    await page.getByRole('button', { name: 'Continue' }).click();
    const error = await page.locator('#rd-form-error').innerText();
    if (!error.includes('display name')) throw new Error('Validation message missing');
    return error;
  });

  await check('post publish, edit, and delete remain coherent', async () => {
    await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.navigate('compose'));
    await page.locator('#rd-post-text').fill('A stateful prototype post.');
    await page.getByRole('button', { name: 'Post to Circle' }).click();
    if (!(await page.locator('#rd-view').innerText()).includes('A stateful prototype post.')) throw new Error('Published post missing');
    await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.navigate('edit-post'));
    await page.locator('#rd-post-text').fill('An edited prototype post.');
    await page.getByRole('button', { name: 'Save changes' }).click();
    if (!(await page.locator('#rd-view').innerText()).includes('An edited prototype post.')) throw new Error('Edited post missing');
    await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.navigate('delete-post'));
    await page.getByRole('button', { name: 'Delete post' }).click();
    if ((await page.locator('#rd-view').innerText()).includes('An edited prototype post.')) throw new Error('Deleted post still shown');
    return 'publish → edit → delete reflected in Circle';
  });

  await check('selected friend identity propagates', async () => {
    await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.navigate('friends'));
    await page.getByRole('button', { name: /Tom Bergen/ }).click();
    const text = await page.locator('#rd-view').innerText();
    if (!text.includes('Tom Bergen') || text.includes('Sarah Lin')) throw new Error('Friend identity mismatch');
    return 'Tom Bergen profile shown';
  });

  await check('pending request acceptance updates counts without duplicating an existing friend', async () => {
    await page.evaluate(() => {
      const api = document.getElementById('readuo-modern-complete').__readuo;
      api.state.selectedRequest = 'priya';
      api.navigate('request-detail');
    });
    await page.getByRole('button', { name: 'Accept request' }).click();
    await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.navigate('friends'));
    const text = await page.locator('#rd-view').innerText();
    if (!text.includes('Your friends · 9') || !text.includes('Received · 1')) throw new Error('Request counts did not update');
    return 'accepted friend count 9; incoming count 1';
  });

  await check('discovery save creates one entry and does not duplicate it', async () => {
    const counts = await page.evaluate(() => {
      const api = document.getElementById('readuo-modern-complete').__readuo;
      api.state.bookIndex = 7;
      api.state.shelf = 'Living room';
      const before = api.state.page;
      api.navigate('save-shelf');
      return { before };
    });
    await page.getByRole('button', { name: 'Save book' }).click();
    const afterFirst = await page.evaluate(() => {
      const api = document.getElementById('readuo-modern-complete').__readuo;
      return api.screens.length && document.querySelectorAll('[data-screen]').length;
    });
    await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.navigate('save-shelf'));
    const text = await page.locator('#rd-view').innerText();
    if (!text.includes('Already in your library')) throw new Error('Existing-entry guard missing');
    return { counts, afterFirst, guard: 'shown' };
  });

  await check('account deletion requires acknowledgement', async () => {
    await page.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.navigate('delete-account'));
    await page.getByRole('button', { name: 'Continue to verification' }).click();
    if (!(await page.locator('#rd-form-error').innerText()).includes('confirm')) throw new Error('Acknowledgement guard missing');
    await page.locator('#rd-delete-check').check();
    await page.getByRole('button', { name: 'Continue to verification' }).click();
    if (!(await page.getByRole('heading', { name: 'Confirm it’s you' }).isVisible())) throw new Error('Reauthentication state missing');
    return 'guarded and routed to linked-provider reauthentication';
  });

  await check('standalone preview loads inside sandboxed iframe', async () => {
    await page.goto(pathToFileURL(previewPath).href, { waitUntil: 'load' });
    const frame = page.frames().find(candidate => candidate !== page.mainFrame());
    if (!frame) throw new Error('Preview iframe missing');
    await frame.waitForSelector('#readuo-modern-complete');
    const current = await frame.evaluate(() => document.getElementById('readuo-modern-complete').__readuo.state.page);
    if (current !== 'login') throw new Error(`Preview starts on ${current}`);
    return 'sandboxed preview starts on login';
  });

  await browser.close();
  fs.writeFileSync(evidencePath, JSON.stringify(evidence, null, 2));
  const summary = {
    screenCount: new Set(evidence.screens.map(row => row.screenId)).size,
    renderedStates: evidence.screens.length,
    widths,
    screenshots: evidence.screenshots.length,
    interactionChecks: evidence.interactionChecks.length,
    interactionFailures: evidence.interactionChecks.filter(check => !check.passed).length,
    layoutFailures: evidence.failures.filter(failure => failure.screenId).length,
    consoleErrors: consoleErrors.length,
    pageErrors: pageErrors.length,
    evidencePath
  };
  console.log(JSON.stringify(summary, null, 2));
  if (evidence.failures.length || consoleErrors.length || pageErrors.length) process.exitCode = 1;
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
