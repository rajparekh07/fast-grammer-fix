# Grammar Fix Fast

Rewrite selected text anywhere on macOS with a global hotkey powered by Codex CLI.

Select text, press `ctrl+option+cmd+g`, wait for the small status bubble, and the selected text is replaced with the corrected version.

## What It Does

- Reads the currently selected text using macOS copy/paste automation.
- Sends that text to `codex exec` with `gpt-5.4-mini`.
- Pastes the returned replacement over the original selection.
- Restores your previous clipboard after pasting.
- Runs as a small background LaunchAgent.

The LaunchAgent and app bundle use the identifier:

```text
com.rajparekhinc.fast-grammer-fix
```

## Requirements

- macOS
- Node.js 20 or newer
- Swift compiler/Xcode command line tools
- Codex CLI installed and logged in

Check Codex first:

```sh
codex --version
codex login
```

## Install

From this repo:

```sh
npm run install:hotkey
```

The installer will:

1. Compile the native macOS helper app.
2. Sign the app bundle locally.
3. Register it as a LaunchAgent.
4. Start it immediately.

On first use, macOS will ask for Accessibility permission. Click **Open System Settings**, then enable **GrammarFixFast** under:

```text
System Settings -> Privacy & Security -> Accessibility
```

If the toggle is already on but macOS asks again, turn **GrammarFixFast** off and back on. macOS sometimes keeps a stale permission entry after a helper app is rebuilt.

## Use

1. Select text in any app.
2. Press `ctrl+option+cmd+g`.
3. The bubble shows progress while Codex rewrites the text.
4. The selected text is replaced when Codex returns.

Example:

```text
this are bad sentence
```

becomes:

```text
this is a bad sentence
```

## Test Without The Hotkey

You can test the Codex rewrite command directly:

```sh
echo "this are bad sentence" | npm run rewrite
```

## Customize

Set environment variables before running `npm run install:hotkey`.

```sh
GRAMMER_FIX_HOTKEY=cmd+shift+g npm run install:hotkey
```

Useful options:

- `GRAMMER_FIX_MODEL`: Codex model name. Defaults to `gpt-5.4-mini`.
- `GRAMMER_FIX_HOTKEY`: Hotkey string. Defaults to `ctrl+option+cmd+g`.
- `GRAMMER_FIX_INSTRUCTION`: Rewrite instruction sent to Codex.
- `CODEX_CLI_PATH`: Explicit path to the `codex` binary.
- `GRAMMER_FIX_RESTORE_CLIPBOARD=0`: Keep the replacement on the clipboard instead of restoring the previous clipboard.

## Privacy

The app does not store or print your Codex auth token.

The selected text is sent to Codex because it is the input being rewritten. The rewrite command uses `codex exec --ephemeral`, writes the final response to a temporary file, reads it, and deletes the temporary directory.

Generated app artifacts live in `dist/`, which is ignored by git.

## Troubleshooting

If the hotkey does nothing:

```sh
launchctl print gui/$(id -u)/com.rajparekhinc.fast-grammer-fix
tail -n 50 ~/Library/Logs/GrammarFixFast/err.log
```

If Accessibility permission looks enabled but macOS still prompts:

1. Open `System Settings -> Privacy & Security -> Accessibility`.
2. Toggle **GrammarFixFast** off.
3. Toggle **GrammarFixFast** back on.
4. Run `npm run install:hotkey` again.

## Uninstall

```sh
npm run uninstall:hotkey
```
