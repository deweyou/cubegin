import {writeArtifactManifest} from './artifact-metadata.mjs';
import {run} from './process.mjs';
import {readFileSync,copyFileSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const manifest=readFileSync('Cargo.toml','utf8');
const version=manifest.match(/wasm-bindgen = "=([^"]+)"/)[1];
const installed=spawnSync('wasm-bindgen',['--version'],{encoding:'utf8'});
if(installed.status!==0 || installed.stdout.trim()!==`wasm-bindgen ${version}`) {
  throw new Error(`Install matching tool first: cargo install wasm-bindgen-cli --version ${version} --locked`);
}
run('cargo',['build','-p','cubegin-wasm','--target','wasm32-unknown-unknown','--release','--locked']);
rmSync('sdk/web/wasm',{recursive:true,force:true});
run('wasm-bindgen',['target/wasm32-unknown-unknown/release/cubegin_wasm.wasm','--target','web','--out-dir','sdk/web/wasm']);
rmSync('sdk/web/dist',{recursive:true,force:true});
run('pnpm',['exec','tsc','-p','sdk/web/tsconfig.json']);
for(const file of ['LICENSE','NOTICE']) copyFileSync(file,`sdk/web/${file}`);

writeArtifactManifest({root:'sdk/web',artifact:'web',paths:['dist','wasm','package.json','README.md','LICENSE','NOTICE']});
