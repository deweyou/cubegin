import {test,expect} from '@playwright/test';
const cases=[['222','R U F'],['333',"M E S Rw x y2"],['444','Rw U 3Fw'],['555','3Rw U M'],['666','3Rw U 4Fw'],['777','M 3Rw U'],['pyram',"R U l b'"],['skewb','R U B'],['minx',"R++ D-- U R F2'"],['fto','U R BL BR'],['sq1','(1,0) / (0,3) /'],['clock','UR3+ y2 U2- z R1+ x2 ALL5+']];
test('all puzzle nets and animated SVG frames use the Worker SDK',async({page})=>{
 await page.setViewportSize({width:1080,height:1200});await page.goto('/');
 const values=await page.evaluate(async(cases)=>{
  const {createWorkerClient}=await import('/capability-worker.js');
  const client=createWorkerClient();try{return await Promise.all(cases.map(async([event,algorithm])=>{
   const net=await client.engine.evaluateEvent(event,algorithm);const t=await client.engine.playerTimeline(event,algorithm);const index=Math.floor(t.steps.length/2);
   const start=await client.engine.playerSvg(event,algorithm,0,0);const middle=await client.engine.playerSvg(event,algorithm,index,.5);const end=await client.engine.playerSvg(event,algorithm,t.steps.length,0);
   return {event,net:net.svg,start,middle,end};
  }));}finally{client.dispose();}
 },cases);
 await page.setContent('<style>body{margin:0;font:14px system-ui;background:#f4f6f7}#grid{display:grid;grid-template-columns:repeat(4,250px);gap:8px;padding:12px}.cell{background:white;text-align:center}svg{display:block;width:250px;height:250px}</style><div id="grid"></div>');
 for(const mode of ['net','start','middle','end'] as const){
  await page.locator('#grid').evaluate((grid,{values,mode})=>{grid.replaceChildren();for(const value of values){const cell=document.createElement('div');cell.className='cell';cell.innerHTML=`<p>${value.event}</p>${value[mode]}`;grid.append(cell);}},{values,mode});
  await expect(page.locator('#grid svg')).toHaveCount(12);
  await expect(page.locator('#grid')).toHaveScreenshot(`all-events-${mode}.png`);
 }
});
test('seeking updates the actual consumer and preserves small viewport layout',async({page})=>{
 await page.setViewportSize({width:390,height:820});await page.goto('/');await expect(page.locator('#catalog-status')).toContainText('18 类标准项目');
 await page.locator('#event').selectOption('sq1');await page.getByLabel('项目公式',{exact:true}).fill('(1,0) /');await page.getByRole('button',{name:'查看图与动画',exact:true}).click();
 await expect(page.locator('#event-status')).toHaveText('0/2');const initial=await page.locator('#player-frame').innerHTML();await page.locator('#seek').fill('1000');
 await expect(page.locator('#event-status')).toHaveText('2/2');expect(await page.locator('#player-frame').innerHTML()).not.toEqual(initial);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
