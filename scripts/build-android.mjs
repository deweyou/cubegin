import {run} from './process.mjs';
import {mkdirSync,copyFileSync} from 'node:fs';
run('node',['scripts/build-native.mjs']);
const ndk=process.env.ANDROID_NDK_HOME;
if(!ndk) throw new Error('Set ANDROID_NDK_HOME to a modern NDK (r28+); install cargo-ndk and the Rust Android targets');
run('cargo',['ndk','-t','arm64-v8a','-t','armeabi-v7a','-t','x86_64','--platform','23','-o','sdk/android/library/src/main/jniLibs','build','-p','cubegin-native','--release','--locked']);
run('sdk/android/gradlew',['-p','sdk/android','testReleaseUnitTest','assembleRelease','publishReleasePublicationToLocalStagingRepository']);
mkdirSync('dist/android',{recursive:true});
copyFileSync('sdk/android/library/build/outputs/aar/library-release.aar','dist/android/cubegin.aar');

run('node',['scripts/verify-android-package.mjs']);
