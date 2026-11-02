import {copyFileSync, mkdirSync} from 'node:fs';
import {run} from './process.mjs';
import {writeArtifactManifest} from './artifact-metadata.mjs';
run('cargo',['build','-p','cubegin-cli','--release','--locked']);
mkdirSync('dist/cli',{recursive:true});
const binary = process.platform === 'win32' ? 'cubegin.exe' : 'cubegin';
copyFileSync(`target/release/${binary}`,`dist/cli/${binary}`);
for (const file of ['LICENSE','NOTICE']) copyFileSync(file,`dist/cli/${file}`);
writeArtifactManifest({root:'dist/cli',artifact:`cli-${process.platform}-${process.arch}`,paths:[binary,'LICENSE','NOTICE']});
