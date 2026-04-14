 using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

/// <summary>
/// Core keyboard-hook engine shared by both the tray and console versions.
/// Each host sets MacKeysEngine.IsDisabledCheck before calling InstallHook().
/// </summary>
public static class MacKeysEngine
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
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);

    [DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();

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

    private const int  WH_KEYBOARD_LL = 13;
    private const int  WM_KEYDOWN     = 0x0100;
    private const int  WM_KEYUP       = 0x0101;
    private const int  WM_SYSKEYDOWN  = 0x0104;
    private const int  WM_SYSKEYUP    = 0x0105;

    private const uint INPUT_KEYBOARD        = 1;
    private const uint KEYEVENTF_KEYUP       = 0x0002;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

    private const int VK_BACK     = 0x08;
    private const int VK_TAB      = 0x09;
    private const int VK_SPACE    = 0x20;
    private const int VK_SHIFT    = 0x10;
    private const int VK_CONTROL  = 0x11;
    private const int VK_CAPITAL  = 0x14;
    private const int VK_HOME     = 0x24;
    private const int VK_END      = 0x23;
    private const int VK_LEFT     = 0x25;
    private const int VK_UP       = 0x26;
    private const int VK_RIGHT    = 0x27;
    private const int VK_DOWN     = 0x28;
    private const int VK_DELETE   = 0x2E;
    private const int VK_LSHIFT   = 0xA0;
    private const int VK_RSHIFT   = 0xA1;
    private const int VK_LCONTROL = 0xA2;
    private const int VK_RCONTROL = 0xA3;
    private const int VK_LMENU   = 0xA4;
    private const int VK_RMENU   = 0xA5;
    private const int VK_LWIN    = 0x5B;
    private const int VK_RWIN    = 0x5C;
    private const int VK_RETURN = 0x0D;
    private const int VK_F2     = 0x71;
    private const int VK_F4     = 0x73;
    private const int VK_NUMLOCK = 0x90;
    private const int VK_SCROLL  = 0x91;

    private static readonly IntPtr MAGIC = new IntPtr(0x4D41434B);

    // ===================== State =====================

    private static IntPtr hookId = IntPtr.Zero;
    private static LowLevelKeyboardProc hookProc;
    private static bool cmdKeyDown   = false;
    private static bool optKeyDown   = false;
    private static bool inAltTabMode = false;
    private static int  cmdDownTick  = 0;

    /// <summary>
    /// Optional callback the host can set to indicate the hook should be
    /// temporarily disabled (e.g. paused, excluded app in foreground).
    /// When this returns true, Win key events pass through to Windows.
    /// Default: always enabled.
    /// </summary>
    public static Func<bool> IsDisabledCheck = () => false;

    // ===================== Key Sets =====================

    private static readonly HashSet<uint> ctrlMappedKeys = new HashSet<uint>
    {
        0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4B, 0x4C, 0x4E, 0x4F, 0x50, 0x52, 0x53, 0x54, 0x55,
        0x56, 0x57, 0x58, 0x5A
    };

    private static readonly HashSet<uint> passthroughKeys = new HashSet<uint>
    {
        (uint)VK_SHIFT, (uint)VK_LSHIFT, (uint)VK_RSHIFT,
        (uint)VK_CONTROL, (uint)VK_LCONTROL, (uint)VK_RCONTROL,
        (uint)VK_LMENU, (uint)VK_RMENU,
        (uint)VK_CAPITAL, (uint)VK_NUMLOCK, (uint)VK_SCROLL
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

    // ===================== Hook Lifecycle =====================

    public static bool InstallHook()
    {
        hookProc = HookCallback;
        using (Process proc = Process.GetCurrentProcess())
        using (ProcessModule mod = proc.MainModule)
        {
            hookId = SetWindowsHookEx(WH_KEYBOARD_LL, hookProc,
                         GetModuleHandle(mod.ModuleName), 0);
        }
        if (hookId != IntPtr.Zero)
            DisableWinLLock();
        return hookId != IntPtr.Zero;
    }

    public static void UninstallHook()
    {
        if (hookId != IntPtr.Zero)
        {
            // Release any modifiers we may have injected before removing hook
            ReleaseInjectedModifiers();
            cmdKeyDown = false;
            optKeyDown = false;

            UnhookWindowsHookEx(hookId);
            hookId = IntPtr.Zero;
            EnableWinLLock();
        }
    }

    /// <summary>
    /// Send key-up for modifiers this engine injects (Ctrl, Alt) so they
    /// never remain stuck after the hook is removed or state is reset.
    /// </summary>
    private static void ReleaseInjectedModifiers()
    {
        if (inAltTabMode)
        {
            SendKey((ushort)VK_LMENU, false, false);
            inAltTabMode = false;
        }
        // Unconditionally release Ctrl and Alt — sending key-up for a key
        // that isn't down is harmless, but NOT sending it when it IS stuck
        // locks the whole keyboard.
        SendKey((ushort)VK_LCONTROL, false, false);
        SendKey((ushort)VK_LMENU,   false, false);
    }

    private const string LockPolicyKey =
        @"Software\Microsoft\Windows\CurrentVersion\Policies\System";

    private static void DisableWinLLock()
    {
        try
        {
            using (var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(LockPolicyKey))
                key.SetValue("DisableLockWorkstation", 1,
                    Microsoft.Win32.RegistryValueKind.DWord);
        }
        catch { }
    }

    private static void EnableWinLLock()
    {
        try
        {
            using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(LockPolicyKey, true))
                if (key != null)
                    key.DeleteValue("DisableLockWorkstation", false);
        }
        catch { }
    }

    // ===================== Hook Callback =====================

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        KBDLLHOOKSTRUCT data =
            (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));

        if (data.dwExtraInfo == MAGIC)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        // Guard against stuck Command key — if the key-up was lost (e.g. UAC,
        // lock screen), check whether the Win key is actually still held.
        // GetAsyncKeyState may not reflect the physical state for keys
        // suppressed by a low-level hook, so only use it as a fallback
        // after a generous grace period (5 s) to avoid resetting cmdKeyDown
        // during normal Cmd+key sequences.
        if (cmdKeyDown && data.vkCode != (uint)VK_LWIN && data.vkCode != (uint)VK_RWIN)
        {
            bool winStillDown = (GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 ||
                                (GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
            if (!winStillDown && (Environment.TickCount - cmdDownTick) > 5000)
            {
                cmdKeyDown = false;
                ReleaseInjectedModifiers();
            }
        }

        int  msg    = wParam.ToInt32();
        bool isDown = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
        bool isUp   = (msg == WM_KEYUP   || msg == WM_SYSKEYUP);
        uint vk     = data.vkCode;

        // Track Left/Right Win (Command key)
        if (vk == (uint)VK_LWIN || vk == (uint)VK_RWIN)
        {
            if (IsDisabledCheck())
                return CallNextHookEx(hookId, nCode, wParam, lParam);

            if (isDown)
            {
                cmdKeyDown = true;
                cmdDownTick = Environment.TickCount;
            }
            else if (isUp)
            {
                cmdKeyDown = false;
                if (inAltTabMode)
                {
                    SendKey((ushort)VK_LMENU, false, false);
                    inAltTabMode = false;
                }
            }
            return (IntPtr)1;
        }

        // ====== Track Left Alt (Option key) — suppress to prevent menu activation ======
        if (vk == (uint)VK_LMENU)
        {
            if (IsDisabledCheck())
                return CallNextHookEx(hookId, nCode, wParam, lParam);

            if (isDown)
                optKeyDown = true;
            else if (isUp)
                optKeyDown = false;
            return (IntPtr)1;
        }

        // ====== Option (Left Alt) + Arrow → Ctrl+Arrow (word/paragraph navigation) ======
        if (!cmdKeyDown &&
            (vk == (uint)VK_LEFT || vk == (uint)VK_RIGHT || vk == (uint)VK_UP || vk == (uint)VK_DOWN) &&
            optKeyDown)
        {
            if (isUp) return (IntPtr)1;

            SendBatch(new INPUT[] {
                MakeKeyInput((ushort)VK_LCONTROL, true,  false),
                MakeKeyInput((ushort)vk,          true,  true),
                MakeKeyInput((ushort)vk,          false, true),
                MakeKeyInput((ushort)VK_LCONTROL, false, false)
            });

            return (IntPtr)1;
        }

        // ====== Option (Left Alt) + Backspace → Ctrl+Backspace (delete word) ======
        if (!cmdKeyDown && vk == (uint)VK_BACK && optKeyDown)
        {
            if (isUp) return (IntPtr)1;

            SendBatch(new INPUT[] {
                MakeKeyInput((ushort)VK_LCONTROL, true,  false),
                MakeKeyInput((ushort)VK_BACK,     true,  false),
                MakeKeyInput((ushort)VK_BACK,     false, false),
                MakeKeyInput((ushort)VK_LCONTROL, false, false)
            });

            return (IntPtr)1;
        }

        // ====== Explorer: Enter → F2 (rename), Space → Enter (open) ======
        if (!cmdKeyDown && (vk == (uint)VK_RETURN || vk == (uint)VK_SPACE) &&
            !optKeyDown &&
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

        if (!cmdKeyDown)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        if (passthroughKeys.Contains(vk))
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        // Cmd+Tab -> Alt+Tab
        if (vk == (uint)VK_TAB)
        {
            if (isDown && !inAltTabMode)
            {
                SendKey((ushort)VK_LMENU, true, false);
                inAltTabMode = true;
            }
            if (inAltTabMode)
            {
                SendKey((ushort)VK_TAB, isDown, false);
                cmdDownTick = Environment.TickCount;
                return (IntPtr)1;
            }
        }

        if (isUp)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        // Cmd+Space -> Win+S (Windows Search)
        if (vk == (uint)VK_SPACE)
        {
            SendBatch(new INPUT[] {
                MakeKeyInput((ushort)VK_LWIN, true,  false),
                MakeKeyInput(0x53,            true,  false),
                MakeKeyInput(0x53,            false, false),
                MakeKeyInput((ushort)VK_LWIN, false, false)
            });
            return (IntPtr)1;
        }

        // Cmd+Q -> Alt+F4
        if (vk == 0x51)
        {
            SendBatch(new INPUT[] {
                MakeKeyInput((ushort)VK_LMENU, true,  false),
                MakeKeyInput((ushort)VK_F4,    true,  true),
                MakeKeyInput((ushort)VK_F4,    false, true),
                MakeKeyInput((ushort)VK_LMENU, false, false)
            });
            return (IntPtr)1;
        }

        // Cmd+Shift+3 -> full screen capture saved to Desktop
        if (vk == 0x33 && (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0)
        {
            CaptureFullScreenToDesktop();
            return (IntPtr)1;
        }

        // Cmd+Shift+4 -> Win+Shift+S (screen region capture) + auto-save to Desktop
        if (vk == 0x34 && (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0)
        {
            uint seqBefore = GetClipboardSequenceNumber();
            SendBatch(new INPUT[] {
                MakeKeyInput((ushort)VK_LWIN, true,  false),
                MakeKeyInput(0x53,            true,  false),
                MakeKeyInput(0x53,            false, false),
                MakeKeyInput((ushort)VK_LWIN, false, false)
            });
            WatchClipboardAndSave(seqBefore);
            return (IntPtr)1;
        }

        // Cmd+Backspace -> Delete (Explorer) or Ctrl+Backspace (delete word)
        if (vk == (uint)VK_BACK)
        {
            if (IsForegroundExplorerBrowser())
            {
                SendKey((ushort)VK_DELETE, true,  true);
                SendKey((ushort)VK_DELETE, false, true);
            }
            else
            {
                SendBatch(new INPUT[] {
                    MakeKeyInput((ushort)VK_LCONTROL, true,  false),
                    MakeKeyInput((ushort)VK_BACK,     true,  false),
                    MakeKeyInput((ushort)VK_BACK,     false, false),
                    MakeKeyInput((ushort)VK_LCONTROL, false, false)
                });
            }
            return (IntPtr)1;
        }

        // Cmd+Letter -> Ctrl+Letter
        if (ctrlMappedKeys.Contains(vk))
        {
            SendBatch(new INPUT[] {
                MakeKeyInput((ushort)VK_LCONTROL, true,  false),
                MakeKeyInput((ushort)vk,          true,  false),
                MakeKeyInput((ushort)vk,          false, false),
                MakeKeyInput((ushort)VK_LCONTROL, false, false)
            });
            return (IntPtr)1;
        }

        // Cmd+Left -> Home
        if (vk == (uint)VK_LEFT)
        {
            SendKey((ushort)VK_HOME, true,  true);
            SendKey((ushort)VK_HOME, false, true);
            return (IntPtr)1;
        }

        // Cmd+Right -> End
        if (vk == (uint)VK_RIGHT)
        {
            SendKey((ushort)VK_END, true,  true);
            SendKey((ushort)VK_END, false, true);
            return (IntPtr)1;
        }

        // Cmd+Up -> Alt+Up in Explorer (go up one dir), Ctrl+Home elsewhere
        if (vk == (uint)VK_UP)
        {
            if (IsForegroundExplorerBrowser())
            {
                SendBatch(new INPUT[] {
                    MakeKeyInput((ushort)VK_LMENU, true,  false),
                    MakeKeyInput((ushort)VK_UP,    true,  true),
                    MakeKeyInput((ushort)VK_UP,    false, true),
                    MakeKeyInput((ushort)VK_LMENU, false, false)
                });
            }
            else
            {
                SendBatch(new INPUT[] {
                    MakeKeyInput((ushort)VK_LCONTROL, true,  false),
                    MakeKeyInput((ushort)VK_HOME,     true,  true),
                    MakeKeyInput((ushort)VK_HOME,     false, true),
                    MakeKeyInput((ushort)VK_LCONTROL, false, false)
                });
            }
            return (IntPtr)1;
        }

        // Cmd+Down -> Ctrl+End
        if (vk == (uint)VK_DOWN)
        {
            SendBatch(new INPUT[] {
                MakeKeyInput((ushort)VK_LCONTROL, true,  false),
                MakeKeyInput((ushort)VK_END,      true,  true),
                MakeKeyInput((ushort)VK_END,      false, true),
                MakeKeyInput((ushort)VK_LCONTROL, false, false)
            });
            return (IntPtr)1;
        }

        // Unmapped Cmd+key — pass through instead of swallowing so that
        // a stuck cmdKeyDown state can never lock the entire keyboard.
        return CallNextHookEx(hookId, nCode, wParam, lParam);
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

    private static INPUT MakeKeyInput(ushort vk, bool down, bool extended)
    {
        INPUT input    = new INPUT();
        input.type     = INPUT_KEYBOARD;
        input.u.ki.wVk = vk;
        input.u.ki.dwFlags =
            (down ? 0u : KEYEVENTF_KEYUP) |
            (extended ? KEYEVENTF_EXTENDEDKEY : 0u);
        input.u.ki.dwExtraInfo = MAGIC;
        return input;
    }

    /// <summary>
    /// Send multiple key events atomically so modifier keys can never get
    /// stuck if Windows removes the hook between individual SendInput calls.
    /// </summary>
    private static void SendBatch(INPUT[] inputs)
    {
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    // ===================== Screenshot Helpers =====================

    private static string GetScreenshotPath()
    {
        string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
        string timestamp = DateTime.Now.ToString("yyyy-MM-dd 'at' h.mm.ss tt");
        string filename = string.Format("Screenshot {0}.png", timestamp);
        string path = Path.Combine(desktop, filename);
        int counter = 2;
        while (File.Exists(path))
        {
            filename = string.Format("Screenshot {0} ({1}).png", timestamp, counter);
            path = Path.Combine(desktop, filename);
            counter++;
        }
        return path;
    }

    private static void CaptureFullScreenToDesktop()
    {
        Thread t = new Thread(() =>
        {
            try
            {
                Rectangle bounds = SystemInformation.VirtualScreen;
                using (Bitmap bmp = new Bitmap(bounds.Width, bounds.Height))
                {
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
                    }
                    string path = GetScreenshotPath();
                    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
                    Clipboard.SetImage(bmp);
                }
            }
            catch { }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
    }

    private static void WatchClipboardAndSave(uint seqBefore)
    {
        Thread t = new Thread(() =>
        {
            try
            {
                for (int i = 0; i < 60; i++)
                {
                    Thread.Sleep(500);
                    uint seqNow = GetClipboardSequenceNumber();
                    if (seqNow != seqBefore && Clipboard.ContainsImage())
                    {
                        Image img = Clipboard.GetImage();
                        if (img != null)
                        {
                            string path = GetScreenshotPath();
                            img.Save(path, System.Drawing.Imaging.ImageFormat.Png);
                            img.Dispose();
                            return;
                        }
                    }
                }
            }
            catch { }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
    }
}
