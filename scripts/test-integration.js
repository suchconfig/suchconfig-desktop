#!/usr/bin/env node

import { existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

async function testIntegration() {
  console.log('🧪 Testing SuchConfig Tauri + Phoenix Integration...\n');

  const phoenixPath = process.env.SUCHCONFIG_DESKTOP_PATH || './phoenix-app';
  const phoenixMixPath = join(phoenixPath, 'mix.exs');

  console.log('1. Checking Phoenix Desktop App...');
  if (existsSync(phoenixMixPath)) {
    console.log('   ✅ suchconfig-desktop found at:', phoenixPath);
  } else {
    console.log('   ❌ suchconfig-desktop not found at:', phoenixPath);
    console.log(
      '   💡 Set SUCHCONFIG_DESKTOP_PATH environment variable to correct path'
    );
    return false;
  }

  console.log('\n2. Checking Tauri Configuration...');
  const tauriConfigPath = join(projectRoot, 'src-tauri', 'tauri.conf.json');
  if (existsSync(tauriConfigPath)) {
    console.log('   ✅ Tauri configuration found');
  } else {
    console.log('   ❌ Tauri configuration not found');
    return false;
  }

  console.log('\n3. Checking Scripts...');
  const scripts = [
    'scripts/start-phoenix-dev.js',
    'scripts/build-phoenix.js',
    'scripts/stop-phoenix.js',
  ];

  let allScriptsExist = true;
  scripts.forEach((script) => {
    const scriptPath = join(projectRoot, script);
    if (existsSync(scriptPath)) {
      console.log(`   ✅ ${script} exists`);
    } else {
      console.log(`   ❌ ${script} missing`);
      allScriptsExist = false;
    }
  });

  if (!allScriptsExist) {
    return false;
  }

  console.log('\n4. Checking Package.json Scripts...');
  try {
    const fs = await import('fs');
    const packageJson = JSON.parse(
      fs.readFileSync(join(projectRoot, 'package.json'), 'utf8')
    );
    const requiredScripts = [
      'start-phoenix-dev',
      'build-phoenix',
      'stop-phoenix',
    ];

    requiredScripts.forEach((script) => {
      if (packageJson.scripts[script]) {
        console.log(`   ✅ Script '${script}' configured`);
      } else {
        console.log(`   ❌ Script '${script}' missing`);
        allScriptsExist = false;
      }
    });
  } catch (error) {
    console.log('   ❌ Error reading package.json:', error.message);
    return false;
  }

  console.log('\n🎉 Integration test completed successfully!');
  console.log('\nNext steps:');
  console.log('1. Run: pnpm run start-phoenix-dev');
  console.log('2. Run: pnpm run tauri:dev');
  console.log('3. Test the integration in the Tauri window');

  return true;
}

testIntegration().catch(console.error);
