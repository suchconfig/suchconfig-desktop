#!/usr/bin/env node

import { spawn } from 'child_process';
import { existsSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

function createPhoenixApp() {
  console.log('🏗️  Creating embedded Phoenix LiveView application...');

  const phoenixPath = join(projectRoot, 'phoenix-app');

  if (existsSync(phoenixPath)) {
    console.log('✅ Phoenix app already exists at:', phoenixPath);
    return;
  }

  console.log('Creating Phoenix app directory...');
  mkdirSync(phoenixPath, { recursive: true });

  return new Promise((resolve, reject) => {
    const mixProcess = spawn('mix', ['new', 'suchconfig_desktop', '--sup'], {
      cwd: phoenixPath,
      stdio: 'inherit',
    });

    mixProcess.on('close', (code) => {
      if (code === 0) {
        console.log('✅ Phoenix app created successfully!');
        console.log('\nNext steps:');
        console.log('1. cd phoenix-app');
        console.log('2. mix deps.get');
        console.log('3. mix phx.new . --app suchconfig_desktop --live');
        console.log('4. mix deps.get');
        resolve();
      } else {
        console.error('❌ Failed to create Phoenix app');
        reject(new Error(`Mix process exited with code ${code}`));
      }
    });

    mixProcess.on('error', (error) => {
      console.error('Failed to create Phoenix app:', error);
      reject(error);
    });
  });
}

createPhoenixApp().catch((error) => {
  console.error('Setup failed:', error);
  process.exit(1);
});
