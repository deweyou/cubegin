// Run after build-ios.mjs has generated matching binaries and bindings.
import {cpSync, mkdirSync, rmSync} from 'node:fs';
import {join} from 'node:path';
import {workspaceVersion, writeArtifactManifest, writeArchiveChecksum} from './artifact-metadata.mjs';
import {run} from './process.mjs';
const version = workspaceVersion();
const name = `CubeginSDK-${version}`;
const destination = join('dist', name);
rmSync(destination, {recursive:true, force:true});
mkdirSync(join(destination,'dist'), {recursive:true});
cpSync('dist/CubeginFFI.xcframework',join(destination,'dist/CubeginFFI.xcframework'),{recursive:true});
for (const path of ['sdk/swift/Generated','sdk/swift/PackageTests']) {
 mkdirSync(join(destination,path),{recursive:true});
 cpSync(path,join(destination,path),{recursive:true});
}
for (const path of ['Package.swift','LICENSE','NOTICE','docs/provenance.md']) {
 mkdirSync(join(destination,path,'..'),{recursive:true});
 cpSync(path,join(destination,path));
}
writeArtifactManifest({root:destination,artifact:'ios',paths:['dist','sdk','Package.swift','LICENSE','NOTICE','docs']});
// Verify the complete self-contained directory before archiving it.
run('swift',['test','--package-path',destination]);
rmSync(join(destination,'.build'),{recursive:true,force:true});
const archive = `${destination}.zip`;
rmSync(archive,{force:true});
run('ditto',['-c','-k','--sequesterRsrc','--keepParent',destination,archive]);
writeArchiveChecksum(archive);
console.log(`Installable SDK: ${archive}`);
