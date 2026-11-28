import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFileSync, createReadStream, mkdirSync, readdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repo = fileURLToPath(new URL('../', import.meta.url));
const listing = join(repo, 'store-listing/ios/app-store');
const locales = [
  {
    id: 'zh-Hans',
    heading: '描述',
    blank: '留空',
    app: {name: '名称', subtitle: '副标题', privacyPolicyUrl: '隐私政策网址'},
    version: {keywords: '关键词', supportUrl: '技术支持网址', marketingUrl: '营销网址', promotionalText: '推广文本'},
  },
  {
    id: 'en-US',
    heading: 'Description',
    blank: 'Blank',
    app: {name: 'Name', subtitle: 'Subtitle', privacyPolicyUrl: 'Privacy Policy URL'},
    version: {keywords: 'Keywords', supportUrl: 'Support URL', marketingUrl: 'Marketing URL', promotionalText: 'Promotional Text'},
  },
];

function metadataFields(markdown, fields, locale) {
  const metadata = {};
  const rows = markdown.split('\n').map(line => line.split('|').map(cell => cell.trim()));
  for (const [field, label] of Object.entries(fields)) {
    const matchingRows = rows.filter(row => row[0] === '' && row[1] === label && row.length === 4);
    if (matchingRows.length !== 1 || !matchingRows[0][2]) {
      throw new Error(`Expected one populated ${label} row in ${locale.id}.md`);
    }
    const value = matchingRows[0][2];
    if (value === locale.blank && field === 'promotionalText') continue;
    if (field.endsWith('Url')) {
      const link = /^\[[^\]]+\]\((https:\/\/[^\s)]+)\)$/.exec(value);
      if (!link) throw new Error(`Expected an HTTPS link for ${label} in ${locale.id}.md`);
      metadata[field] = link[1];
    } else {
      metadata[field] = value.replace(/^`([^`]+)`$/, '$1');
    }
  }
  return metadata;
}

function generateMetadata(version, directory) {
  const localized = locales.map(locale => {
    const source = readFileSync(join(listing, `${locale.id}.md`), 'utf8').replaceAll('\r\n', '\n');
    const [table, description, extra] = source.split(`\n## ${locale.heading}\n`);
    if (!description?.trim() || extra !== undefined) {
      throw new Error(`Expected one description in ${locale.id}.md`);
    }
    return {
      locale: locale.id,
      app: metadataFields(table, locale.app, locale),
      version: {...metadataFields(table, locale.version, locale), description: description.trim()},
    };
  });

  const appDirectory = join(directory, 'app-info');
  const versionDirectory = join(directory, 'version', version);
  mkdirSync(appDirectory, {recursive: true});
  mkdirSync(versionDirectory, {recursive: true});
  for (const entry of localized) {
    writeFileSync(join(appDirectory, `${entry.locale}.json`), JSON.stringify(entry.app, null, 2) + '\n');
    writeFileSync(join(versionDirectory, `${entry.locale}.json`), JSON.stringify(entry.version, null, 2) + '\n');
  }
}

function stageScreenshots(directory) {
  mkdirSync(directory, {recursive: true});
  if (readdirSync(directory).length) throw new Error('Use an empty screenshot staging directory');

  for (const {id} of locales) {
    for (const device of ['iphone', 'ipad', 'iphone-duo']) {
      const source = join(listing, 'screenshots', id, device);
      const target = join(directory, id, device);
      const names = readdirSync(source).filter(name => /\.(jpe?g|png)$/i.test(name)).sort();
      const timer = names.find(name => name.startsWith(`${device}-timer.`));
      const ordered = timer ? [timer, ...names.filter(name => name !== timer)] : names;
      if (!ordered.length) throw new Error(`No screenshots in ${id}/${device}`);
      mkdirSync(target, {recursive: true});
      ordered.forEach((name, index) => {
        const orderedName = `${String(index + 1).padStart(2, '0')}-${name}`;
        copyFileSync(join(source, name), join(target, orderedName));
      });
    }
  }
}

function git(args) {
  return execFileSync('git', args, {cwd: repo, encoding: 'utf8'}).trim();
}

async function verifyIPA(version, build, ipa) {
  if (!/^[1-9]\d*$/.test(build)) throw new Error('Build number must be a positive integer');
  const candidateTag = `app-candidate/ios/${build}`;
  const commit = git(['rev-parse', '--verify', `${candidateTag}^{commit}`]);
  if (git(['rev-parse', '--verify', `app-build/ios/${build}^{commit}`]) !== commit) {
    throw new Error(`Build reservation and ${candidateTag} point to different commits`);
  }

  const candidate = git(['for-each-ref', '--format=%(contents)', `refs/tags/${candidateTag}`]).split('\n');
  for (const field of ['Bundle ID: io.github.deweyou.cubegin', `Version: ${version}`, `Build: ${build}`, `Commit: ${commit}`]) {
    if (!candidate.includes(field)) throw new Error(`Missing candidate field ${field} in ${candidateTag}`);
  }
  const receipt = candidate.find(line => /^IPA SHA-256: [a-f0-9]{64}$/.test(line));
  if (!receipt) throw new Error(`No IPA checksum registered in ${candidateTag}`);

  const hash = createHash('sha256');
  for await (const chunk of createReadStream(ipa)) hash.update(chunk);
  if (`IPA SHA-256: ${hash.digest('hex')}` !== receipt) {
    throw new Error(`IPA does not match ${candidateTag}`);
  }
  console.log(`Verified Cubegin ${version} (${build}) at ${commit}`);
}

function verifyTestFlightGroup(build, group) {
  const receipt = JSON.parse(readFileSync(0, 'utf8'));
  const membership = receipt.groups?.find(entry => entry.id === group && entry.type === 'internal');
  if (receipt.appId !== '6838818301' || receipt.buildId !== build || !membership) {
    throw new Error(`Build ${build} has no confirmed access in Cubegin Internal`);
  }
  console.log(`Verified TestFlight build ${build} in ${membership.name}`);
}

const [operation, ...args] = process.argv.slice(2);
try {
  if (operation === 'verify-testflight' && args.length === 2) {
    verifyTestFlightGroup(...args);
  } else if (operation === 'screenshots' && args.length === 1) {
    stageScreenshots(args[0]);
  } else {
    const [version, ...inputs] = args;
    if (!/^\d+\.\d+\.\d+$/.test(version ?? '')) throw new Error('Use a public version such as 1.0.0');
    if (operation === 'metadata' && inputs.length === 1) {
      generateMetadata(version, inputs[0]);
    } else if (operation === 'verify-ipa' && inputs.length === 2) {
      await verifyIPA(version, ...inputs);
    } else {
      throw new Error('Usage: ios-store.mjs metadata VERSION OUTPUT_DIR | screenshots OUTPUT_DIR | verify-ipa VERSION BUILD IPA | verify-testflight BUILD_ID GROUP_ID');
    }
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
