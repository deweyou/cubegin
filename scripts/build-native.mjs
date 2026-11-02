import {run} from './process.mjs';
import {mkdirSync,copyFileSync,rmSync} from 'node:fs';
const library=process.platform==='darwin'?'target/release/libcubegin_native.dylib':'target/release/libcubegin_native.so';
run('cargo',['build','-p','cubegin-native','--release','--locked']);
for(const [language,destination] of [['swift','sdk/swift/Generated'],['kotlin','sdk/android/library/src/main/java']]) {
 rmSync(destination,{recursive:true,force:true});mkdirSync(destination,{recursive:true});
 run('cargo',['run','-p','cubegin-native','--features','cli','--bin','uniffi-bindgen','--','generate',library,'--language',language,'--no-format','--out-dir',destination]);
}
const notices='sdk/android/library/src/main/resources/META-INF';
mkdirSync(notices,{recursive:true});
for(const file of ['LICENSE','NOTICE']) copyFileSync(file,`${notices}/${file}`);
