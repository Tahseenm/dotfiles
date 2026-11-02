const { spawnSync } = require('node:child_process');
const manifest = require('./package.json');

const entries = Object.entries(manifest.dependencies || {});
if (!entries.length) {
  console.log('No global pnpm packages configured.');
  process.exit(0);
}

if (process.argv.includes('--dry-run')) {
  for (const [name, version] of entries) console.log(`would ensure: ${name}@${version}`);
  process.exit(0);
}

const list = spawnSync(
  'pnpm',
  ['list', '--global', '--depth', '0', '--json'], { encoding: 'utf8' },
);
if (list.status !== 0) {
  throw new Error(
    `Could not list global pnpm packages: ${list.stderr || list.error || list.status}`
  );
}

const projects = JSON.parse(list.stdout || '[]');
const installed = Object.assign(
  {},
  ...projects.map(project => project.dependencies || {}),
);

for (const [name, version] of entries) {
  if (Object.hasOwn(installed, name)) {
    console.log(`already installed: ${name}`);
    continue;
  }

  console.log(`Installing global package: ${name}@${version}`);
  const result = spawnSync('pnpm', ['add', '--global', `${name}@${version}`], { stdio: 'inherit' });
  if (result.status !== 0) {
    throw new Error(`Could not install ${name}: ${result.error || result.status}`);
  }
}
