import {execFileSync} from 'node:child_process';

const base = process.argv[2];
let scope = 'full';
if (/^[0-9a-f]{40}$/.test(base ?? '') && !/^0+$/.test(base)) {
  try {
    // A rename out of or into the app must still count as touching both paths.
    const diff = execFileSync('git', ['diff', '--name-only', '--no-renames', '-z', base, 'HEAD']);
    const paths = diff.toString().split('\0').filter(Boolean);
    if (paths.length > 0 && paths.every(path => path.startsWith('apps/ios/'))) {
      scope = 'ios';
    }
  } catch {
    console.error('Could not compare the change range. Running all checks.');
  }
}
console.log(scope);
