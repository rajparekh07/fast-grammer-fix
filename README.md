# Grammar Fix Fast

A tiny macOS hotkey app that rewrites the currently selected text with Codex CLI and pastes the result back over the selection.

Default hotkey: `ctrl+option+cmd+g`

## Install

```sh
npm run install:hotkey
```

The installer compiles a small background macOS app, registers it as a LaunchAgent, and starts it immediately.

On first use, macOS will ask for Accessibility permission. Allow `Grammar Fix Fast`; it needs that permission to copy the selected text and paste the replacement.

## Use

1. Select text in any macOS app.
2. Press `ctrl+option+cmd+g`.
3. A small bubble appears while Codex rewrites the text.
4. The selected text is replaced when the model returns.

## Model and Behavior

The JS rewrite command calls:

```sh
codex exec --model gpt-5.4-mini
```

You can override defaults before installing:

```sh
GRAMMER_FIX_MODEL=gpt-5.4-mini GRAMMER_FIX_HOTKEY=ctrl+option+cmd+g npm run install:hotkey
```

Useful environment variables:

- `GRAMMER_FIX_MODEL`: Codex model name. Defaults to `gpt-5.4-mini`.
- `GRAMMER_FIX_HOTKEY`: Hotkey string, such as `ctrl+option+cmd+g` or `cmd+shift+g`.
- `GRAMMER_FIX_INSTRUCTION`: Rewrite instruction sent to Codex.
- `CODEX_CLI_PATH`: Explicit path to the `codex` binary if your shell cannot find it.
- `GRAMMER_FIX_RESTORE_CLIPBOARD=0`: Keep the replacement on the clipboard instead of restoring the previous clipboard.

## Test the JS command directly

```sh
echo "this are bad sentence" | npm run rewrite
```

## Uninstall

```sh
npm run uninstall:hotkey
```
