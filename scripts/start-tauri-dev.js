#!/usr/bin/env node

import { spawn } from 'child_process';
import http from 'http';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

function checkServerReady(port) {
  return new Promise((resolve) => {
    const req = http.get(`http://127.0.0.1:${port}`, (res) => {
      res.on('data', () => {});
      res.on('end', () => {
        resolve(res.statusCode >= 200 && res.statusCode < 600);
      });
    });
    req.on('error', () => resolve(false));
    req.setTimeout(2000, () => {
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
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return false;
}

async function main() {
  console.log('🚀 Starting Phoenix and Tauri development...');

  const isPhoenixReady = await checkServerReady(4000);
  let phoenixProcess = null;

  if (!isPhoenixReady) {
    console.log('📦 Starting Phoenix server...');
    phoenixProcess = spawn('node', [join(__dirname, 'start-phoenix-dev.js')], {
      cwd: projectRoot,
      stdio: 'pipe',
      detached: false,
    });

    phoenixProcess.stdout.on('data', (data) => {
      process.stdout.write(data);
    });

    phoenixProcess.stderr.on('data', (data) => {
      process.stderr.write(data);
    });

    phoenixProcess.on('error', (error) => {
      console.error('Failed to start Phoenix:', error);
      process.exit(1);
    });

    console.log('⏳ Waiting for Phoenix server to be ready...');
    const ready = await waitForServer(4000);

    if (!ready) {
      console.error('❌ Phoenix server did not become ready in time');
      if (phoenixProcess) {
        phoenixProcess.kill('SIGTERM');
      }
      process.exit(1);
    }
  } else {
    console.log('✅ Phoenix server is already running');
  }

  console.log('🚀 Starting Tauri...');

  console.log('⏳ Waiting a moment for Phoenix to fully initialize...');
  await new Promise((resolve) => setTimeout(resolve, 2000));

  const tauriProcess = spawn('pnpm', ['tauri', 'dev', '--no-dev-server-wait'], {
    cwd: projectRoot,
    stdio: 'inherit',
    detached: false,
  });

  tauriProcess.on('error', (error) => {
    console.error('Failed to start Tauri:', error);
    if (phoenixProcess) {
      phoenixProcess.kill('SIGTERM');
    }
    process.exit(1);
  });

  process.on('SIGINT', () => {
    console.log('\n🛑 Stopping processes...');
    if (phoenixProcess) {
      phoenixProcess.kill('SIGTERM');
    }
    tauriProcess.kill('SIGTERM');
    process.exit(0);
  });

  process.on('SIGTERM', () => {
    if (phoenixProcess) {
      phoenixProcess.kill('SIGTERM');
    }
    tauriProcess.kill('SIGTERM');
    process.exit(0);
  });

  const exitCode = await new Promise((resolve) => {
    tauriProcess.on('exit', (code) => {
      if (phoenixProcess) {
        phoenixProcess.kill('SIGTERM');
      }
      resolve(code || 0);
    });
  });

  process.exit(exitCode);
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
