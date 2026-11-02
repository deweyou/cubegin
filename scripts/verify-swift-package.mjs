import {run} from './process.mjs';
import {mkdtempSync,mkdirSync,copyFileSync,cpSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
const consumer=mkdtempSync(join(tmpdir(),'cubegin-swift-consumer-'));
mkdirSync(join(consumer,'dist'));
run('ditto',['-x','-k',resolve('dist/CubeginFFI.xcframework.zip'),join(consumer,'dist')]);
copyFileSync('Package.swift',join(consumer,'Package.swift'));
for(const directory of ['Generated','PackageTests']) {
 cpSync(`sdk/swift/${directory}`,join(consumer,'sdk/swift',directory),{recursive:true});
}
run('swift',['test'],{cwd:consumer});
writeFileSync('dist/swift-verification.json',JSON.stringify({verified:true,consumer,artifact:'CubeginFFI.xcframework.zip'},null,2));
