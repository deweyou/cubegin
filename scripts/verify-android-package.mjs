import {run} from './process.mjs';
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
const archive=spawnSync('unzip',['-Z1','dist/android/cubegin.aar'],{encoding:'utf8'});
if(archive.status!==0) throw new Error(archive.stderr);
for(const file of ['classes.jar','jni/arm64-v8a/libcubegin_native.so','jni/armeabi-v7a/libcubegin_native.so','jni/x86_64/libcubegin_native.so']) {
 if(!archive.stdout.split('\n').includes(file)) throw new Error(`AAR missing ${file}`);
}
for(const [abi,machine] of [['arm64-v8a',183],['armeabi-v7a',40],['x86_64',62]]) {
 const binary=spawnSync('unzip',['-p','dist/android/cubegin.aar',`jni/${abi}/libcubegin_native.so`],{maxBuffer:16*1024*1024});
 if(binary.status!==0 || binary.stdout.length<20 || binary.stdout.subarray(0,4).toString('hex')!=='7f454c46' || binary.stdout.readUInt16LE(18)!==machine) {
  throw new Error(`Wrong ELF architecture in AAR for ${abi}`);
 }
}
run('sdk/android/gradlew',['-p','examples/android','testReleaseUnitTest']);
writeFileSync('dist/android-verification.json',JSON.stringify({verified:true,artifact:'android/cubegin.aar',abis:['arm64-v8a','armeabi-v7a','x86_64'],runtime:'host JNA; Android-device runtime not exercised'},null,2));
