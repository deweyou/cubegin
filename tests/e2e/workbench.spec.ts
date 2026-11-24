import {test,expect} from '@playwright/test';
import {selectOption,countOptions} from './playground-controls';

test.beforeEach(async({page})=>{
  await page.goto('/playground/');
  await expect(page.locator('#event')).toBeEnabled();
});

test('catalogs are visible and standard events generate, solve and support multi-blind',async({page})=>{
  expect(await countOptions(page,'event')).toBe(18);
  await selectOption(page,'event','555');
  await expect(page.locator('#event-solve')).toBeDisabled();
  await expect(page.locator('#preview-source')).toContainText('五阶');
  await selectOption(page,'event','222');
  await expect(page.locator('#event-solve')).toBeEnabled();
  await page.getByRole('button',{name:'生成项目打乱',exact:true}).click();
  await expect(page.locator('#playground-output code')).not.toBeEmpty();
  await expect(page.locator('#event-solve')).toBeEnabled();
  await page.getByRole('button',{name:'求解并回放',exact:true}).click();
  await expect(page.locator('#preview-source')).toContainText('已还原');
  await selectOption(page,'event','333mbld');
  await page.getByRole('button',{name:'高级选项',exact:true}).click();
  await page.locator('#blind-count').fill('2');
  await page.getByRole('button',{name:'生成项目打乱',exact:true}).click();
  await expect(page.locator('#playground-output code')).toHaveCount(2);
  await page.getByRole('button',{name:'预览结果',exact:true}).nth(1).click();
  await expect(page.locator('#preview-source')).toContainText('第 2 个');
  await expect(page.locator('#workbench-error')).toHaveCount(0);
});

test('training supports filtering, selected cases, weights, orientation and subgroup generation',async({page})=>{
  await page.getByRole('tab',{name:'训练打乱'}).click();
  expect(await countOptions(page,'training-type')).toBe(94);
  await selectOption(page,'training-event','333');
  await expect(page.locator('#training-type')).toBeEnabled();
  await selectOption(page,'training-type','333.pll');
  await expect(page.locator('#training-cases')).toBeEnabled();
  await page.locator('#training-cases').click();
  const cases=page.getByRole('option');
  const caseId=await cases.last().getAttribute('data-option');
  await cases.first().click();
  await cases.last().click();
  await expect(cases.first()).toHaveAttribute('aria-selected','true');
  await expect(cases.last()).toHaveAttribute('aria-selected','true');
  await page.keyboard.press('Escape');
  await expect(page.locator('#training-cases')).toHaveText('已选 2 项');
  await page.getByRole('button',{name:'清除',exact:true}).click();
  await expect(page.locator('#training-cases')).toHaveText('全部案例');
  await selectOption(page,'training-cases',caseId!);
  await page.keyboard.press('Escape');
  await page.getByRole('button',{name:'高级选项',exact:true}).click();
  await page.locator('#natural').check();
  await selectOption(page,'bottom-color','white');
  await selectOption(page,'front-color','green');
  await page.getByRole('button',{name:'生成训练打乱',exact:true}).click();
  await expect(page.locator('#playground-output')).toContainText(`案例 ${caseId}`);
  await expect(page.locator('#playground-output')).toContainText('底面 white / 正面 green');
  await expect(page.locator('#preview-source')).toContainText('333.pll');
  await expect(page.locator('#training-generate')).toBeEnabled();
  await selectOption(page,'training-event','minx');
  await expect(page.locator('#training-type')).toBeEnabled();
  await selectOption(page,'training-type','minx.s2l');
  await expect(page.locator('#training-cases')).toBeDisabled();
  await expect(page.locator('#bottom-color')).toBeHidden();
  await page.getByRole('button',{name:'生成训练打乱',exact:true}).click();
  await expect(page.locator('#preview-source')).toContainText('minx.s2l');
  await expect(page.locator('#event-net svg')).toHaveCount(1);
  await expect(page.locator('#workbench-error')).toHaveCount(0);
});

test('assist returns actual target solutions, previews stages and recovers from invalid targets',async({page})=>{
  await page.getByRole('tab',{name:'辅助求解'}).click();
  expect(await countOptions(page,'assist-method')).toBe(20);
  await page.getByRole('button',{name:'高级选项',exact:true}).click();
  await page.locator('#assist-targets').fill('D');
  await page.locator('#assist-depth').fill('12');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#playground-output article')).toHaveCount(1);
  await page.getByRole('button',{name:'预览结果',exact:true}).click();
  await expect(page.locator('#preview-source')).toContainText('D');
  await selectOption(page,'assist-method','roux-s2');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#playground-output article')).toHaveCount(2);
  await page.getByRole('button',{name:'预览结果',exact:true}).last().click();
  await expect(page.locator('#preview-source')).toContainText('·');
  await selectOption(page,'assist-method','sq1-shape-twist');
  await page.locator('#assist-depth').fill('');
  await page.locator('#assist-targets').fill('bad-target');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#workbench-error')).toContainText('target');
  await page.locator('#assist-targets').fill('');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#playground-output article')).toHaveCount(1);
  await expect(page.locator('#workbench-error')).toHaveCount(0);
});

test('mobile view can play, pause and seek the captured algorithm',async({page})=>{
  await page.setViewportSize({width:390,height:820});
  await selectOption(page,'event','sq1');
  await expect(page.locator('#preview-source')).toContainText('Square-1');
  await page.locator('#event-algorithm').fill('(1,0) /');
  await page.getByRole('button',{name:'查看图与动画',exact:true}).click();
  await expect(page.locator('#event-status')).toHaveText('0/2');
  await page.getByRole('combobox',{name:'播放速度'}).click();
  await page.getByRole('option',{name:'0.5×',exact:true}).click();
  await expect(page.getByRole('combobox',{name:'播放速度'})).toHaveText('0.5×');
  await page.locator('#play').click();
  await expect.poll(async()=>Number(await page.getByRole('slider').getAttribute('aria-valuenow'))).toBeGreaterThan(0);
  await page.locator('#play').click();
  await expect(page.locator('#play')).toHaveText('播放');
  await page.getByRole('slider',{name:'动画进度'}).press('End');
  await expect(page.locator('#event-status')).toHaveText('2/2');
  await page.locator('#event-algorithm').fill('not applied');
  await page.locator('#restart').click();
  await expect(page.locator('#event-status')).toHaveText('0/2');
  await expect(page.locator('#workbench-error')).toHaveCount(0);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

test('site navigation opens the localized playground and generated algorithms can be copied',async({page,context})=>{
  await context.grantPermissions(['clipboard-read','clipboard-write']);
  await page.setViewportSize({width:320,height:720});
  await page.goto('/en/');
  const nav=page.getByRole('navigation');
  await expect(nav.getByRole('link')).toHaveText(['Home','Playground']);
  await expect(nav.getByRole('link',{name:'Home',exact:true})).toHaveAttribute('aria-current','page');
  await page.getByRole('link',{name:'Playground',exact:true}).click();
  await expect(page).toHaveURL(/\/en\/playground\/?$/);
  await page.getByRole('link',{name:'Cubegin',exact:true}).click();
  await expect(page).toHaveURL(/\/en\/?$/);
  await nav.getByRole('link',{name:'Playground',exact:true}).click();
  await expect(nav.getByRole('link',{name:'Playground',exact:true})).toHaveAttribute('aria-current','page');
  await expect(page.locator('.playground-heading').getByRole('heading')).toHaveText('Cubegin SDK Playground');
  await expect(page.locator('.sdk-version')).toHaveText(/^v\d/);
  await page.getByRole('button',{name:'Generate scramble'}).click();
  const result=page.locator('#playground-output code');
  await expect(result).not.toBeEmpty();
  await page.getByRole('button',{name:'Copy algorithm'}).click();
  await expect(page.getByRole('button',{name:'Copied'})).toBeVisible();
  expect(await page.evaluate(()=>navigator.clipboard.readText())).toEqual(await result.textContent());
  await page.getByRole('link',{name:'Switch to Simplified Chinese'}).click();
  await expect.poll(() => new URL(page.url()).pathname).toMatch(/^\/playground\/?$/);
  await expect(page.getByRole('tab',{name:'标准打乱'})).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await expect(nav.getByRole('link')).toHaveText(['首页','调试台']);
  await expect(nav.getByRole('link',{name:'调试台',exact:true})).toHaveAttribute('aria-current','page');
  await nav.getByRole('link',{name:'首页',exact:true}).click();
  await expect(page).toHaveURL(/^http:\/\/[^/]+\/$/);
});

test('playback completes when the first animation frame timestamp precedes the click', async ({ page }) => {
  await page.getByRole('button', { name: '高级选项' }).click();
  await page.locator('#event-seed').fill('924946762');
  await page.getByRole('button', { name: '生成项目打乱' }).click();
  await expect(page.locator('#event-status')).toHaveText('0/21');
  await page.getByRole('combobox', { name: '播放速度' }).click();
  await page.getByRole('option', { name: '2×', exact: true }).click();
  await page.locator('#play').evaluate((button: HTMLButtonElement) => {
    const requestFrame = window.requestAnimationFrame;
    const firstTimestamp = performance.now() - 50;
    window.requestAnimationFrame = callback => requestFrame(() => callback(firstTimestamp));
    try {
      button.click();
    } finally {
      window.requestAnimationFrame = requestFrame;
    }
  });
  await expect(page.locator('#event-status')).toHaveText('21/21', { timeout: 10000 });
  await expect(page.getByRole('button', { name: '播放', exact: true })).toBeVisible();
  await expect(page.locator('#workbench-error')).toHaveCount(0);
});

test('mouse drag rotates the camera while preserving the current replay frame', async ({ page }) => {
  await page.getByRole('button', { name: '下一步', exact: true }).click();
  await expect(page.locator('#event-status')).toHaveText('1/4');
  const surface = page.locator('#player-frame');
  const defaultView = await surface.innerHTML();
  const net = await page.locator('#event-net').innerHTML();
  const progress = await page.getByRole('slider').getAttribute('aria-valuenow');
  const box = await surface.boundingBox();
  if (!box) throw new Error('Missing animation surface');
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width + 15, box.y + box.height / 2 + 35, { steps: 5 });
  await page.mouse.up();

  await expect.poll(() => surface.innerHTML()).not.toBe(defaultView);
  await expect(page.locator('#event-status')).toHaveText('1/4');
  await expect(page.getByRole('slider')).toHaveAttribute('aria-valuenow', progress!);
  expect(await page.locator('#event-net').innerHTML()).toBe(net);

  await page.getByRole('button', { name: '重置视角', exact: true }).click();
  await expect.poll(() => surface.innerHTML()).toBe(defaultView);
  await expect(page.locator('#workbench-error')).toHaveCount(0);
});

test('training configuration survives sharing, language switching and tab history', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.getByRole('tab', { name: '训练打乱' }).click();
  await expect(page).toHaveURL(/mode=training/);
  await page.reload();
  await expect(page.getByRole('tab', { name: '训练打乱' })).toHaveAttribute('aria-selected', 'true');
  await page.locator('#training-cases').click();
  const option = page.getByRole('option').first();
  const selected = await option.getAttribute('data-option');
  await option.click();
  await page.keyboard.press('Escape');
  await expect.poll(() => new URL(page.url()).searchParams.getAll('case')).toEqual([selected]);
  await page.getByRole('button', { name: '复制配置链接' }).click();
  const url = await page.evaluate(() => navigator.clipboard.readText());
  expect(new URL(url).searchParams.getAll('case')).toEqual([selected]);
  await page.goto(url);
  await expect(page.locator('#training-cases')).toHaveText('已选 1 项');
  await page.getByRole('link', { name: '切换到英文' }).click();
  await expect(page.locator('#training-cases')).toHaveText('1 selected');
  await page.getByRole('tab', { name: 'Solve assist' }).click();
  await expect(page).toHaveURL(/mode=assist/);
  await page.goBack();
  await expect(page.locator('#training-cases')).toHaveText('1 selected');
  await page.goForward();
  await expect(page.getByRole('tab', { name: 'Solve assist' })).toHaveAttribute('aria-selected', 'true');
});

test('assist replay links restore the selected solution and paused move separately from input', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/playground/?mode=assist&method=cross&input=R+U+F&targets=D');
  await page.getByRole('button', { name: '运行辅助求解' }).click();
  await expect(page.locator('#playground-output article')).toHaveCount(1);
  await page.getByRole('button', { name: '下一步' }).click();
  await expect(page.locator('#event-status')).toHaveText(/^1\//);
  const status = await page.locator('#event-status').textContent();
  const svg = await page.locator('#player-frame').innerHTML();
  await page.getByRole('button', { name: '复制回放链接' }).click();
  const url = await page.evaluate(() => navigator.clipboard.readText());
  await expect.poll(() => new URL(page.url()).searchParams.toString()).toBe(new URL(url).searchParams.toString());
  const params = new URL(url).searchParams;
  expect(params.get('input')).toBe('R U F');
  expect(params.get('alg')).not.toBe(params.get('input'));
  expect(params.get('step')).toBe('1');
  await page.goto(url);
  await expect(page.locator('#event-status')).toHaveText(status!);
  await expect(page.getByRole('button', { name: '播放', exact: true })).toBeVisible();
  expect(await page.locator('#player-frame').innerHTML()).toBe(svg);
  await expect(page.locator('#workbench-error')).toHaveCount(0);
});

test('address follows standard edits, replay and history without adding an entry for each move', async ({ page }) => {
  const historySize = await page.evaluate(() => history.length);
  await selectOption(page, 'event', 'sq1');
  await expect.poll(() => new URL(page.url()).searchParams.get('event')).toBe('sq1');
  await page.locator('#event-algorithm').fill('(1,0) /');
  await expect.poll(() => new URL(page.url()).searchParams.get('input')).toBe('(1,0) /');
  await page.locator('#event-apply').click();
  await page.getByRole('button', { name: '播放', exact: true }).click();
  await expect.poll(() => new URL(page.url()).searchParams.get('step')).toBe('2');
  expect(new URL(page.url()).searchParams.get('alg')).toBe('(1,0) /');
  expect(await page.evaluate(() => history.length)).toBe(historySize);
  await page.reload();
  await expect(page.locator('#event-status')).toHaveText('2/2');
  await page.getByRole('tab', { name: '训练打乱' }).click();
  await expect(page).toHaveURL(/mode=training/);
  await page.goBack();
  await expect(page.getByRole('tab', { name: '标准打乱' })).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('#event-status')).toHaveText('2/2');
});
