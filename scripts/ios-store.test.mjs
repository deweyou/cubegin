import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readdirSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';

const script = fileURLToPath(new URL('./ios-store.mjs', import.meta.url));
const listing = fileURLToPath(new URL('../store-listing/ios/app-store/', import.meta.url));

function stagingDirectory(t) {
  const directory = mkdtempSync(join(tmpdir(), 'cubegin-store-test-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  return directory;
}

test('exports both approved store descriptions and public fields in asc layout', t => {
  const directory = stagingDirectory(t);
  const command = spawnSync(process.execPath, [script, 'metadata', '1.0.0', directory], {encoding: 'utf8'});
  assert.equal(command.status, 0, command.stderr);

  for (const [locale, heading, base] of [
    ['zh-Hans', '描述', 'https://cubegin.deweyou.me/'],
    ['en-US', 'Description', 'https://cubegin.deweyou.me/en/'],
  ]) {
    const app = JSON.parse(readFileSync(join(directory, 'app-info', `${locale}.json`), 'utf8'));
    const version = JSON.parse(readFileSync(join(directory, 'version/1.0.0', `${locale}.json`), 'utf8'));
    const source = readFileSync(join(listing, `${locale}.md`), 'utf8');
    assert.equal(app.name, 'Cubegin');
    assert.equal(app.privacyPolicyUrl, `${base}privacy/`);
    assert.equal(version.description, source.split(`## ${heading}\n`)[1].trim());
    assert.equal(version.marketingUrl, base);
    assert.equal(version.supportUrl, `${base}feedback/`);
    assert.equal(version.promotionalText, undefined);
  }
});

test('screenshot staging puts timer first and keeps Duo outer images ahead of inner', t => {
  const directory = stagingDirectory(t);
  const command = spawnSync(process.execPath, [script, 'screenshots', directory], {encoding: 'utf8'});
  assert.equal(command.status, 0, command.stderr);

  for (const locale of ['zh-Hans', 'en-US']) {
    for (const device of ['iphone', 'ipad', 'iphone-duo']) {
      const source = join(listing, 'screenshots', locale, device);
      const staged = join(directory, locale, device);
      const names = readdirSync(staged).sort();
      assert.equal(names.length, readdirSync(source).length);
      assert.match(names[0], /timer\.jpg$/);
      if (device === 'iphone-duo') {
        const innerStart = names.findIndex(name => name.includes('inner-landscape'));
        assert.ok(innerStart > 0);
        assert.ok(names.slice(0, innerStart).every(name => name.includes('outer-portrait')));
      }
      for (const name of names) {
        assert.deepEqual(readFileSync(join(staged, name)), readFileSync(join(source, name.slice(3))));
      }
    }
  }
});

test('requires the exact app, build and internal group in a TestFlight receipt', () => {
  const groups = [{id: 'target', type: 'internal', name: 'Cubegin Internal'}];
  const receipt = {appId: '6838818301', buildId: 'candidate', groups};
  const verify = input => spawnSync(process.execPath, [script, 'verify-testflight', 'candidate', 'target'], {
    encoding: 'utf8',
    input: JSON.stringify(input),
  });
  assert.equal(verify(receipt).status, 0);
  assert.equal(verify({...receipt, buildId: 'old-build'}).status, 1);
  assert.equal(verify({...receipt, groups: []}).status, 1);
  assert.equal(verify({...receipt, groups: [{...groups[0], type: 'external'}]}).status, 1);
});
