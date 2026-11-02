import {test,expect} from '@playwright/test';

test.beforeEach(async({page})=>{
  await page.goto('/');
  await expect(page.locator('#catalog-status')).toHaveText('18 类标准项目 · 94 类训练打乱 · 20 种辅助求解');
  await expect(page.locator('#event')).toBeEnabled();
});

test('catalogs are visible and standard events generate, solve and support multi-blind',async({page})=>{
  await expect(page.locator('#event option')).toHaveCount(18);
  await expect(page.locator('#training-type option')).toHaveCount(94);
  await expect(page.locator('#assist-method option')).toHaveCount(20);
  await page.locator('#event').selectOption('555');
  await expect(page.locator('#event-solve')).toBeDisabled();
  await expect(page.locator('#preview-source')).toContainText('五阶');
  await page.locator('#event').selectOption('222');
  await expect(page.locator('#event-solve')).toBeEnabled();
  await page.getByRole('button',{name:'生成项目打乱',exact:true}).click();
  await expect(page.locator('#event-output pre')).not.toBeEmpty();
  await expect(page.locator('#event-solve')).toBeEnabled();
  await page.getByRole('button',{name:'求解并回放',exact:true}).click();
  await expect(page.locator('#preview-source')).toContainText('已还原');
  await page.locator('#event').selectOption('333mbld');
  await page.locator('#blind-count').fill('2');
  await page.getByRole('button',{name:'生成项目打乱',exact:true}).click();
  await expect(page.locator('#event-output pre')).toHaveCount(2);
  await page.getByRole('button',{name:'查看第 2 个',exact:true}).click();
  await expect(page.locator('#preview-source')).toContainText('第 2 个');
  await expect(page.locator('#workbench-error')).toBeEmpty();
});

test('training supports filtering, selected cases, weights, orientation and subgroup generation',async({page})=>{
  await page.locator('#training-event').selectOption('333');
  await expect(page.locator('#training-type')).toBeEnabled();
  await page.locator('#training-type').selectOption('333.pll');
  await expect(page.locator('#training-cases')).toBeEnabled();
  const caseId=await page.locator('#training-cases option').last().getAttribute('value');
  await page.locator('#training-cases').selectOption(caseId!);
  await page.locator('#natural').check();
  await page.locator('#bottom-color').selectOption('white');
  await page.locator('#front-color').selectOption('green');
  await page.getByRole('button',{name:'生成训练打乱',exact:true}).click();
  await expect(page.locator('#training-output')).toContainText(`案例 ${caseId}`);
  await expect(page.locator('#training-output')).toContainText('底面 white / 正面 green');
  await expect(page.locator('#preview-source')).toContainText('训练 333.pll');
  await expect(page.locator('#training-generate')).toBeEnabled();
  await page.locator('#training-event').selectOption('minx');
  await expect(page.locator('#training-type')).toBeEnabled();
  await page.locator('#training-type').selectOption('minx.s2l');
  await expect(page.locator('#training-cases')).toBeDisabled();
  await expect(page.locator('#bottom-field')).toBeHidden();
  await page.getByRole('button',{name:'生成训练打乱',exact:true}).click();
  await expect(page.locator('#preview-source')).toContainText('训练 minx.s2l');
  await expect(page.locator('#event-net svg')).toHaveCount(1);
  await expect(page.locator('#workbench-error')).toBeEmpty();
});

test('assist returns actual target solutions, previews stages and recovers from invalid targets',async({page})=>{
  await page.locator('#assist-targets').fill('D');
  await page.locator('#assist-depth').fill('12');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#assist-output tbody tr')).toHaveCount(1);
  await page.getByRole('button',{name:'预览结果',exact:true}).click();
  await expect(page.locator('#preview-source')).toContainText('cross');
  await page.locator('#assist-method').selectOption('roux-s2');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#assist-output tbody tr')).toHaveCount(2);
  await page.getByRole('button',{name:'预览结果',exact:true}).last().click();
  await expect(page.locator('#preview-source')).toContainText('roux-s2');
  await page.locator('#assist-method').selectOption('sq1-shape-twist');
  await page.locator('#assist-depth').fill('');
  await page.locator('#assist-targets').fill('bad-target');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#workbench-error')).toContainText('target');
  await page.locator('#assist-targets').fill('');
  await page.getByRole('button',{name:'运行辅助求解',exact:true}).click();
  await expect(page.locator('#assist-output tbody tr')).toHaveCount(1);
  await expect(page.locator('#workbench-error')).toBeEmpty();
});

test('mobile view can play, pause and seek the captured algorithm',async({page})=>{
  await page.setViewportSize({width:390,height:820});
  await page.locator('#event').selectOption('sq1');
  await expect(page.locator('#preview-source')).toContainText('Square-1');
  await page.locator('#event-algorithm').fill('(1,0) /');
  await page.getByRole('button',{name:'查看图与动画',exact:true}).click();
  await expect(page.locator('#event-status')).toHaveText('0/2');
  await page.locator('#play').click();
  await expect(page.locator('#move-label')).not.toContainText('0%');
  await page.locator('#play').click();
  await expect(page.locator('#play')).toHaveText('播放');
  await page.locator('#seek').fill('1000');
  await expect(page.locator('#event-status')).toHaveText('2/2');
  await page.locator('#event-algorithm').fill('not applied');
  await page.locator('#restart').click();
  await expect(page.locator('#event-status')).toHaveText('0/2');
  await expect(page.locator('#workbench-error')).toBeEmpty();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
