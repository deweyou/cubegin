import {writeArtifactManifest} from './artifact-metadata.mjs';
import {execFileSync} from 'node:child_process';
import {run} from './process.mjs';
import {mkdirSync,copyFileSync,writeFileSync,rmSync} from 'node:fs';
const args=process.argv.slice(2);
const mode=args[0];
if(args.length>1 || (mode && !['--app-only','--package-only'].includes(mode))){
 throw new Error('Usage: node scripts/build-ios.mjs [--app-only|--package-only]');
}
if(mode!=='--package-only') buildFramework();
if(mode!=='--app-only') packageFramework();

function buildFramework(){
 run('node',['scripts/build-native.mjs']);
 const targets=['aarch64-apple-ios','aarch64-apple-ios-sim','x86_64-apple-ios'];
 for(const target of targets) run('cargo',['build','-p','cubegin-native','--release','--target',target,'--locked']);
 const headers='target/apple-headers';mkdirSync(headers,{recursive:true});
 copyFileSync('sdk/swift/Generated/CubeginFFI.h',`${headers}/CubeginFFI.h`);
 writeFileSync(`${headers}/module.modulemap`,'module CubeginFFI { header "CubeginFFI.h" export * }\n');
 mkdirSync('dist',{recursive:true});
 run('lipo',['-create','target/aarch64-apple-ios-sim/release/libcubegin_native.a','target/x86_64-apple-ios/release/libcubegin_native.a','-output','dist/libcubegin-simulator.a']);
 rmSync('dist/CubeginFFI.xcframework',{recursive:true,force:true});
 run('xcodebuild',['-create-xcframework',
  '-library','target/aarch64-apple-ios/release/libcubegin_native.a','-headers',headers,
  '-library','dist/libcubegin-simulator.a','-headers',headers,
  '-library','target/release/libcubegin_native.a','-headers',headers,
  '-output','dist/CubeginFFI.xcframework']);
 for(const file of ['LICENSE','NOTICE']) copyFileSync(file,`dist/CubeginFFI.xcframework/${file}`);
}

function packageFramework(){
 run('swift',['test']);
 run('ditto',['-c','-k','--sequesterRsrc','--keepParent','dist/CubeginFFI.xcframework','dist/CubeginFFI.xcframework.zip']);
 const checksum=execFileSync('swift',['package','compute-checksum','dist/CubeginFFI.xcframework.zip'],{encoding:'utf8'}).trim();
 if(!/^[a-f0-9]{64}$/.test(checksum)) throw new Error('Invalid Swift package checksum');
 writeFileSync('dist/CubeginFFI.xcframework.zip.sha256',`${checksum}  CubeginFFI.xcframework.zip\n`);
 console.log(checksum);
 writeArtifactManifest({root:'dist',artifact:'ios-xcframework',output:'xcframework-SDK.json',paths:['CubeginFFI.xcframework.zip']});

 run('node',['scripts/verify-swift-package.mjs']);

 run('node',['scripts/package-ios.mjs']);
}
