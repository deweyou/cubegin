import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCubegin} from '../dist/index.js';
const bytes=await readFile(new URL('../wasm/cubegin_wasm_bg.wasm',import.meta.url));
const engine=await createCubegin(bytes);
const fixtures=JSON.parse(await readFile(new URL('../../../fixtures/states.json',import.meta.url),'utf8'));
test('all shared fixtures traverse the real WASM binding',()=> {
  for(const fixture of fixtures) assert.equal(engine.evaluate(fixture.algorithm).facelets,fixture.facelets,fixture.algorithm);
});
test('SDK errors, u32 boundary and solution replay',()=> {
  assert.throws(()=>engine.evaluate('Rw'),/invalid move/);
  assert.throws(()=>engine.solve('bad'),/invalid cube state/);
  for(const seed of [-1,2**32,0.5,NaN]) assert.throws(()=>engine.scramble(seed),/u32/);
  const scramble=engine.scramble(42);
  assert.equal(engine.evaluate(scramble.algorithm).facelets,scramble.facelets);
  const solution=engine.solve(scramble.facelets);
  assert.ok(engine.evaluate(`${scramble.algorithm} ${solution}`).solved);
  const steps=engine.timeline("R U2 F'");
  assert.equal(steps.at(-1).after,engine.evaluate("R U2 F'").facelets);
});
const eventFixtures=JSON.parse(await readFile(new URL('../../../fixtures/events.json',import.meta.url),'utf8'));
test('all multi-puzzle state fixtures and solver replay through WASM',()=>{
 for(const f of eventFixtures)assert.deepEqual(engine.evaluateEvent(f.eventId,f.algorithm).state,f.state,f.eventId+' '+f.algorithm);
 for(const info of engine.eventCatalog()){
  if(info.id==='333mbld')continue;
  const s=engine.generateEvent(info.id,42);assert.deepEqual(engine.evaluateEvent(info.id,s.algorithm).state,s.state);
  if(info.full_solver)assert.ok(engine.evaluateEvent(info.id,s.algorithm+' '+engine.solveEvent(info.id,s.algorithm)).solved,info.id);
 }
 assert.equal(engine.generateMultiBlind(42,3).length,3);
});
test('training catalog, selected cases, batch uniqueness, assist and player',()=>{
 assert.equal(Object.keys(engine.typeCatalog()).length,112);
 for(const [id,info]of Object.entries(engine.typeCatalog())){if(info.kind==='official')continue;const s=engine.generateTraining(id,42);assert.deepEqual(engine.evaluateEvent(s.event_id,s.algorithm).state,s.state,id);}
 const cases=engine.trainingCases('333.pll');const selected=cases.at(-1).id;
 assert.equal(engine.generateTraining('333.pll',42,{enabled_case_ids:[selected],natural:true}).case_id,selected);
 const batch=engine.generateBatch('333',0,4);assert.equal(new Set(batch.map(s=>JSON.stringify(s.state))).size,4);
 assert.throws(()=>engine.generateTraining('minx.lsll.invalid',0),/unknown/);
 assert.equal(engine.assistMethods().length,20);
 assert.equal(engine.solveAssist('333',['cross'],'R U F')[0].solutions.length,6);
 assert.equal(engine.validateFmc('R','R R2').status,'valid');
 for(const [event,algorithm]of [['333','M Rw x'],['pyram',"R u'"],['fto','BL U'],['minx','R++ D-- U'],['sq1','(1,0) /'],['clock','z UR1+ y2 ALL3-']]){
  const t=engine.playerTimeline(event,algorithm);assert.ok(t.model.pieces.length);assert.ok(engine.playerSvg(event,algorithm,0,.5).includes('<polygon'));
  assert.equal(engine.playerFrame(event,algorithm,t.steps.length,0).pieces.length,t.model.pieces.length);
 }
});
