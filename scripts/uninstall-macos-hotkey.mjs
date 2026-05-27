#!/usr/bin/env node

import { execFile } from "node:child_process";
import { rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const labels = ["com.rajparekhinc.fast-grammer-fix", "com.raj.grammer-fix-fast"];
const launchAgentsDir = path.join(os.homedir(), "Library", "LaunchAgents");

async function main() {
  for (const label of labels) {
    const plistPath = path.join(launchAgentsDir, `${label}.plist`);
    await execFileAsync("launchctl", ["bootout", `gui/${process.getuid()}`, plistPath]).catch(() => {});
    await execFileAsync("launchctl", ["bootout", `gui/${process.getuid()}/${label}`]).catch(() => {});
    await rm(plistPath, { force: true });
  }

  console.log("Uninstalled Grammar Fix Fast launch agent.");
}

main().catch((error) => {
  console.error(error.stderr || error.stack || error.message);
  process.exit(1);
});
