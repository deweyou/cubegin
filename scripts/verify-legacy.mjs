// Optional migration oracle. Requires the retained legacy Git commit and pnpm install.
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';import {join} from 'node:path';import {execFileSync} from 'node:child_process';import {createRequire} from 'node:module';
const commit='79a1e4c4c5239fbcda8cccf313a81b8d7d430a97';
const directory=mkdtempSync(join(tmpdir(),'cubegin-legacy-oracle-'));
try {
 const archive=execFileSync('git',['archive',commit,'packages'],{maxBuffer:128*1024*1024});execFileSync('tar',['-x','-C',directory],{input:archive});
 const require=createRequire(import.meta.url);const {build}=await import(createRequire(require.resolve('vite')).resolve('esbuild'));
 const families={'222':'two-by-two','333':'three-by-three','444':'four-by-four','555':'big-cube','666':'big-cube','777':'big-cube',minx:'megaminx',pyram:'pyraminx',skewb:'skewb',sq1:'square-one',fto:'fto'};
 const symbols={'two-by-two':'TwoByTwo','three-by-three':'ThreeByThree','four-by-four':'FourByFour','big-cube':'BigCube',megaminx:'Megaminx',pyraminx:'Pyraminx',skewb:'Skewb','square-one':'SquareOne',fto:'Fto'};
 const file=join(directory,'packages/solver/src/assist/three-by-three/stage-mask.ts');writeFileSync(file,readFileSync(file,'utf8')+`\nexport {applyMoves,CFOP_F2L_META,ROUX_S2_META,PETRUS_S2_META,ZZ_F2L_META,EO_DR_META,BLOCK_222_TARGETS,BLOCK_222_SOLVED_STATES,GENERAL_PRESETS};\n`);
 const imports=[...new Set(Object.values(families))].map(f=>`import {does${symbols[f]}TrainingStateMatch as ${symbols[f]}} from '${directory}/packages/scramble-core/src/generators/training-${f}.ts';`).join('\n');
 const source=`${imports}
import * as p from '${directory}/packages/scramble-puzzle/src/index.ts';
import * as h from '${directory}/packages/solver/src/assist/three-by-three/target-validation.ts';
import * as d from '${file}';
import {isPyraminxVSolved} from '${directory}/packages/solver/src/assist/pyraminx/v.ts';
import {isSkewbFaceSolved} from '${directory}/packages/solver/src/assist/skewb/face.ts';
import {isSquareOneShapeSolved} from '${directory}/packages/solver/src/assist/square1/shape.ts';
import {isTwoByTwoFaceSolved,isTwoByTwoLayerSolved} from '${directory}/packages/solver/src/assist/two-by-two/face-layer.ts';
import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
const validators={${Object.entries(families).map(([k,v])=>JSON.stringify(k)+':'+symbols[v]).join(',')}};
let states=0,training=0,assist=0;
for(const f of JSON.parse(readFileSync('fixtures/events.json','utf8'))){const base=f.eventId==='333mbld'?'333':f.eventId.replace(/bld|fm|oh/g,'');const def=/^\\d/.test(base)?p.createCubeDefinition(Number(base[0]),[]):({clock:p.createClockDefinition,minx:p.createMegaminxDefinition,pyram:p.createPyraminxDefinition,skewb:p.createSkewbDefinition,sq1:p.createSquareOneDefinition,fto:p.createFtoDefinition})[base]();assert.deepEqual(def.applyAlgorithm(def.createSolvedState(),f.algorithm),f.state);states++;}
for(const r of JSON.parse(readFileSync('crates/scramble/tests/fixtures/training.json','utf8'))){assert.ok(validators[r.event_id](r.scramble_type_id,r.algorithm),r.scramble_type_id);training++;}
const numeric={cross:'isCrossSolved',xcross:'isXCrossSolved',eofc:'isEOFCAligned',eoline:'isEOLineSolved','petrus-s1':'isPetrusS1Solved','roux-s1':'isRouxS1Solved'};
const stageKeys={'cfop-f2l':'CFOP_F2L_META','roux-s2':'ROUX_S2_META','petrus-s2':'PETRUS_S2_META','zz-f2l':'ZZ_F2L_META','eo-dr':'EO_DR_META'};
for(const r of JSON.parse(readFileSync('crates/solver/tests/fixtures/assist.json','utf8'))){let prior='';for(const s of r.solutions){let ok;const stageKey=stageKeys[r.method];if(numeric[r.method])ok=h[numeric[r.method]](r.scramble,s);else if(stageKey){const meta=d[stageKey].find(v=>v.head===s.target);ok=Object.keys(meta.step).some(goal=>d.applyMoves(goal,(r.scramble+' '+prior+' '+s.solution).trim().split(/\\s+/))===goal);prior+=' '+s.solution;}else if(r.method==='block-222'){const goal=d.BLOCK_222_SOLVED_STATES[d.BLOCK_222_TARGETS.indexOf(s.target)];ok=d.applyMoves(goal,(r.scramble+' '+s.solution).trim().split(/\\s+/))===goal;}else if(r.method==='333-general'){const goal=d.GENERAL_PRESETS.find(p=>p[0]===s.targetLabel)[1];ok=d.applyMoves(goal,(r.scramble+' '+s.solution).trim().split(/\\s+/))===goal;}else if(r.method==='pyraminx-v')ok=isPyraminxVSolved(r.scramble,s);else if(r.method==='skewb-face')ok=isSkewbFaceSolved(r.scramble,s);else if(r.method==='222-face')ok=isTwoByTwoFaceSolved(r.scramble,s);else if(r.method==='222-layer')ok=isTwoByTwoLayerSolved(r.scramble,s);else if(r.method.startsWith('sq1-shape'))ok=isSquareOneShapeSolved(r.scramble,s.solution);else if(r.method==='333-two-phase'){const def=p.createCubeDefinition(3,[]);ok=def.isSolved(def.applyAlgorithm(def.createSolvedState(),r.scramble+' '+s.solution));}else throw Error(r.method);assert.ok(ok,r.method+' '+s.target);assist++;}}
console.log({legacyCommit:'${commit}',states,training,assist});`;
 const entry=join(directory,'oracle.ts'),output=join(directory,'oracle.cjs');writeFileSync(entry,source);
 await build({entryPoints:[entry],outfile:output,bundle:true,platform:'node',format:'cjs',alias:{'@cubegin/shared/events':directory+'/packages/shared/src/events/index.ts','@cubegin/scramble-puzzle':directory+'/packages/scramble-puzzle/src/index.ts'}});
 execFileSync(process.execPath,[output],{stdio:'inherit'});
}finally{rmSync(directory,{recursive:true,force:true});}
