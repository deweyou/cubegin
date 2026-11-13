import {writeArtifactManifest, writeArchiveChecksum} from './artifact-metadata.mjs';
import {run} from './process.mjs';
import {mkdtempSync,mkdirSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
run('node',['scripts/build-web.mjs']);
mkdirSync('dist',{recursive:true});
const packed=spawnSync('npm',['pack','./sdk/web','--json','--pack-destination',resolve('dist')],{encoding:'utf8'});
if(packed.status!==0) throw new Error(packed.stderr);
const metadata=JSON.parse(packed.stdout)[0];
const consumer=mkdtempSync(join(tmpdir(),'cubegin-consumer-'));
writeFileSync(join(consumer,'package.json'),'{"type":"module","private":true}');
run('npm',['install','--ignore-scripts','--no-audit','--no-fund',resolve('dist',metadata.filename)],{cwd:consumer});
writeFileSync(join(consumer,'verify.mjs'),`
import {createCubegin} from 'cubegin';
import {createWorkerClient} from 'cubegin/worker';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const wasmURL=new URL('../wasm/cubegin_wasm_bg.wasm',import.meta.resolve('cubegin'));
const engine=await createCubegin(await readFile(wasmURL));
const fixtures=JSON.parse(await readFile(${JSON.stringify(resolve('fixtures/states.json'))},'utf8'));
for(const f of fixtures) assert.equal(engine.evaluate(f.algorithm).facelets,f.facelets);
const s=engine.scramble(42);assert.ok(engine.evaluate(s.algorithm+' '+engine.solve(s.facelets)).solved);
assert.equal(typeof createWorkerClient,'function');
const events=JSON.parse(await readFile(${JSON.stringify(resolve('fixtures/events.json'))},'utf8'));
for(const f of events)assert.deepEqual(engine.evaluateEvent(f.eventId,f.algorithm).state,f.state);
assert.equal(Object.keys(engine.typeCatalog()).length,112);
assert.equal(engine.generateTraining('333.pll',42).event_id,'333');
assert.ok(engine.solveAssist('333',['cross'],'R U F')[0].solutions.length);
assert.ok(engine.playerSvg('sq1','(1,0) /',1,.5).includes('<polygon'));

console.log('Isolated npm consumer passed '+fixtures.length+' 3x3 and '+events.length+' event fixtures, solver replay, training, assist and player');
`);
run(process.execPath,['verify.mjs'],{cwd:consumer});
writeFileSync('dist/npm-verification.json',JSON.stringify({version:metadata.version,shasum:metadata.shasum,integrity:metadata.integrity,package:metadata.filename,consumer,verified:true},null,2));

writeArtifactManifest({root:'dist',artifact:'npm',output:'npm-SDK.json',paths:[metadata.filename]});
writeArchiveChecksum(resolve('dist',metadata.filename));
