import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, writeFileSync, readFileSync, rmSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {writeArtifactManifest, writeArchiveChecksum} from './artifact-metadata.mjs';

test('portable artifact manifest hashes exact binary bytes and excludes its own output',()=>{
 const root=mkdtempSync(join(tmpdir(),'cubegin-metadata-'));
 try {
  writeFileSync(join(root,'payload'),Buffer.from('abc'));
  writeFileSync(join(root,'SDK.json'),'stale');
  const metadata=writeArtifactManifest({root,artifact:'fixture',paths:['payload','SDK.json']});
  assert.equal(metadata.files.payload,'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.deepEqual(Object.keys(metadata.files),['payload']);
  assert.match(metadata.sourceCommit,/^[a-f0-9]{40}$/);
  assert.equal(metadata.sourceObservation,'packaging-time');
  assert.equal(typeof metadata.sourceDirty,'boolean');
  writeArchiveChecksum(join(root,'payload'));
  assert.equal(readFileSync(join(root,'payload.sha256'),'utf8'),metadata.files.payload+'  payload\n');
  writeFileSync(join(root,'payload'),'changed');
  assert.notEqual(writeArtifactManifest({root,artifact:'fixture',paths:['payload']}).files.payload,metadata.files.payload);
 } finally {rmSync(root,{recursive:true,force:true});}
});
test('reject missing files, paths outside package, symlinks and empty inventories',()=>{
 const root=mkdtempSync(join(tmpdir(),'cubegin-metadata-'));
 try {
  for(const paths of [[],['missing'],['../outside']])assert.throws(()=>writeArtifactManifest({root,artifact:'fixture',paths}));
  symlinkSync('/etc/hosts',join(root,'link'));
  assert.throws(()=>writeArtifactManifest({root,artifact:'fixture',paths:['link']}),/symlink/);
 } finally {rmSync(root,{recursive:true,force:true});}
});
