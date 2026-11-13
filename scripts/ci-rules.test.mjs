import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const scopeScript = fileURLToPath(new URL('./ci-scope.mjs', import.meta.url));
const gateScript = fileURLToPath(new URL('./ci-gate.sh', import.meta.url));

test('selects a scope from the entire change range', t => {
  const cwd = mkdtempSync(join(tmpdir(), 'cubegin-ci-'));
  t.after(() => rmSync(cwd, {recursive: true, force: true}));
  const git = (...args) => execFileSync('git', [
    '-c', 'user.name=CI test', '-c', 'user.email=ci@example.invalid',
    '-c', 'commit.gpgsign=false', ...args,
  ], {cwd, encoding: 'utf8'}).trim();
  function write(path, contents) {
    const file = join(cwd, path);
    mkdirSync(dirname(file), {recursive: true});
    writeFileSync(file, contents);
  }
  function commit(message) {
    git('add', '-A');
    git('commit', '-qm', message);
    return git('rev-parse', 'HEAD');
  }
  function scope(base) {
    return execFileSync(process.execPath, [scopeScript, base], {cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
  }

  git('init', '-q');
  write('apps/ios/Timer.swift', 'original');
  write('sdk/web/README.md', '# Web');
  const base = commit('baseline');
  assert.equal(scope(''), 'full');
  assert.equal(scope(base), 'full');
  assert.equal(scope('1'.repeat(40)), 'full');

  write('docs/README.md', '# Cubegin');
  const docs = commit('docs');
  assert.equal(scope(base), 'docs');

  write('.github/workflows/check.yml', 'name: CI');
  write('scripts/ci-gate.sh', '# gate');
  const rules = commit('CI rules');
  assert.equal(scope(docs), 'docs');
  assert.equal(scope(base), 'docs');

  write('sdk/web/README.md', '# Web SDK');
  const web = commit('published README');
  assert.equal(scope(rules), 'docs');
  assert.equal(scope(base), 'docs');

  write('apps/ios/Timer.swift', 'updated');
  const ios = commit('iOS');
  assert.equal(scope(web), 'ios');
  assert.equal(scope(base), 'full');

  write('scripts/build-ios.mjs', '// shared build');
  const shared = commit('shared build');
  assert.equal(scope(ios), 'full');

  renameSync(join(cwd, 'apps/ios/Timer.swift'), join(cwd, 'Timer.swift'));
  commit('move out of iOS');
  assert.equal(scope(shared), 'full');
});

const required = {
  full: ['RUST', 'RUST_PACKAGES', 'WEB', 'WEB_E2E', 'APPLE_BUILD', 'APPLE_PACKAGE', 'IOS', 'ANDROID'],
  ios: ['APPLE_BUILD', 'IOS'],
  docs: ['DOCS'],
};
const results = new Set(['SCOPE', 'CI_RULES', ...Object.values(required).flat()]);

for (const [scope, jobs] of Object.entries(required)) {
  test(`CI passed enforces every job result for ${scope}`, () => {
    const env = {...process.env, CHECKS: scope};
    for (const name of results) {
      env[`${name}_RESULT`] = ['SCOPE', 'CI_RULES', ...jobs].includes(name) ? 'success' : 'skipped';
    }
    const run = overrides => spawnSync('bash', [gateScript], {
      env: {...env, ...overrides}, encoding: 'utf8',
    });
    const success = run({});
    assert.equal(success.status, 0, success.stderr);
    for (const name of results) {
      const key = `${name}_RESULT`;
      for (const value of ['success', 'skipped', 'failure', 'cancelled']) {
        if (value === env[key]) continue;
        assert.equal(run({[key]: value}).status, 1, `${key}=${value}`);
      }
    }
    assert.equal(run({CHECKS: 'unknown'}).status, 1);
  });
}
