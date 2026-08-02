import { spawnSync } from 'child_process';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const env = { ...process.env };

if (process.platform === 'darwin' && args[0] === 'build') {
  env.CI = 'true';
}

const r = spawnSync('pnpm', ['exec', 'tauri', ...args], {
  cwd: root,
  stdio: 'inherit',
  env,
});

process.exit(r.status ?? 1);
