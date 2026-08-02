#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, utimesSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = join(root, "design/sc-desktop/app-icon.svg");
const tauriIcons = join(root, "src-tauri/icons");
const phoenixImages = join(root, "phoenix-app/priv/static/images");
const buildRs = join(root, "src-tauri/build.rs");
const tauriDir = join(root, "src-tauri");
const iosColor = "#201f1d";

if (!existsSync(source)) {
  console.error(`Missing source icon: ${source}`);
  process.exit(1);
}

const result = spawnSync(
  "pnpm",
  ["exec", "tauri", "icon", source, "-o", tauriIcons, "--ios-color", iosColor],
  { cwd: root, stdio: "inherit", shell: process.platform === "win32" }
);

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

mkdirSync(phoenixImages, { recursive: true });

const faviconPng = join(tauriIcons, "32x32.png");
const faviconDest = join(phoenixImages, "favicon.png");

if (existsSync(faviconPng)) {
  copyFileSync(faviconPng, faviconDest);
}

const now = new Date();
utimesSync(buildRs, now, now);

const rebuild = spawnSync("cargo", ["build"], {
  cwd: tauriDir,
  stdio: "inherit",
});

if (rebuild.status !== 0) {
  process.exit(rebuild.status ?? 1);
}

console.log("Generated Tauri icons in src-tauri/icons/");
console.log("Synced phoenix favicon to phoenix-app/priv/static/images/favicon.png");
console.log("Rebuilt src-tauri debug binary with embedded icons.");
console.log("Quit and restart pnpm run tauri:dev to refresh the macOS dock icon.");
