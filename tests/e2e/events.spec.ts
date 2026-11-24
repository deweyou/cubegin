import {test,expect} from '@playwright/test';
import {selectOption} from './playground-controls';
const cases=[['222','R U F'],['333',"M E S Rw x y2"],['444','Rw U 3Fw'],['555','3Rw U M'],['666','3Rw U 4Fw'],['777','M 3Rw U'],['pyram',"R U l b'"],['skewb','R U B'],['minx',"R++ D-- U R F2'"],['fto','U R BL BR'],['sq1','(1,0) / (0,3) /'],['clock','UR3+ y2 U2- z R1+ x2 ALL5+']];
test('all puzzle nets and animated SVG frames use the Worker SDK',async({page})=>{
 test.setTimeout(90000);
 await page.setViewportSize({width:1080,height:1200});await page.goto('/playground/');
 const values=[];
 const eventSelect=page.locator('#event');
 const progress=page.getByRole('slider',{name:'动画进度'});
 const track=page.locator('[data-slot="slider-track"]');
 const player=page.locator('#player-frame');
 for(const [event,algorithm] of cases) {
  await selectOption(page,'event',event);
  await expect(eventSelect).toBeEnabled();
  await page.getByLabel('项目公式',{exact:true}).fill(algorithm);
  await page.getByRole('button',{name:'查看图与动画',exact:true}).click();
  await expect(eventSelect).toBeEnabled();
  await expect(page.locator('#workbench-error')).toHaveCount(0);
  const net=await page.locator('#event-net').innerHTML();
  const start=await player.innerHTML();
  await track.scrollIntoViewIfNeeded();
  const trackBox=await track.boundingBox();
  expect(trackBox).not.toBeNull();
  await page.mouse.click(trackBox!.x+trackBox!.width/2,trackBox!.y+trackBox!.height/2);
  const current=Number(await progress.getAttribute('aria-valuenow'));
  for(let remaining=Math.abs(current-500);remaining>0;remaining--) {
   await progress.press(current<500?'ArrowRight':'ArrowLeft');
  }
  await expect(progress).toHaveAttribute('aria-valuenow','500');
  await expect.poll(()=>player.innerHTML()).not.toEqual(start);
  const middle=await player.innerHTML();
  const total=(await page.locator('#event-status').textContent())?.split('/')[1];
  expect(Number(total)).toBeGreaterThan(0);
  await progress.press('End');
  await expect(page.locator('#event-status')).toHaveText(`${total}/${total}`);
  const end=await player.innerHTML();
  values.push({event,net,start,middle,end});
 }
 await page.setContent('<style>body{margin:0;font:14px system-ui;background:#f4f6f7}#grid{display:grid;grid-template-columns:repeat(4,250px);gap:8px;padding:12px}.cell{background:white;text-align:center}svg{display:block;width:250px;height:250px}</style><div id="grid"></div>');
 for(const mode of ['net','start','middle','end'] as const){
  await page.locator('#grid').evaluate((grid,{values,mode})=>{grid.replaceChildren();for(const value of values){const cell=document.createElement('div');cell.className='cell';cell.innerHTML=`<p>${value.event}</p>${value[mode]}`;grid.append(cell);}},{values,mode});
  await expect(page.locator('#grid svg')).toHaveCount(12);
  await expect(page.locator('#grid')).toHaveScreenshot(`all-events-${mode}.png`);
 }
});
test('seeking updates the actual consumer and preserves small viewport layout',async({page})=>{
 await page.setViewportSize({width:390,height:820});await page.goto('/playground/');await expect(page.locator('#event')).toBeEnabled();
 await selectOption(page,'event','sq1');await page.getByLabel('项目公式',{exact:true}).fill('(1,0) /');await page.getByRole('button',{name:'查看图与动画',exact:true}).click();
 await expect(page.locator('#event-status')).toHaveText('0/2');const initial=await page.locator('#player-frame').innerHTML();await page.getByRole('slider',{name:'动画进度'}).press('End');
 await expect(page.locator('#event-status')).toHaveText('2/2');expect(await page.locator('#player-frame').innerHTML()).not.toEqual(initial);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
