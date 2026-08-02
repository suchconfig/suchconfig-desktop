#!/usr/bin/env node

import { existsSync, readFileSync, unlinkSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

const PHOENIX_PID_FILE = join(projectRoot, '.phoenix-dev.pid');

function stopPhoenix() {
  console.log('🛑 Stopping Phoenix LiveView server...');

  if (!existsSync(PHOENIX_PID_FILE)) {
    console.log('No Phoenix server PID file found. Server may not be running.');
    return;
  }

  try {
    const pid = parseInt(readFileSync(PHOENIX_PID_FILE, 'utf8').trim());

    if (process.platform === 'win32') {
      require('child_process').exec(`taskkill /PID ${pid} /F`, (error) => {
        if (error) {
          console.error('Failed to stop Phoenix server:', error);
        } else {
          console.log('✅ Phoenix server stopped successfully!');
        }
        unlinkSync(PHOENIX_PID_FILE);
      });
    } else {
      process.kill(pid, 'SIGTERM');
      console.log('✅ Phoenix server stopped successfully!');
      unlinkSync(PHOENIX_PID_FILE);
    }
  } catch (error) {
    console.error('Failed to stop Phoenix server:', error);
    if (existsSync(PHOENIX_PID_FILE)) {
      unlinkSync(PHOENIX_PID_FILE);
    }
  }
}

stopPhoenix();
