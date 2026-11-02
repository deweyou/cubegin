import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const version=process.argv[2];
if(!/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$/.test(version)) throw new Error('Invalid version');
const metadata=spawnSync('cargo',['metadata','--format-version','1','--no-deps','--locked'],{encoding:'utf8'});
if(metadata.status!==0) throw new Error(metadata.stderr);
const packages=JSON.parse(metadata.stdout).packages;
for(const pkg of packages) if(pkg.version!==version) throw new Error(`Version mismatch: ${pkg.name} ${pkg.version}`);
if(JSON.parse(readFileSync('sdk/web/package.json')).version!==version) throw new Error('Web version mismatch');
if(!readFileSync('sdk/android/library/build.gradle.kts','utf8').includes(`version = "${version}"`)) throw new Error('Android version mismatch');
const commit=spawnSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim();
const dirty=spawnSync('git',['status','--porcelain'],{encoding:'utf8'}).stdout.trim()!=='';
const plan={version,commit,dirty,publicationEnabled:false,
 crates:packages.filter(pkg=>pkg.publish===null).map(pkg=>pkg.name),
 artifacts:['npm tarball + wasm','Swift sources + XCFramework + checksum','Android AAR + POM + sources'],
 requiredBeforePublication:['clean approved commit','all platform consumer checks','registry ownership and credentials','transitive license inventory','immutable remote Swift artifact metadata','registry-specific publish and readback'],
};
mkdirSync('dist',{recursive:true});writeFileSync('dist/release-plan.json',JSON.stringify(plan,null,2));
console.log(JSON.stringify(plan,null,2));
