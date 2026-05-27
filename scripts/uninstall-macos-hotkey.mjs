#!/usr/bin/env node

import { execFile } from "node:child_process";
import { rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const label = "com.raj.grammer-fix-fast";
const plistPath = path.join(os.homedir(), "Library", "LaunchAgents", `${label}.plist`);

async function main() {
  await execFileAsync("launchctl", ["bootout", `gui/${process.getuid()}`, plistPath]).catch(() => {});
  await rm(plistPath, { force: true });
  console.log("Uninstalled Grammar Fix Fast launch agent.");
}

main().catch((error) => {
  console.error(error.stderr || error.stack || error.message);
  process.exit(1);
});
