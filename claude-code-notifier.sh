#!/bin/bash

#==============================================================================
# Claude Code Notification Hook Script
#
# Shows a desktop notification when Claude Code needs your attention
# (permission prompts, dialogs) or finishes a response.
#
# macOS extras:
#   - Clicking the notification opens VS Code and focuses the window/native
#     tab for the session's working directory (via the editor URL handler).
#   - If a screensaver is active and a ntfy.sh channel is configured, the
#     notification is sent to your phone via ntfy.sh instead of the desktop.
#
# See README.md for setup instructions.
#==============================================================================

#------------------------------------------------------------------------------
# Configuration (override via environment variables)
#------------------------------------------------------------------------------
# ntfy.sh channel for remote push when the screensaver is on. Leave empty to
# disable remote push (the script will just show a local notification).
#   export CLAUDE_NTFY_CHANNEL="my-channel"
NTFY_CHANNEL="${CLAUDE_NTFY_CHANNEL:-}"

# URL scheme of your editor, used for the click-to-focus action on macOS:
#   vscode           -> VS Code (default)
#   vscode-insiders  -> VS Code Insiders
#   cursor           -> Cursor
#   windsurf         -> Windsurf
#   export CLAUDE_NOTIFIER_SCHEME="vscode-insiders"
EDITOR_SCHEME="${CLAUDE_NOTIFIER_SCHEME:-vscode}"

#------------------------------------------------------------------------------
# Read JSON input from stdin (Claude Code passes the hook payload here)
#------------------------------------------------------------------------------
input=$(cat)

# Skip entirely when running inside the Claude Code Desktop app: it has its
# own notifications, and the editor click action would hijack an unrelated
# window. Only notify for terminal/CLI sessions (iTerm, Terminal, VS Code).
if [ "$CLAUDE_CODE_ENTRYPOINT" = "claude-desktop" ]; then
  exit 0
fi

message=$(echo "$input" | jq -r '.message // "Claude Code Notification"')
hook_event=$(echo "$input" | jq -r '.hook_event_name // "Unknown"')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# Fallback if jq is not available
if [ $? -ne 0 ] || [ "$message" = "null" ]; then
  message="Claude Code Notification"
fi

# Project/folder name for the session (used in titles and the ntfy push)
project_name=""
[ -n "$cwd" ] && project_name=$(basename "$cwd")

# Title shown at the top of notifications: "Claude Code — <project>"
notify_title="Claude Code"
[ -n "$project_name" ] && notify_title="Claude Code — $project_name"

#------------------------------------------------------------------------------
# Customize message based on event type
#------------------------------------------------------------------------------
case "$hook_event" in
  "SessionStart")
    message="Session started 🚀"
    ;;
  "SessionEnd")
    message="Session completed ✅"
    ;;
  "Stop")
    message="Response finished 🏁"
    ;;
  "Notification")
    # Keep the original message from Claude (e.g. permission request)
    ;;
  *)
    message="$hook_event: $message"
    ;;
esac

#------------------------------------------------------------------------------
# Detect whether a screensaver is active
#------------------------------------------------------------------------------
screensaver_active() {
  case "$(uname -s)" in
    Darwin*)
      pgrep -x ScreenSaverEngine >/dev/null 2>&1
      ;;
    Linux*)
      if command -v xdg-screensaver >/dev/null 2>&1; then
        xdg-screensaver status 2>/dev/null | grep -q "enabled"
      elif command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -q 2>/dev/null | grep -q "is active"
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

#------------------------------------------------------------------------------
# Send notification via ntfy.sh (remote push to phone)
#------------------------------------------------------------------------------
send_ntfy() {
  curl -s -H "Title: ${notify_title}" -d "$message" "ntfy.sh/${NTFY_CHANNEL}" >/dev/null 2>&1
}

#------------------------------------------------------------------------------
# If a screensaver is active AND a ntfy channel is configured, push remotely
#------------------------------------------------------------------------------
if screensaver_active && [ -n "$NTFY_CHANNEL" ]; then
  send_ntfy
  exit 0
fi

#------------------------------------------------------------------------------
# Show notification according to the operating system
#------------------------------------------------------------------------------
case "$(uname -s)" in
  Darwin*)
    # macOS - use terminal-notifier, adapting the icon + click action to the
    # terminal Claude Code is running in (detected via $TERM_PROGRAM):
    #   - VS Code:  click opens the exact folder/tab via the editor URL handler.
    #   - iTerm / Terminal / Termius: no per-tab URL exists, so the click just
    #     activates (brings forward) that terminal app.
    #   - Unknown terminal: notify with no click action.
    # The icon is a right-side thumbnail via -contentImage (the corner icon
    # can't be changed without -sender, which would break the click).

    # Map the terminal to its app bundle + bundle id.
    term_app=""
    term_bid=""
    case "$TERM_PROGRAM" in
      vscode)          term_app="/Applications/Visual Studio Code.app";       term_bid="com.microsoft.VSCode" ;;
      iTerm.app)       term_app="/Applications/iTerm.app";                     term_bid="com.googlecode.iterm2" ;;
      Apple_Terminal)  term_app="/System/Applications/Utilities/Terminal.app"; term_bid="com.apple.Terminal" ;;
      *)
        case "$(printf '%s' "$TERM_PROGRAM" | tr '[:upper:]' '[:lower:]')" in
          *termius*) term_app="/Applications/Termius.app"; term_bid="com.termius-dmg.mac" ;;
        esac
        ;;
    esac

    # Resolve the icon for the -contentImage thumbnail (CLAUDE_NOTIFIER_ICON
    # overrides; otherwise use the detected terminal's own icon).
    icon_args=()
    icon_path="${CLAUDE_NOTIFIER_ICON:-}"
    if [ -z "$icon_path" ] && [ -n "$term_app" ] && [ -d "$term_app" ]; then
      icon_file=$(defaults read "$term_app/Contents/Info" CFBundleIconFile 2>/dev/null)
      case "$icon_file" in *.icns|"") ;; *) icon_file="$icon_file.icns" ;; esac
      [ -n "$icon_file" ] && icon_path="$term_app/Contents/Resources/$icon_file"
    fi
    [ -n "$icon_path" ] && [ -f "$icon_path" ] && icon_args=(-contentImage "$icon_path")

    # Build the click action.
    click_args=()
    if [ "$TERM_PROGRAM" = "vscode" ] && [ -n "$cwd" ]; then
      # VS Code can focus the exact window/tab for this folder (spaces encoded).
      url="${EDITOR_SCHEME}://file${cwd// /%20}"
      click_args=(-execute "open \"$url\"")
    elif [ -n "$term_bid" ]; then
      # Other terminals: just bring the app forward (no per-tab targeting).
      click_args=(-activate "$term_bid")
    fi

    terminal-notifier -title "$notify_title" -message "$message" -sound default \
      "${icon_args[@]}" "${click_args[@]}"
    ;;

  Linux*)
    # Linux - use notify-send
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$notify_title" "$message" -i dialog-information
    else
      echo "notify-send not found. Install libnotify-bin package."
      echo "${notify_title}: $message"
    fi
    ;;

  CYGWIN*|MINGW*|MSYS*)
    # Windows - use PowerShell toast notification
    powershell.exe -Command "
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null;
    \$template = @'
    <toast>
        <visual>
            <binding template=\"ToastGeneric\">
                <text>Claude Code</text>
                <text>$message</text>
            </binding>
        </visual>
    </toast>
'@;
    \$xml = New-Object Windows.Data.Xml.Dom.XmlDocument;
    \$xml.LoadXml(\$template);
    \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml);
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show(\$toast);"
    ;;

  *)
    # Fallback - just echo to terminal
    echo "Claude Code Notification: $message"
    ;;
esac
