#!/usr/bin/env node

import { spawn, spawnSync } from 'child_process';
import { existsSync, unlinkSync, writeFileSync } from 'fs';
import http from 'http';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

spawnSync('node', ['scripts/ensure-phoenix-sidecar-bundle.mjs'], {
  cwd: projectRoot,
  stdio: 'inherit',
});

const PHOENIX_PID_FILE = join(projectRoot, '.phoenix-dev.pid');
const PHOENIX_PORT = 4000;

function killPort(port) {
  if (process.platform === 'win32') {
    return;
  }

  spawnSync('bash', ['-lc', `lsof -ti :${port} | xargs kill -TERM 2>/dev/null || true`], {
    stdio: 'inherit',
  });
}

async function stopExistingPhoenix() {
  spawnSync('node', ['scripts/stop-phoenix.js'], {
    cwd: projectRoot,
    stdio: 'inherit',
  });
  killPort(PHOENIX_PORT);
  await new Promise((resolve) => setTimeout(resolve, 500));
}

function checkServerReady(port) {
  return new Promise((resolve) => {
    const req = http.get(`http://127.0.0.1:${port}`, (res) => {
      res.on('data', () => {});
      res.on('end', () => {
        resolve(res.statusCode >= 200 && res.statusCode < 600);
      });
    });
    req.on('error', () => resolve(false));
    req.setTimeout(1000, () => {
      req.destroy();
      resolve(false);
    });
  });
}

async function waitForServer(port, maxWait = 60000) {
  const startTime = Date.now();
  while (Date.now() - startTime < maxWait) {
    if (await checkServerReady(port)) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  return false;
}

async function startPhoenixDev() {
  console.log('🚀 Starting Phoenix LiveView development server...');

  const phoenixPath = process.env.SUCHCONFIG_DESKTOP_PATH || './phoenix-app';
  const phoenixMixPath = join(phoenixPath, 'mix.exs');

  if (!existsSync(phoenixMixPath)) {
    console.error(`❌ Phoenix project not found at: ${phoenixPath}`);
    console.error(
      'Please ensure phoenix-app exists and contains a Phoenix project.'
    );
    console.error(
      'You can set SUCHCONFIG_DESKTOP_PATH environment variable to override the path.'
    );
    process.exit(1);
  }

  if (await checkServerReady(PHOENIX_PORT)) {
    if (process.env.SUCHCONFIG_REUSE_PHOENIX === '1') {
      console.log(`✅ Phoenix server is already running on port ${PHOENIX_PORT}`);
      console.log('Keeping process alive for Tauri (SUCHCONFIG_REUSE_PHOENIX=1)...');

      process.on('SIGINT', () => {
        console.log('\n🛑 Received SIGINT');
        process.exit(0);
      });

      process.on('SIGTERM', () => {
        console.log('🛑 Received SIGTERM');
        process.exit(0);
      });

      setInterval(async () => {
        if (!(await checkServerReady(PHOENIX_PORT))) {
          console.warn('⚠️  Phoenix server appears to have stopped');
        }
      }, 10000);

      return;
    }

    console.log(
      `♻️  Restarting Phoenix on port ${PHOENIX_PORT} to pick up Elixir and asset changes...`
    );
    await stopExistingPhoenix();

    if (await checkServerReady(PHOENIX_PORT)) {
      console.error(
        `❌ Phoenix is still running on port ${PHOENIX_PORT}. Run: pnpm run stop-phoenix && pnpm run kill-port`
      );
      process.exit(1);
    }
  }

  console.log('📦 Running database migrations (mix ecto.migrate)...');
  const migrate = spawnSync('mix', ['ecto.migrate'], {
    cwd: phoenixPath,
    stdio: 'inherit',
    env: process.env,
  });
  if (migrate.status !== 0) {
    console.error(
      '❌ mix ecto.migrate failed. From phoenix-app try: mix ecto.create && mix ecto.migrate'
    );
    process.exit(migrate.status ?? 1);
  }

  const phoenixProcess = spawn('mix', ['phx.server'], {
    cwd: phoenixPath,
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: false,
  });

  phoenixProcess.stdout.on('data', (data) => {
    const output = data.toString();
    console.log(`[Phoenix] ${output.trim()}`);
  });

  phoenixProcess.stderr.on('data', (data) => {
    const error = data.toString();
    console.error(`[Phoenix Error] ${error.trim()}`);
  });

  phoenixProcess.on('close', (code) => {
    console.log(`Phoenix process exited with code ${code}`);
    if (existsSync(PHOENIX_PID_FILE)) {
      unlinkSync(PHOENIX_PID_FILE);
    }
    process.exit(code || 0);
  });

  phoenixProcess.on('error', (error) => {
    console.error('Failed to start Phoenix server:', error);
    process.exit(1);
  });

  writeFileSync(PHOENIX_PID_FILE, phoenixProcess.pid.toString());
  console.log(`Phoenix server started with PID: ${phoenixProcess.pid}`);

  (async () => {
    console.log('⏳ Waiting for Phoenix server to be ready...');
    const ready = await waitForServer(PHOENIX_PORT);
    if (ready) {
      console.log('✅ Phoenix LiveView server is ready!');
    } else {
      console.warn('⚠️  Phoenix server did not become ready in time');
    }
  })();

  process.on('SIGINT', () => {
    console.log('\n🛑 Stopping Phoenix server...');
    phoenixProcess.kill('SIGTERM');
    if (existsSync(PHOENIX_PID_FILE)) {
      unlinkSync(PHOENIX_PID_FILE);
    }
    process.exit(0);
  });

  process.on('SIGTERM', () => {
    phoenixProcess.kill('SIGTERM');
    if (existsSync(PHOENIX_PID_FILE)) {
      unlinkSync(PHOENIX_PID_FILE);
    }
    process.exit(0);
  });
}

startPhoenixDev();
