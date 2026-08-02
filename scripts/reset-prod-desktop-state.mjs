import { rmSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

const home = homedir();
const targets = [
  join(home, 'Library', 'Application Support', 'io.suchconfig'),
  join(home, 'Library', 'WebKit', 'io.suchconfig'),
  join(home, 'Library', 'Caches', 'io.suchconfig'),
];

for (const path of targets) {
  try {
    rmSync(path, { recursive: true, force: true });
    console.log('Removed', path);
  } catch (err) {
    console.error('Failed to remove', path, err.message);
    process.exit(1);
  }
}

console.log(
  'Production SuchConfig state cleared. Quit the app fully, then reopen (or reinstall the .dmg) for a first-run experience.'
);
