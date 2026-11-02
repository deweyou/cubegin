import {run} from './process.mjs';
import {mkdirSync} from 'node:fs';
mkdirSync('target/swift-test',{recursive:true});
run('swiftc',['-emit-module','-emit-library','-module-name','Cubegin','-I','sdk/swift/Generated','-Xcc','-fmodule-map-file=sdk/swift/Generated/CubeginFFI.modulemap','sdk/swift/Generated/Cubegin.swift','-L','target/release','-lcubegin_native','-emit-module-path','target/swift-test/Cubegin.swiftmodule','-o','target/swift-test/libCubegin.dylib']);
run('swiftc',['-I','target/swift-test','-I','sdk/swift/Generated','-Xcc','-fmodule-map-file=sdk/swift/Generated/CubeginFFI.modulemap','-L','target/swift-test','-lCubegin','sdk/swift/Tests/smoke.swift','-o','target/swift-test/smoke']);
run('target/swift-test/smoke',[],{env:{...process.env,DYLD_LIBRARY_PATH:`${process.cwd()}/target/release:${process.cwd()}/target/swift-test`}});
