<#
.SYNOPSIS
    Mac-style keyboard shortcuts for Windows — for Mac keyboards.
    The Command key (left of spacebar) registers as Left Win on Windows.
    This script intercepts it and makes it behave like Mac Command.
    Uses ONLY built-in Windows components — zero third-party software.

.DESCRIPTION
    Your Mac keyboard in Windows:
      Command (⌘)  =  Left Win key  →  this script remaps it

    Shortcut Mappings (Cmd = Left Win):

      Cmd+C/V/X          Copy / Paste / Cut
      Cmd+A               Select All
      Cmd+Z               Undo
      Cmd+Shift+Z         Redo  (sends Ctrl+Shift+Z)
      Cmd+S               Save
      Cmd+W               Close Tab
      Cmd+T               New Tab
      Cmd+N               New Window
      Cmd+F               Find
      Cmd+P               Print
      Cmd+O               Open
      Cmd+L               Address Bar (browser)
      Cmd+R               Reload
      Cmd+Q               Quit App (Alt+F4)
      Cmd+Backspace        Delete Word Back (Ctrl+Backspace)

    Navigation:
      Cmd+Left            Home  (start of line)
      Cmd+Right           End   (end of line)
      Cmd+Up              Ctrl+Home  (start of document)
      Cmd+Down            Ctrl+End   (end of document)

    Selection (hold Shift with any of the above navigation):
      Cmd+Shift+Left      Select to start of line
      Cmd+Shift+Right     Select to end of line
      Cmd+Shift+Up        Select to start of document
      Cmd+Shift+Down      Select to end of document

    Preserved:
      Cmd+Tab             Alt+Tab  (app switching, like Mac)
      Right Win           Unchanged
      Left Alt / Option   Unchanged (normal Alt behavior)

.NOTES
    Close the PowerShell window or press Ctrl+C to stop.
    To auto-start on login, place a shortcut to Start-MacKeys.bat
    in: shell:startup  (paste that into File Explorer address bar)

.USAGE
    powershell -ExecutionPolicy Bypass -File MacKeys.ps1
#>

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class MacKeys
{
    // ===================== Windows API =====================

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);

    // ===================== Structs =====================

    [StructLayout(LayoutKind.Sequential)]
    private struct GUITHREADINFO
    {
        public int cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public int rcCaretLeft;
        public int rcCaretTop;
        public int rcCaretRight;
        public int rcCaretBottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUTUNION u;
    }

    // ===================== Constants =====================

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN    = 0x0100;
    private const int WM_KEYUP      = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP   = 0x0105;

    private const uint INPUT_KEYBOARD       = 1;
    private const uint KEYEVENTF_KEYUP      = 0x0002;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

    // Virtual-key codes
    private const int VK_BACK      = 0x08;
    private const int VK_TAB       = 0x09;
    private const int VK_SPACE     = 0x20;
    private const int VK_SHIFT     = 0x10;
    private const int VK_CONTROL   = 0x11;
    private const int VK_CAPITAL   = 0x14;
    private const int VK_HOME      = 0x24;
    private const int VK_END       = 0x23;
    private const int VK_LEFT      = 0x25;
    private const int VK_UP        = 0x26;
    private const int VK_RIGHT     = 0x27;
    private const int VK_DOWN      = 0x28;
    private const int VK_DELETE    = 0x2E;
    private const int VK_LSHIFT    = 0xA0;
    private const int VK_RSHIFT    = 0xA1;
    private const int VK_LCONTROL  = 0xA2;
    private const int VK_RCONTROL  = 0xA3;
    private const int VK_LMENU     = 0xA4;  // Left Alt  (Mac Option key)
    private const int VK_RMENU     = 0xA5;  // Right Alt
    private const int VK_LWIN      = 0x5B;  // Left Win  (Mac Command key!)
    private const int VK_RWIN      = 0x5C;
    private const int VK_RETURN    = 0x0D;
    private const int VK_F2        = 0x71;
    private const int VK_F4        = 0x73;
    private const int VK_NUMLOCK   = 0x90;
    private const int VK_SCROLL    = 0x91;

    // Marker so the hook ignores our own synthetic key events
    private static readonly IntPtr MAGIC = new IntPtr(0x4D41434B);

    // ===================== State =====================

    private static IntPtr hookId = IntPtr.Zero;
    private static LowLevelKeyboardProc hookProc;  // prevent GC
    private static bool cmdKeyDown  = false;        // Left Win (Command) state
    private static bool inAltTabMode = false;

    // ===================== Key Sets =====================

    // Cmd+Key  ->  Ctrl+Key
    private static readonly HashSet<uint> ctrlMappedKeys = new HashSet<uint>
    {
        0x41, // A  Select All
        0x42, // B  Bold (in editors)
        0x43, // C  Copy
        0x44, // D  Bookmark / duplicate line
        0x45, // E  (search bar in some apps)
        0x46, // F  Find
        0x47, // G  Find Next (some apps)
        0x48, // H  Find & Replace (some apps)
        0x49, // I  Italic
        0x4B, // K  Insert link (editors)
        0x4C, // L  Address bar
        0x4E, // N  New
        0x4F, // O  Open
        0x50, // P  Print
        0x52, // R  Reload
        0x53, // S  Save
        0x54, // T  New Tab
        0x55, // U  Underline
        0x56, // V  Paste
        0x57, // W  Close Tab
        0x58, // X  Cut
        0x5A, // Z  Undo  (Shift passthrough gives Ctrl+Shift+Z = Redo)
    };

    // Modifier / toggle keys that should always pass through to the OS
    private static readonly HashSet<uint> passthroughKeys = new HashSet<uint>
    {
        (uint)VK_SHIFT,    (uint)VK_LSHIFT,   (uint)VK_RSHIFT,
        (uint)VK_CONTROL,  (uint)VK_LCONTROL, (uint)VK_RCONTROL,
        (uint)VK_LMENU,    (uint)VK_RMENU,    // Both Alt/Option keys pass through normally
        (uint)VK_RWIN,     // Right Win stays normal
        (uint)VK_CAPITAL,  (uint)VK_NUMLOCK,  (uint)VK_SCROLL,
    };

    // ===================== Explorer Detection =====================

    private static bool IsForegroundExplorerBrowser()
    {
        try
        {
            IntPtr hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return false;
            System.Text.StringBuilder className = new System.Text.StringBuilder(256);
            GetClassName(hwnd, className, 256);
            string cls = className.ToString();
            // CabinetWClass = Explorer window, Progman/WorkerW = Desktop
            return cls == "CabinetWClass" || cls == "Progman" || cls == "WorkerW";
        }
        catch { return false; }
    }

    private static bool IsTextInputActive()
    {
        GUITHREADINFO info = new GUITHREADINFO();
        info.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        if (GetGUIThreadInfo(0, ref info))
        {
            return info.hwndCaret != IntPtr.Zero;
        }
        return false;
    }

    // ===================== Public Entry =====================

    public static void Run()
    {
        hookProc = HookCallback;

        using (Process proc = Process.GetCurrentProcess())
        using (ProcessModule mod = proc.MainModule)
        {
            hookId = SetWindowsHookEx(WH_KEYBOARD_LL, hookProc,
                         GetModuleHandle(mod.ModuleName), 0);
        }

        if (hookId == IntPtr.Zero)
        {
            Console.WriteLine("ERROR: Could not install keyboard hook.");
            Console.WriteLine("Try running as Administrator.");
            return;
        }

        Console.WriteLine("===  Mac-style keys ACTIVE (Mac keyboard)  ===");
        Console.WriteLine("Command key (Left Win)  =  mapped to Ctrl combos");
        Console.WriteLine("Option  key (Left Alt)  =  unchanged (normal Alt)");
        Console.WriteLine();
        Console.WriteLine("Shortcuts:  Cmd+C/V/X  Copy/Paste/Cut");
        Console.WriteLine("            Cmd+A/Z/S  SelectAll/Undo/Save");
        Console.WriteLine("            Cmd+Shift+Z  Redo");
        Console.WriteLine("            Cmd+Q  Quit (Alt+F4)");
        Console.WriteLine("Navigation: Cmd+Arrows  Home/End/DocStart/DocEnd");
        Console.WriteLine("Selection:  Cmd+Shift+Arrows  select text");
        Console.WriteLine("Cmd+Tab:    Alt+Tab (app switching)");
        Console.WriteLine();
        Console.WriteLine("Press Ctrl+C or close this window to stop.");

        // Graceful shutdown on Ctrl+C
        Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e) {
            e.Cancel = true;
            Application.ExitThread();
        };

        // Message loop — required for the low-level hook to receive events
        Application.Run();

        UnhookWindowsHookEx(hookId);
        Console.WriteLine("Hook removed. Bye!");
    }

    // ===================== Hook Callback =====================

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        KBDLLHOOKSTRUCT data =
            (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));

        // Ignore our own synthetic events (identified by the magic marker)
        if (data.dwExtraInfo == MAGIC)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        int  msg = wParam.ToInt32();
        bool isDown = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
        bool isUp   = (msg == WM_KEYUP   || msg == WM_SYSKEYUP);
        uint vk     = data.vkCode;

        // ---------- Track Left Win (Mac Command key) ----------
        if (vk == (uint)VK_LWIN)
        {
            if (isDown)
            {
                cmdKeyDown = true;
            }
            else if (isUp)
            {
                cmdKeyDown = false;
                if (inAltTabMode)
                {
                    // Release the synthetic Alt we injected for Cmd+Tab
                    SendKey((ushort)VK_LMENU, false, false);
                    inAltTabMode = false;
                }
            }
            return (IntPtr)1;  // always suppress real Left Win (prevents Start menu)
        }

        // ====== Option (Left Alt) + Arrow → Ctrl+Arrow (word/paragraph navigation) ======
        // Shift state is physical, so Option+Shift+Arrow → Ctrl+Shift+Arrow (selection)
        if (!cmdKeyDown &&
            (vk == (uint)VK_LEFT || vk == (uint)VK_RIGHT || vk == (uint)VK_UP || vk == (uint)VK_DOWN) &&
            (GetAsyncKeyState(VK_LMENU) & 0x8000) != 0)
        {
            if (isUp) return (IntPtr)1;  // suppress key-up

            // Cancel Alt to prevent menu activation
            SendKey((ushort)VK_LMENU, false, false);

            // Send Ctrl+Arrow
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)vk,          true,  true);
            SendKey((ushort)vk,          false, true);
            SendKey((ushort)VK_LCONTROL, false, false);

            // Re-press Alt so subsequent arrows still work while held
            SendKey((ushort)VK_LMENU, true, false);

            return (IntPtr)1;
        }

        // ====== Explorer: Enter → F2 (rename), Space → Enter (open) ======
        // Only when no modifier held and no text input is active (rename, search bar)
        if (!cmdKeyDown && (vk == (uint)VK_RETURN || vk == (uint)VK_SPACE) &&
            (GetAsyncKeyState(VK_LMENU) & 0x8000) == 0 &&
            IsForegroundExplorerBrowser() && !IsTextInputActive())
        {
            if (isUp) return (IntPtr)1;

            if (vk == (uint)VK_RETURN)
            {
                SendKey((ushort)VK_F2, true,  false);
                SendKey((ushort)VK_F2, false, false);
                return (IntPtr)1;
            }
            if (vk == (uint)VK_SPACE)
            {
                SendKey((ushort)VK_RETURN, true,  false);
                SendKey((ushort)VK_RETURN, false, false);
                return (IntPtr)1;
            }
        }

        // ---------- If Command is NOT held, pass everything through ----------
        if (!cmdKeyDown)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        // ====== Command IS held — apply Mac mappings ======

        // Let modifier/toggle keys pass through so Shift state is real
        if (passthroughKeys.Contains(vk))
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        // ---------- Cmd+Tab -> Alt+Tab (app switching, like Mac) ----------
        if (vk == (uint)VK_TAB)
        {
            if (isDown && !inAltTabMode)
            {
                SendKey((ushort)VK_LMENU, true, false);   // synthetic Alt down
                inAltTabMode = true;
            }
            if (inAltTabMode)
            {
                SendKey((ushort)VK_TAB, isDown, false);
                return (IntPtr)1;
            }
        }

        // Let key-up events pass through to avoid stuck keys
        if (isUp)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        // ====== Key-down mappings only below this line ======

        // ---------- Cmd+Space  ->  Win+S (Windows Search, like Spotlight) ----------
        if (vk == (uint)VK_SPACE)
        {
            SendKey((ushort)VK_LWIN, true,  false);
            SendKey(0x53,             true,  false);  // S
            SendKey(0x53,             false, false);
            SendKey((ushort)VK_LWIN, false, false);
            return (IntPtr)1;
        }

        // ---------- Cmd+Q  ->  Alt+F4 (Quit application) ----------
        if (vk == 0x51)  // Q
        {
            SendKey((ushort)VK_LMENU, true,  false);
            SendKey((ushort)VK_F4,    true,  true);
            SendKey((ushort)VK_F4,    false, true);
            SendKey((ushort)VK_LMENU, false, false);
            return (IntPtr)1;
        }

        // ---------- Cmd+Backspace  ->  Delete (trash) in Explorer, Ctrl+Backspace (delete word) elsewhere ----------
        if (vk == (uint)VK_BACK)
        {
            if (IsForegroundExplorerBrowser())
            {
                SendKey((ushort)VK_DELETE, true,  true);
                SendKey((ushort)VK_DELETE, false, true);
            }
            else
            {
                SendKey((ushort)VK_LCONTROL, true,  false);
                SendKey((ushort)VK_BACK,     true,  false);
                SendKey((ushort)VK_BACK,     false, false);
                SendKey((ushort)VK_LCONTROL, false, false);
            }
            return (IntPtr)1;
        }

        // ---------- Cmd+Letter  ->  Ctrl+Letter ----------
        // Physical Shift state carries through automatically, so
        // Cmd+Shift+Z  ->  Ctrl+Shift+Z  (Redo in most modern apps)
        if (ctrlMappedKeys.Contains(vk))
        {
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)vk,          true,  false);
            SendKey((ushort)vk,          false, false);
            SendKey((ushort)VK_LCONTROL, false, false);
            return (IntPtr)1;
        }

        // ---------- Cmd+Left  ->  Home (start of line) ----------
        if (vk == (uint)VK_LEFT)
        {
            SendKey((ushort)VK_HOME, true,  true);
            SendKey((ushort)VK_HOME, false, true);
            return (IntPtr)1;
        }

        // ---------- Cmd+Right  ->  End (end of line) ----------
        if (vk == (uint)VK_RIGHT)
        {
            SendKey((ushort)VK_END, true,  true);
            SendKey((ushort)VK_END, false, true);
            return (IntPtr)1;
        }

        // ---------- Cmd+Up  ->  Ctrl+Home (start of document) ----------
        if (vk == (uint)VK_UP)
        {
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)VK_HOME,     true,  true);
            SendKey((ushort)VK_HOME,     false, true);
            SendKey((ushort)VK_LCONTROL, false, false);
            return (IntPtr)1;
        }

        // ---------- Cmd+Down  ->  Ctrl+End (end of document) ----------
        if (vk == (uint)VK_DOWN)
        {
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)VK_END,      true,  true);
            SendKey((ushort)VK_END,      false, true);
            SendKey((ushort)VK_LCONTROL, false, false);
            return (IntPtr)1;
        }

        // ---------- Unmapped key while Cmd held — suppress to avoid OS shortcuts ----------
        return (IntPtr)1;
    }

    // ===================== Helpers =====================

    private static void SendKey(ushort vk, bool down, bool extended)
    {
        INPUT input    = new INPUT();
        input.type     = INPUT_KEYBOARD;
        input.u.ki.wVk = vk;
        input.u.ki.dwFlags =
            (down ? 0u : KEYEVENTF_KEYUP) |
            (extended ? KEYEVENTF_EXTENDEDKEY : 0u);
        input.u.ki.dwExtraInfo = MAGIC;

        SendInput(1, new INPUT[] { input }, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@ -ReferencedAssemblies System.Windows.Forms

# Start the keyboard hook and message loop (blocks until stopped)
[MacKeys]::Run()
