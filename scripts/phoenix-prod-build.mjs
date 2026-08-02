import { execSync, spawnSync } from 'child_process';
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const phoenixPath = join(root, 'phoenix-app');
const darwinArch = process.env.SUCHCONFIG_DARWIN_ARCH || 'native';

function expectedMachArch() {
  if (darwinArch === 'x86_64') return 'x86_64';
  if (darwinArch === 'aarch64') return 'arm64';
  return process.arch === 'arm64' ? 'arm64' : 'x86_64';
}

function beamArch(beamPath) {
  if (!existsSync(beamPath)) return null;
  return execSync(`file -b "${beamPath}"`, { encoding: 'utf8' }).trim();
}

function isX86DarwinBeam(beamPath) {
  return beamArch(beamPath)?.includes('x86_64') ?? false;
}

function intelErlangRoot() {
  const override = process.env.SUCHCONFIG_X86_64_ERLANG_ROOT?.trim();
  if (override) {
    const beam = join(override, 'bin', 'beam.smp');
    if (isX86DarwinBeam(beam)) return override;
    console.error(`SUCHCONFIG_X86_64_ERLANG_ROOT is set but ${beam} is not x86_64`);
    process.exit(1);
  }

  for (const candidate of ['/usr/local/opt/erlang']) {
    const beam = join(candidate, 'bin', 'beam.smp');
    if (isX86DarwinBeam(beam)) return candidate;
  }

  try {
    const prefix = execSync('arch -x86_64 /usr/local/bin/brew --prefix erlang 2>/dev/null', {
      encoding: 'utf8',
    }).trim();
    const beam = join(prefix, 'bin', 'beam.smp');
    if (prefix && isX86DarwinBeam(beam)) return prefix;
  } catch {
    // Rosetta Homebrew not installed
  }

  return null;
}

function printIntelErlangHelp() {
  console.error(`
Intel Phoenix build from Apple Silicon requires an x86_64 Erlang install.
Your default Elixir (asdf/Homebrew arm64) cannot produce an Intel OTP release.

Option A — build on the Intel Mac (recommended):
  pnpm run desktop:release:build -- --platform darwin --arch x86_64

Option B — install Rosetta Homebrew Erlang on this machine, then rebuild:
  arch -x86_64 /usr/local/bin/brew install erlang
  export SUCHCONFIG_X86_64_ERLANG_ROOT="$(arch -x86_64 /usr/local/bin/brew --prefix erlang)"
  pnpm run desktop:release:build -- --platform darwin --arch x86_64

If /usr/local/bin/brew is missing, install Intel Homebrew first:
  arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
`);
}

function requireIntelErlangForCrossBuild() {
  if (process.platform !== 'darwin' || darwinArch !== 'x86_64' || process.arch !== 'arm64') {
    return null;
  }

  const erlangRoot = intelErlangRoot();
  if (!erlangRoot) {
    printIntelErlangHelp();
    process.exit(1);
  }

  console.log(`Using x86_64 Erlang at ${erlangRoot}`);
  return erlangRoot;
}

function prodMixEnv(extraEnv = {}) {
  const env = { ...process.env, MIX_ENV: 'prod', ...extraEnv };
  const erlangRoot = requireIntelErlangForCrossBuild();
  if (erlangRoot) {
    const bin = join(erlangRoot, 'bin');
    env.PATH = `${bin}:${env.PATH ?? ''}`;
    env.ERLANG_HOME = erlangRoot;
  }
  return env;
}

function runMix(args) {
  const env = prodMixEnv();
  const r = spawnSync('mix', args, {
    cwd: phoenixPath,
    stdio: 'inherit',
    env,
  });

  if (r.status !== 0) {
    process.exit(r.status ?? 1);
  }
}

function verifyReleaseArch(releaseRoot) {
  const ertsDir = readdirSync(releaseRoot).find((name) => name.startsWith('erts-'));
  if (!ertsDir) {
    console.error('Phoenix release missing erts-* directory');
    process.exit(1);
  }

  const beam = join(releaseRoot, ertsDir, 'bin', 'beam.smp');
  const description = beamArch(beam);
  const want = expectedMachArch();

  if (!description?.includes(want)) {
    console.error(`Phoenix release CPU mismatch: expected Mach-O ${want}, got: ${description}`);
    if (want === 'x86_64' && process.arch === 'arm64') {
      printIntelErlangHelp();
    }
    process.exit(1);
  }

  console.log(`Phoenix release arch OK (${want})`);
}

spawnSync('node', ['scripts/ensure-phoenix-sidecar-bundle.mjs'], {
  cwd: root,
  stdio: 'inherit',
});

console.log(
  `Phoenix prod build (darwin arch: ${darwinArch === 'native' ? 'host default' : darwinArch})`
);

runMix(['assets.deploy']);

const release = spawnSync('sh', ['-c', 'echo Y | mix release --overwrite'], {
  cwd: phoenixPath,
  stdio: 'inherit',
  env: prodMixEnv(),
});

if (release.status !== 0) {
  process.exit(release.status ?? 1);
}

const releaseSrc = join(phoenixPath, '_build/prod/rel/suchconfig_desktop');
verifyReleaseArch(releaseSrc);

const bundleRoot = join(root, 'src-tauri/bundle-resources/phoenix-sidecar');
const releaseDest = join(bundleRoot, 'suchconfig_desktop');

rmSync(bundleRoot, { recursive: true, force: true });
mkdirSync(bundleRoot, { recursive: true });
cpSync(releaseSrc, releaseDest, { recursive: true });
console.log(`Bundled Phoenix release → ${releaseDest}`);
