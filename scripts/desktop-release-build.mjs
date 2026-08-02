import { spawnSync } from 'child_process';
import { cpSync, mkdirSync, readFileSync, readdirSync, statSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const root = join(__dirname, '..');

const DARWIN_TARGETS = {
  aarch64: 'aarch64-apple-darwin',
  x86_64: 'x86_64-apple-darwin',
  universal: 'universal-apple-darwin',
};

function readVersion() {
  const raw = readFileSync(join(root, 'src-tauri', 'tauri.conf.json'), 'utf8');
  const j = JSON.parse(raw);
  if (!j.version) throw new Error('tauri.conf.json missing version');
  return j.version;
}

function hostDarwinArch() {
  if (process.arch === 'arm64') return 'aarch64';
  if (process.arch === 'x64') return 'x86_64';
  console.error(`Unsupported process.arch for darwin build: ${process.arch}`);
  process.exit(1);
}

function parseArgs(argv) {
  let platform = null;
  let arch = 'auto';

  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--platform' && argv[i + 1]) {
      platform = argv[i + 1];
      i++;
    } else if (argv[i] === '--arch' && argv[i + 1]) {
      arch = argv[i + 1];
      i++;
    }
  }

  if (!platform) {
    console.error(
      'Usage: node scripts/desktop-release-build.mjs --platform darwin|linux [--arch aarch64|x86_64|universal|auto]'
    );
    process.exit(1);
  }

  if (platform !== 'darwin' && platform !== 'linux') {
    console.error('platform must be darwin or linux');
    process.exit(1);
  }

  if (platform === 'linux' && arch !== 'auto') {
    console.error('--arch is only supported with --platform darwin');
    process.exit(1);
  }

  if (platform === 'darwin') {
    if (arch === 'auto') {
      arch = hostDarwinArch();
    } else if (!['aarch64', 'x86_64', 'universal'].includes(arch)) {
      console.error('--arch must be aarch64, x86_64, universal, or auto');
      process.exit(1);
    }
  }

  return { platform, arch };
}

function assertHost(platform) {
  const p = process.platform;
  if (platform === 'darwin' && p !== 'darwin') {
    console.error('macOS builds must run on darwin');
    process.exit(1);
  }
  if (platform === 'linux' && p !== 'linux') {
    console.error('Linux builds must run on linux');
    process.exit(1);
  }
}

function ensureRustTargets(arch) {
  const targets = new Set();
  if (arch === 'universal') {
    targets.add(DARWIN_TARGETS.aarch64);
    targets.add(DARWIN_TARGETS.x86_64);
  } else {
    targets.add(DARWIN_TARGETS[arch]);
  }

  for (const target of targets) {
    const list = spawnSync('rustup', ['target', 'list', '--installed'], {
      encoding: 'utf8',
    });
    if (list.status !== 0) {
      console.error('rustup target list failed');
      process.exit(list.status ?? 1);
    }
    if (!list.stdout.split('\n').includes(target)) {
      console.log(`Installing Rust target ${target}...`);
      const add = spawnSync('rustup', ['target', 'add', target], {
        stdio: 'inherit',
      });
      if (add.status !== 0) process.exit(add.status ?? 1);
    }
  }
}

function tauriRustTarget(arch) {
  if (arch === 'aarch64' && hostDarwinArch() === 'aarch64') {
    return null;
  }
  if (arch === 'x86_64' && hostDarwinArch() === 'x86_64') {
    return null;
  }
  return DARWIN_TARGETS[arch];
}

function cargoTargetDir() {
  return join(root, 'src-tauri', 'target');
}

function bundleRootForArch(arch) {
  const base = cargoTargetDir();
  const target = tauriRustTarget(arch);
  if (target) {
    return join(base, target, 'release', 'bundle');
  }
  return join(base, 'release', 'bundle');
}

function runTauriBuild(arch) {
  const env = { ...process.env, CARGO_TARGET_DIR: cargoTargetDir() };
  if (process.platform === 'darwin') {
    env.CI = 'true';
    if (arch === 'x86_64') {
      env.SUCHCONFIG_DARWIN_ARCH = 'x86_64';
    } else {
      env.SUCHCONFIG_DARWIN_ARCH = 'native';
    }
  }

  const args = ['exec', 'tauri', 'build'];
  const rustTarget = tauriRustTarget(arch);
  if (rustTarget) {
    args.push('--target', rustTarget);
  }

  const r = spawnSync('pnpm', args, {
    cwd: root,
    stdio: 'inherit',
    env,
  });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

function collectArtifacts(platform, version, arch) {
  const bundleRoot = bundleRootForArch(arch);
  const outDir = join(root, 'dist', 'desktop', version);
  mkdirSync(outDir, { recursive: true });

  if (platform === 'darwin') {
    const dmgDir = join(bundleRoot, 'dmg');
    if (!statSync(dmgDir, { throwIfNoEntry: false })?.isDirectory()) {
      console.error('Missing bundle output:', dmgDir);
      process.exit(1);
    }
    for (const name of readdirSync(dmgDir)) {
      if (name.endsWith('.dmg')) {
        cpSync(join(dmgDir, name), join(outDir, name));
        console.log('Copied', join(outDir, name));
      }
    }
  } else {
    const debDir = join(bundleRoot, 'deb');
    if (!statSync(debDir, { throwIfNoEntry: false })?.isDirectory()) {
      console.error('Missing bundle output:', debDir);
      process.exit(1);
    }
    for (const name of readdirSync(debDir)) {
      if (name.endsWith('.deb')) {
        cpSync(join(debDir, name), join(outDir, name));
        console.log('Copied', join(outDir, name));
      }
    }
  }
}

const { platform, arch } = parseArgs(process.argv);
assertHost(platform);
const version = readVersion();

if (platform === 'darwin') {
  ensureRustTargets(arch);
  if (arch === 'x86_64' && hostDarwinArch() === 'aarch64') {
    console.log(
      'Cross-building Intel (x86_64) from Apple Silicon — Phoenix/NIF built under arch -x86_64'
    );
  }
}

console.log('Building SuchConfig desktop', version, 'for', platform, arch);
runTauriBuild(arch);
collectArtifacts(platform, version, arch);
console.log('Done. Artifacts under dist/desktop/', version, '/');
