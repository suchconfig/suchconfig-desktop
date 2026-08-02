import { chmodSync, cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const phoenixRelease = join(root, 'phoenix-app/_build/prod/rel/suchconfig_desktop');
const bundleRoot = join(root, 'src-tauri/bundle-resources/phoenix-sidecar/suchconfig_desktop');
const binPath = join(bundleRoot, 'bin/suchconfig_desktop');

function releaseLooksValid(dir) {
  return (
    existsSync(join(dir, 'bin/suchconfig_desktop')) &&
    existsSync(join(dir, 'releases'))
  );
}

function writeStub() {
  mkdirSync(join(bundleRoot, 'bin'), { recursive: true });
  mkdirSync(join(bundleRoot, 'releases'), { recursive: true });
  writeFileSync(
    binPath,
    '#!/bin/sh\necho "Phoenix sidecar missing. Run: node scripts/phoenix-prod-build.mjs" >&2\nexit 1\n'
  );
  chmodSync(binPath, 0o755);
}

if (releaseLooksValid(bundleRoot)) {
  process.exit(0);
}

if (releaseLooksValid(phoenixRelease)) {
  rmSync(dirname(bundleRoot), { recursive: true, force: true });
  mkdirSync(dirname(bundleRoot), { recursive: true });
  cpSync(phoenixRelease, bundleRoot, { recursive: true });
  process.exit(0);
}

writeStub();
