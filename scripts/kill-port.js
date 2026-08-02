#!/usr/bin/env node

import { spawn } from 'child_process';
import { existsSync, unlinkSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

const PHOENIX_PID_FILE = join(projectRoot, '.phoenix-dev.pid');

function killProcesses() {
  console.log('🔪 Killing existing Phoenix/Elixir processes...');

  const processes = ['mix phx.server', 'iex -S mix', 'beam.smp'];

  return Promise.all(
    processes.map((pattern) => {
      return new Promise((resolve) => {
        const killProcess = spawn('pkill', ['-f', pattern], {
          stdio: ['ignore', 'pipe', 'pipe'],
        });

        killProcess.on('close', (code) => {
          if (code === 0) {
            console.log(`✅ Killed processes matching: ${pattern}`);
          } else {
            console.log(`⚠️  No processes found matching: ${pattern}`);
          }
          resolve();
        });

        killProcess.on('error', (error) => {
          if (error.code === 'ENOENT') {
            console.log(`⚠️  pkill command not found. Skipping: ${pattern}`);
          } else {
            console.log(
              `❌ Error killing processes matching ${pattern}: ${error.message}`
            );
          }
          resolve();
        });
      });
    })
  );
}

function cleanupFiles() {
  console.log('🧹 Cleaning up development files...');

  // Clean up PID file if it exists
  if (existsSync(PHOENIX_PID_FILE)) {
    try {
      unlinkSync(PHOENIX_PID_FILE);
      console.log('✅ Cleaned up Phoenix PID file');
    } catch (error) {
      console.log('⚠️  Could not remove PID file:', error.message);
    }
  }
}

async function main() {
  console.log('🧹 Cleaning up development environment...');

  await killProcesses();
  cleanupFiles();

  console.log('✨ Cleanup completed!');
  console.log('');
  console.log('Next steps:');
  console.log('1. Run: pnpm run tauri:dev');
  console.log('2. Or run: pnpm run clean-start (kills processes + starts dev)');
}

main().catch(console.error);
