import {test,expect} from '@playwright/test';
import fixtures from '../../fixtures/states.json' with {type:'json'};
const colors:Record<string,string>={U:'#ffffff',R:'#d93636',F:'#159957',D:'#ffd633',L:'#ff8a24',B:'#2962d9'};
test('all fixture states render correct sticker colors through the Worker SDK',async({page})=> {
 await page.goto('/');await page.locator('#legacy summary').click();await expect(page.locator('#status')).toHaveText('Scrambled');
 for(const fixture of fixtures) {
   await page.getByLabel('Algorithm',{exact:true}).fill(fixture.algorithm);
   await page.getByRole('button',{name:'Apply',exact:true}).click();
   await expect(page.locator('#state')).toHaveText(fixture.facelets);
   const fills=await page.locator('#diagram svg rect').evaluateAll(rects=>rects.map(rect=>rect.getAttribute('fill')));
   expect(fills).toEqual([...fixture.facelets].map(face=>colors[face]));
 }
});
test('SVG visual baseline, invalid input and real solver',async({page})=> {
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 await page.goto('/');await page.locator('#legacy summary').click();await expect(page.locator('#status')).toHaveText('Scrambled');await expect(page.locator('#status')).toHaveText('Scrambled');
 await expect(page.locator('#diagram')).toHaveScreenshot('sexy-move.png');
 await page.getByLabel('Algorithm',{exact:true}).fill('');await page.getByRole('button',{name:'Apply',exact:true}).click();
 await expect(page.locator('#status')).toHaveText('Solved');
 await expect(page.locator('#diagram')).toHaveScreenshot('solved.png');
 await page.getByLabel('Algorithm',{exact:true}).fill('Rw');await page.getByRole('button',{name:'Apply',exact:true}).click();
 await expect(page.locator('#error')).toContainText('invalid move');
 await page.getByRole('button',{name:'Scramble · seed 42',exact:true}).click();
 await expect(page.locator('#status')).toHaveText('Scrambled');
 await page.getByRole('button',{name:'Solve',exact:true}).click();
 await expect(page.locator('#status')).toHaveText('Solved',{timeout:30000});
 expect(errors).toEqual([]);
});
test('narrow viewport keeps the net in view',async({page})=> {
 await page.setViewportSize({width:320,height:680});await page.goto('/');await page.locator('#legacy summary').click();await expect(page.locator('#status')).toHaveText('Scrambled');
 await expect(page.locator('#diagram svg rect')).toHaveCount(54);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
