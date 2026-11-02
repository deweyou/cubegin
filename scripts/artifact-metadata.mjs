import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {dirname, isAbsolute, relative, resolve} from 'node:path';

export const sha256 = path => createHash('sha256').update(readFileSync(path)).digest('hex');
export function workspaceVersion() {
 const match = readFileSync('Cargo.toml','utf8').match(/\[workspace\.package\][\s\S]*?version\s*=\s*"([^"]+)"/);
 if (!match) throw new Error('Missing workspace version');
 return match[1];
}
// Metadata observes sources at packaging time; it is not a clean-build attestation.
export function writeArtifactManifest({root, artifact, paths, output='SDK.json'}) {
 root = resolve(root);
 const destination = resolve(root, output);
 if (relative(root,destination).startsWith('..') || destination === root) throw new Error('Manifest must be inside artifact root');
 const files = {};
 function visit(path) {
  const name = relative(root,path).split('\\').join('/');
  if (name.startsWith('../') || isAbsolute(name) || path === root) throw new Error(`Invalid artifact path: ${path}`);
  if (path === destination) return;
  const stat = lstatSync(path);
  if (stat.isSymbolicLink()) throw new Error(`Artifact symlink not supported: ${path}`);
  if (stat.isDirectory()) {
   for (const child of readdirSync(path).sort()) visit(resolve(path,child));
  } else if (stat.isFile()) files[name] = sha256(path);
  else throw new Error(`Unsupported artifact file: ${path}`);
 }
 for (const path of paths) visit(resolve(root,path));
 if (!Object.keys(files).length) throw new Error('Empty artifact manifest');
 const git = (...args) => execFileSync('git',args,{encoding:'utf8'}).trim();
 const metadata = {schemaVersion:1,artifact,version:workspaceVersion(),sourceCommit:git('rev-parse','HEAD'),
  sourceDirty:git('status','--porcelain','--untracked-files=normal') !== '',
  sourceObservation:'packaging-time',packagedAt:new Date().toISOString(),license:'GPL-3.0-only',files};
 mkdirSync(dirname(destination),{recursive:true});
 writeFileSync(destination,JSON.stringify(metadata,null,2)+'\n');
 return metadata;
}
export function writeArchiveChecksum(path) {
 writeFileSync(`${path}.sha256`,`${sha256(path)}  ${path.split('/').at(-1)}\n`);
}
