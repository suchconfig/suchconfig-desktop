#!/usr/bin/env node

import { spawn } from 'child_process';
import { existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

function buildPhoenix() {
  console.log('🔨 Building Phoenix LiveView for production...');

  const phoenixPath = process.env.SUCHCONFIG_DESKTOP_PATH || './phoenix-app';
  const mixPath = join(phoenixPath, 'mix.exs');

  if (!existsSync(mixPath)) {
    console.error(`❌ Phoenix project not found at: ${phoenixPath}`);
    console.error(
      'Please ensure suchconfig-desktop exists and the path is correct.'
    );
    console.error(
      'You can set SUCHCONFIG_DESKTOP_PATH environment variable to override the path.'
    );
    process.exit(1);
  }

  return new Promise((resolve, reject) => {
    const buildProcess = spawn('mix', ['release'], {
      cwd: phoenixPath,
      stdio: 'inherit',
      env: { ...process.env, MIX_ENV: 'prod' },
    });

    buildProcess.on('close', (code) => {
      if (code === 0) {
        console.log('✅ Phoenix LiveView build completed successfully!');
        resolve();
      } else {
        console.error(`❌ Phoenix build failed with code ${code}`);
        reject(new Error(`Build failed with code ${code}`));
      }
    });

    buildProcess.on('error', (error) => {
      console.error('Failed to build Phoenix:', error);
      reject(error);
    });
  });
}

buildPhoenix().catch((error) => {
  console.error('Build failed:', error);
  process.exit(1);
});
