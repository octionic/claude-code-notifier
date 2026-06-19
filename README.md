# Claude Code Notifier

Desktop notifications for **Claude Code CLI** — get notified when Claude needs
your attention (permission prompts, dialogs) or finishes a response.

On macOS, **clicking the notification jumps straight to the VS Code window/tab**
for that session's folder. Optionally, when your screensaver is on, the
notification is pushed to your phone via [ntfy.sh](https://ntfy.sh) instead.

> [!IMPORTANT]
> **This is primarily designed for [VS Code](https://code.visualstudio.com/).**
> VS Code supports macOS **native window tabs** *and* exposes a `vscode://file/…`
> URL handler, so clicking a notification can focus the **exact window/tab** that
> has the session's folder open.
>
> It **also works in regular terminals** (iTerm, Apple Terminal, Termius, …): the
> notification fires, shows that terminal's icon, and clicking brings the terminal
> **app** to the front. But terminals have **no per-tab URL scheme**, so if you
> have multiple tabs/windows open, the click **cannot distinguish which tab** the
> session is in — it just focuses the app. Precise tab targeting is a VS Code-only
> capability.

> Adapted from [hta218/ai-agents-notifier](https://github.com/hta218/ai-agents-notifier).

---

## What you need

Everything lives in **one script** plus a few lines in your Claude Code
settings. To set it up on a new machine you need:

1. `claude-code-notifier.sh` — the script (in this repo)
2. The hook entries in `~/.claude/settings.json` (see `settings.example.json`)
3. The notification tool for your OS:
   - **macOS:** [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) + [`jq`](https://stedolan.github.io/jq/)
   - **Linux:** `notify-send` (from `libnotify-bin`) + `jq`
   - **Windows:** PowerShell (built in) + `jq`

---

## Setup

### 1. Install dependencies

**macOS** (with [Homebrew](https://brew.sh)):

```bash
brew install terminal-notifier jq
```

**Linux** (Debian/Ubuntu):

```bash
sudo apt install libnotify-bin jq
```

### 2. Install the script

```bash
cp claude-code-notifier.sh ~/.claude/claude-code-notifier.sh
chmod +x ~/.claude/claude-code-notifier.sh
```

### 3. Register the hooks

Merge the contents of `settings.example.json` into `~/.claude/settings.json`.
If you don't already have a `settings.json`, you can just copy the example:

```bash
cp settings.example.json ~/.claude/settings.json
```

If you already have one, merge the `"hooks"` block into it (keep your other
settings intact). The hooks configured here fire on:

| Event          | Matcher             | When it fires                              |
| -------------- | ------------------- | ------------------------------------------ |
| `Notification` | `permission_prompt` | Claude asks permission to run something    |
| `Notification` | `elicitation_dialog`| Claude shows an input/choice dialog        |
| `Stop`         | *(none)*            | Claude finishes a response                 |

> No restart needed — Claude Code reads hooks on each invocation.

### 4. Test it

```bash
echo '{"hook_event_name":"Notification","message":"Hello from the notifier","cwd":"'"$PWD"'"}' \
  | ~/.claude/claude-code-notifier.sh
```

A banner should appear. On macOS, clicking it should open/focus VS Code on the
current folder.

---

## Configuration (optional)

The script reads two environment variables. Set them in your shell profile
(`~/.zshrc`, `~/.bashrc`) if you want to change the defaults:

| Variable                  | Default  | Purpose                                                                 |
| ------------------------- | -------- | ----------------------------------------------------------------------- |
| `CLAUDE_NTFY_CHANNEL`     | *(empty)*| ntfy.sh channel for remote push while the screensaver is active. Empty = remote push disabled. |
| `CLAUDE_NOTIFIER_SCHEME`  | `vscode` | Editor URL scheme for the VS Code click action. Use `vscode-insiders`, `cursor`, or `windsurf` as appropriate. |
| `CLAUDE_NOTIFIER_ICON`    | *(auto)* | Path to an `.icns`/`.png` for the notification thumbnail. Defaults to the detected terminal's own icon. |

Example:

```bash
export CLAUDE_NTFY_CHANNEL="my-private-channel"
export CLAUDE_NOTIFIER_SCHEME="vscode-insiders"
```

For remote push, install the [ntfy app](https://ntfy.sh/app) on your phone and
subscribe to the same channel name.

---

## How the click-to-focus works (macOS)

The script detects which terminal Claude Code is running in via the
`$TERM_PROGRAM` environment variable and adapts both the icon and the click:

| Terminal (`$TERM_PROGRAM`) | Icon shown | Click action |
| -------------------------- | ---------- | ------------ |
| VS Code (`vscode`)         | VS Code    | Opens `vscode://file/<cwd>` → focuses the **exact window/tab** for that folder |
| iTerm (`iTerm.app`)        | iTerm      | Brings **iTerm** to the front (cannot target a specific tab) |
| Terminal (`Apple_Terminal`)| Terminal   | Brings **Terminal** to the front (cannot target a specific tab) |
| Termius (`*termius*`)      | Termius    | Brings **Termius** to the front (cannot target a specific tab) |
| Anything else / unknown    | default    | Notification only, no click action |

For VS Code, the session's working directory (`cwd`, supplied by Claude Code) is
turned into a `vscode://file/…` URL and attached via `terminal-notifier -execute`.
Clicking runs `open "<that url>"`, and VS Code focuses the existing window (a
native macOS tab) that already has that folder open. No Accessibility permission
is required.

The icon is shown as a right-side thumbnail via `-contentImage`. On modern macOS
the small **corner** icon is always the delivering app (`terminal-notifier`) and
can't be changed without `-sender`.

**Gotcha:** do **not** add `terminal-notifier`'s `-sender` flag. It overrides
`-execute`/`-activate`, so the click would just activate the sender app instead
of running the URL open — and the jump-to-tab stops working.

### Claude Code Desktop is excluded

When Claude Code runs in the **Desktop app** (`CLAUDE_CODE_ENTRYPOINT=claude-desktop`)
the script exits early and shows nothing — the Desktop app has its own
notifications, and there is no terminal/editor tab to jump to. Notifications only
fire for terminal/CLI sessions.

---

## Troubleshooting

- **Clicking the notification does nothing (macOS):** make sure `-sender` is not
  set (see gotcha above), and verify the URL works manually:
  `open "vscode://file$PWD"`.
- **Opens the wrong/a new window:** this matches on the folder in `cwd`. It
  assumes one editor window per project and that the session runs at the
  workspace root. Subfolder sessions may open a different window.
- **No notification at all (macOS):** confirm `terminal-notifier` is installed
  (`which terminal-notifier`) and that notifications aren't blocked by a Focus
  mode / Do Not Disturb.
- **Nothing happens in a terminal session:** the click only *focuses the app*
  for non-VS-Code terminals — it can't pick the tab. For unknown terminals there
  is no click action at all. Check what your terminal reports with
  `echo "$TERM_PROGRAM"` and open an issue/PR to add it.
- **Termius over SSH doesn't notify:** if Claude Code runs on a **remote** host
  via SSH, the hook executes remotely, where there's no `terminal-notifier` and
  no access to your Mac's notifications. This only works for **local** sessions.
- **`jq: command not found`:** install `jq` (see step 1).

---

## Platform support

| Platform | Notification backend | Click-to-focus |
| -------- | -------------------- | -------------- |
| macOS    | `terminal-notifier`  | ✅ exact tab in VS Code; app-only focus in other terminals |
| Linux    | `notify-send`        | ❌ not implemented |
| Windows  | PowerShell toast     | ❌ not implemented |
