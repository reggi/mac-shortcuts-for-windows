# mac-shortcuts-for-windows ⌘

Use your Mac keyboard shortcuts on Windows — no third-party software required. Everything runs on built-in PowerShell and .NET Framework.

Intercepts the **Command (⌘) key** (which Windows sees as Left Win) and remaps it to behave like macOS.

---

## Quick Start

**Tray version (recommended):** Double-click **`RunTray.vbs`**. A ⌘ icon appears in your system tray - no window flash.

**Console version:** Double-click **`RunConsole.bat`**. A terminal window stays open showing status.

## Requirements

- Windows 10 or 11 (nothing to install — uses built-in PowerShell 5.1 and .NET Framework)

## Folder Structure

```
RunTray.vbs              ← double-click to start (recommended)
RunConsole.bat           ← launch the console version
README.md
src/
  MacKeysRules.cs        ← deterministic, unit-tested shortcut mappings
  MacKeysEngine.cs       ← shared keyboard-hook engine (C#)
  MacKeysTray.cs         ← tray UI (C#)
  MacKeysTrayHost.ps1    ← tray bootstrap script
  MacKeysConsole.cs      ← console entry point (C#)
  MacKeysConsoleHost.ps1 ← console bootstrap script
tests/
  MacKeysRulesTests.cs   ← shortcut-rule unit tests
```

## Keyboard Shortcuts

### Copy, Paste & Common Shortcuts

| Mac Shortcut | What You Press | What Windows Receives |
|---|---|---|
| ⌘C | Cmd+C | Ctrl+C (Copy) |
| ⌘V | Cmd+V | Ctrl+V (Paste) |
| ⌘X | Cmd+X | Ctrl+X (Cut) |
| ⌘A | Cmd+A | Ctrl+A (Select All) |
| ⌘Z | Cmd+Z | Ctrl+Z (Undo) |
| ⌘⇧Z | Cmd+Shift+Z | Ctrl+Shift+Z (Redo) |
| ⌘S | Cmd+S | Ctrl+S (Save) |
| ⌘F | Cmd+F | Ctrl+F (Find) |
| ⌘W | Cmd+W | Ctrl+W (Close Tab) |
| ⌘T | Cmd+T | Ctrl+T (New Tab) |
| ⌘N | Cmd+N | Ctrl+N (New Window) |
| ⌘P | Cmd+P | Ctrl+P (Print) |
| ⌘O | Cmd+O | Ctrl+O (Open) |
| ⌘L | Cmd+L | Ctrl+L (Address Bar) |
| ⌘R | Cmd+R | Ctrl+R (Reload) |
| ⌘B | Cmd+B | Ctrl+B (Bold) |
| ⌘I | Cmd+I | Ctrl+I (Italic) |
| ⌘U | Cmd+U | Ctrl+U (Underline) |
| ⌘Q | Cmd+Q | Alt+F4 (Quit App) |
| ⌘⌫ | Cmd+Backspace | Ctrl+Backspace (Delete Word) |

### Navigation

| Mac Shortcut | What You Press | What Windows Receives |
|---|---|---|
| ⌘← | Cmd+Left | Home (start of line) |
| ⌘→ | Cmd+Right | End (end of line) |
| ⌘↑ | Cmd+Up | Ctrl+Home (start of document) |
| ⌘↓ | Cmd+Down | Ctrl+End (end of document) |

### Text Selection

Hold **Shift** with any navigation shortcut to select text:

| Mac Shortcut | What You Press | What Windows Receives |
|---|---|---|
| ⌘⇧← | Cmd+Shift+Left | Shift+Home (select to start of line) |
| ⌘⇧→ | Cmd+Shift+Right | Shift+End (select to end of line) |
| ⌘⇧↑ | Cmd+Shift+Up | Ctrl+Shift+Home (select to start of doc) |
| ⌘⇧↓ | Cmd+Shift+Down | Ctrl+Shift+End (select to end of doc) |

### App Switching

| Mac Shortcut | What You Press | What Windows Receives |
|---|---|---|
| ⌘Tab | Cmd+Tab | Alt+Tab (switch apps) |

## System Tray Features

Right-click the ⌘ icon in the tray:

- **Preferences** — manage excluded apps (see below)
- **Pause / Resume** — temporarily disable/enable (icon turns gray when paused)
- **Exit** — stop completely

Double-click the icon to toggle Pause/Resume.

## Excluded Apps (Preferences)

Some apps — especially games and game launchers — don't play well with keyboard hooks. When an excluded app is in the foreground, Mac Keys automatically turns off and lets the Command key act as the normal Windows key.

**Default exclusions:**
- `steam`
- `steamwebhelper`
- `gameoverlayui`

**To add more apps:**
1. Right-click the ⌘ tray icon → **Preferences**
2. Either:
   - Type a process name and click **Add**
   - Click **Pick from running apps** to select from a list of everything currently running

Settings are saved to `%AppData%\MacKeys\excluded.txt` and persist across restarts.

## Running in the Background (No Window)

**`RunTray.vbs`** starts PowerShell completely hidden with no console window flash and no taskbar entry. The ⌘ tray icon still appears as normal.

## Auto-Start on Login

1. Press `Win+R`, type `shell:startup`, press Enter
2. Copy a shortcut to `RunTray.vbs` into that folder

## Key Behavior

- **Command (⌘) key** → intercepted and remapped (Left Win key suppressed — no Start menu)
- **Option (⌥) key** → unchanged (acts as normal Alt)
- **Right Win key** → unchanged
- **Ctrl key** → unchanged

## How It Works

The script uses `Add-Type` to compile C# code at runtime that installs a [low-level keyboard hook](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc) (`WH_KEYBOARD_LL`). This intercepts keystrokes system-wide before they reach any application, translates Command-key combos into their Windows equivalents via `SendInput`, and suppresses the original keypress. Synthetic events are tagged with a marker (`dwExtraInfo`) so the hook ignores its own output and avoids infinite loops.

## Tests

The application still requires only built-in Windows components at runtime. Development tests require the .NET 8 SDK:

```powershell
dotnet test .\tests\MacKeysRules.Tests.csproj
.\tests\Test-HostCompilation.ps1
```

GitHub Actions runs both checks on `windows-latest` for pushes and pull requests.

## Troubleshooting

| Problem | Solution |
|---|---|
| Nothing happens when I press Command+C | Make sure the tray icon shows blue (not gray/paused). Try running as Administrator. |
| Start menu keeps opening | The script should suppress this. If it still happens, make sure you're running `MacKeysTray.ps1`, not an old version. |
| Shortcuts don't work in a specific app | Some elevated (admin) apps ignore hooks from non-admin processes. Run `Start-MacKeys.bat` as Administrator. |
| Want to use Windows key normally | Right-click tray icon → Pause. Or use the Right Win key, which is never intercepted. |
| Game has issues | Right-click tray icon → Preferences → add the game's process name to the exclusion list. |
