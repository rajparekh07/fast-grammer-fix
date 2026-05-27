#!/usr/bin/env node

import { execFile } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const label = "com.rajparekhinc.fast-grammer-fix";
const legacyLabels = ["com.raj.grammer-fix-fast"];
const appDir = path.join(root, "dist", "GrammarFixFast.app");
const contentsDir = path.join(appDir, "Contents");
const macosDir = path.join(contentsDir, "MacOS");
const binaryPath = path.join(macosDir, "GrammarFixFast");
const swiftPath = path.join(root, "native", "GrammarFixFast.swift");
const launchAgentsDir = path.join(os.homedir(), "Library", "LaunchAgents");
const plistPath = path.join(launchAgentsDir, `${label}.plist`);
const logDir = path.join(os.homedir(), "Library", "Logs", "GrammarFixFast");

async function main() {
  await mkdir(macosDir, { recursive: true });
  await mkdir(launchAgentsDir, { recursive: true });
  await mkdir(logDir, { recursive: true });

  console.log("Compiling macOS hotkey app...");
  await execFileAsync("swiftc", [
    "-O",
    "-framework",
    "AppKit",
    "-framework",
    "ApplicationServices",
    "-framework",
    "Carbon",
    "-o",
    binaryPath,
    swiftPath,
  ]);

  const codexPath = await resolveCodexPath();

  await writeFile(path.join(contentsDir, "Info.plist"), infoPlist(), "utf8");
  console.log("Signing macOS hotkey app...");
  await execFileAsync("codesign", ["--force", "--deep", "--sign", "-", appDir]);

  await writeFile(plistPath, launchAgentPlist(codexPath), "utf8");

  await removeLegacyLaunchAgents();
  await launchctl(["bootout", `gui/${process.getuid()}`, plistPath]).catch(() => {});
  await launchctl(["bootstrap", `gui/${process.getuid()}`, plistPath]);
  await launchctl(["kickstart", "-k", `gui/${process.getuid()}/${label}`]).catch(() => {});

  console.log(`Installed Grammar Fix Fast.`);
  console.log(`Hotkey: ${process.env.GRAMMER_FIX_HOTKEY || "ctrl+option+cmd+g"}`);
  console.log("On first use, allow Accessibility access when macOS asks.");
}

function infoPlist() {
  return xmlPlist(`
  <dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>GrammarFixFast</string>
    <key>CFBundleIdentifier</key>
    <string>${escapeXml(label)}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Grammar Fix Fast</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
  </dict>`);
}

async function resolveCodexPath() {
  if (process.env.CODEX_CLI_PATH) {
    return process.env.CODEX_CLI_PATH;
  }

  const { stdout } = await execFileAsync("/bin/zsh", ["-lc", "command -v codex"], {
    env: process.env,
    timeout: 10_000,
  });

  const codexPath = stdout.trim().split("\n")[0];
  if (!codexPath) {
    throw new Error("Could not find Codex CLI. Install/login first, or set CODEX_CLI_PATH.");
  }

  return codexPath;
}

function launchAgentPlist(codexPath) {
  const environment = {
    GRAMMER_FIX_SCRIPT: path.join(root, "bin", "grammer-fix-fast.mjs"),
    GRAMMER_FIX_NODE: process.execPath,
    GRAMMER_FIX_MODEL: process.env.GRAMMER_FIX_MODEL || process.env.GRAMMAR_FIX_MODEL || "gpt-5.4-mini",
    GRAMMER_FIX_HOTKEY: process.env.GRAMMER_FIX_HOTKEY || "ctrl+option+cmd+g",
    CODEX_CLI_PATH: codexPath,
    PATH: launchAgentPath(codexPath),
  };

  return xmlPlist(`
  <dict>
    <key>Label</key>
    <string>${escapeXml(label)}</string>
    <key>ProgramArguments</key>
    <array>
      <string>${escapeXml(binaryPath)}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${escapeXml(path.join(logDir, "out.log"))}</string>
    <key>StandardErrorPath</key>
    <string>${escapeXml(path.join(logDir, "err.log"))}</string>
    <key>EnvironmentVariables</key>
    <dict>
      ${Object.entries(environment)
        .map(([key, value]) => `<key>${escapeXml(key)}</key>\n      <string>${escapeXml(value)}</string>`)
        .join("\n      ")}
    </dict>
  </dict>`);
}

function launchAgentPath(codexPath) {
  const home = os.homedir();
  const values = [
    process.env.PATH || "",
    path.dirname(process.execPath),
    codexPath ? path.dirname(codexPath) : "",
    path.join(home, ".local/bin"),
    path.join(home, ".npm-global/bin"),
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ];

  return [...new Set(values.flatMap((value) => value.split(":")).filter(Boolean))].join(":");
}

function xmlPlist(body) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
${body.trim()}
</plist>
`;
}

function escapeXml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

async function launchctl(args) {
  return execFileAsync("launchctl", args, { timeout: 15_000 });
}

async function removeLegacyLaunchAgents() {
  for (const legacyLabel of legacyLabels) {
    const legacyPlistPath = path.join(launchAgentsDir, `${legacyLabel}.plist`);
    await launchctl(["bootout", `gui/${process.getuid()}`, legacyPlistPath]).catch(() => {});
    await launchctl(["bootout", `gui/${process.getuid()}/${legacyLabel}`]).catch(() => {});
    await rm(legacyPlistPath, { force: true });
  }
}

main().catch((error) => {
  console.error(error.stderr || error.stack || error.message);
  process.exit(1);
});
