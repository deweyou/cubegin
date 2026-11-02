import {mkdtempSync,mkdirSync,copyFileSync,rmSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {run} from './process.mjs';
// Cargo caches same-version temporary-registry sources by registry path. A fresh
// path ensures a repeated pre-release verification cannot reuse yesterday's crate.
mkdirSync('target',{recursive:true});
const temporary=mkdtempSync(join(resolve('target'),'rust-packages-'));
const metadata=JSON.parse(execFileSync('cargo',['metadata','--no-deps','--format-version','1','--locked'],{encoding:'utf8'}));
const versions=Object.fromEntries(metadata.packages.map(p=>[p.name,p.version]));
const names=['cubegin-tnoodle','cubegin-puzzle','cubegin-solver','cubegin-scramble','cubegin-diagram','cubegin-playback','cubegin'];
try {
 run('cargo',['package',...names.flatMap(name=>['-p',name]),'--allow-dirty','--locked','--target-dir',temporary]);
 mkdirSync('dist/rust',{recursive:true});
 for(const name of names)copyFileSync(join(temporary,'package',`${name}-${versions[name]}.crate`),`dist/rust/${name}-${versions[name]}.crate`);
}finally{rmSync(temporary,{recursive:true,force:true});}
