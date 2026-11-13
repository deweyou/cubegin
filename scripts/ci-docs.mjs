import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import {dirname, resolve} from 'node:path';

const base = process.argv[2];
const changed = /^[0-9a-f]{40}$/.test(base ?? '') && !/^0+$/.test(base)
  ? execFileSync('git', ['diff', '--name-only', '--no-renames', '-z', base, 'HEAD']).toString().split('\0').filter(Boolean)
  : [];
// Asset changes and deletions may break references in unchanged documents.
const scanAll = changed.length === 0 || changed.some(path => !/\.md$/i.test(path) || !existsSync(path));
const files = (scanAll ? execFileSync('git', ['ls-files', '-z']).toString().split('\0') : changed)
  // The preserved design archive contains paths relative to the legacy checkout.
  .filter(path => /\.md$/i.test(path) && existsSync(path)
    && !path.startsWith('apps/ios/Design/LegacyIcons/reference/'));
let failures = 0;

for (const file of files) {
  const source = readFileSync(file, 'utf8').replace(/^```[^\n]*\n[\s\S]*?^```[^\n]*$/gm, '');
  const links = [
    ...Array.from(source.matchAll(/\]\((<[^>]+>|[^\s)]+)\)/g), match => match[1]),
    ...Array.from(source.matchAll(/\b(?:src|srcset)="([^"]+)"/g), match => match[1]),
  ];
  for (const raw of links) {
    const link = raw.replace(/^<|>$/g, '')
      .replace(/^https:\/\/github\.com\/deweyou\/cubegin\/blob\/main\//, '/');
    if (/^[a-z][a-z0-9+.-]*:|^\/\//i.test(link)) continue;
    const target = decodeURIComponent(link.split(/[?#]/)[0]);
    if (!target) continue;
    const path = target.startsWith('/') ? resolve(target.slice(1)) : resolve(dirname(realpathSync(file)), target);
    if (!existsSync(path)) {
      console.error(`${file}: missing target ${raw}`);
      failures++;
    }
  }
}

console.log(`Checked links and resources in ${files.length} Markdown files.`);
if (failures) process.exitCode = 1;
