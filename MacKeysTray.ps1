<#
.SYNOPSIS
    Mac-style keyboard shortcuts for Windows — system tray version.
    Sits in the notification area (by the clock) with a ⌘ icon.
    Right-click the icon for Preferences / Pause / Exit.
    Auto-disables when excluded apps (e.g. Steam, games) are in the foreground.
    No console window.
#>

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class MacKeysTray : Form
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

    // ===================== Structs =====================

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
    private const int VK_F4      = 0x73;
    private const int VK_NUMLOCK = 0x90;
    private const int VK_SCROLL  = 0x91;

    private static readonly IntPtr MAGIC = new IntPtr(0x4D41434B);

    // ===================== State =====================

    private static IntPtr hookId = IntPtr.Zero;
    private static LowLevelKeyboardProc hookProc;
    private static bool cmdKeyDown   = false;
    private static bool inAltTabMode = false;
    private static bool paused       = false;

    // Excluded apps — process names (lowercase, no .exe)
    private static HashSet<string> excludedApps = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    private static string settingsPath;

    private NotifyIcon trayIcon;
    private MenuItem   pauseItem;
    private MenuItem   statusItem;

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
        (uint)VK_RWIN,
        (uint)VK_CAPITAL, (uint)VK_NUMLOCK, (uint)VK_SCROLL
    };

    // ===================== Settings =====================

    private static void LoadSettings()
    {
        // Store settings in AppData so it always works regardless of how we're launched
        string appDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "MacKeys");
        if (!Directory.Exists(appDir))
            Directory.CreateDirectory(appDir);
        settingsPath = Path.Combine(appDir, "excluded.txt");

        excludedApps.Clear();

        if (File.Exists(settingsPath))
        {
            foreach (string line in File.ReadAllLines(settingsPath))
            {
                string trimmed = line.Trim();
                if (!string.IsNullOrEmpty(trimmed) && !trimmed.StartsWith("#"))
                {
                    excludedApps.Add(trimmed.ToLowerInvariant().Replace(".exe", ""));
                }
            }
        }
        else
        {
            // Default exclusions for common game platforms
            excludedApps.Add("steam");
            excludedApps.Add("steamwebhelper");
            excludedApps.Add("gameoverlayui");
            SaveSettings();
        }
    }

    private static void SaveSettings()
    {
        try
        {
            List<string> lines = new List<string>();
            lines.Add("# Mac Keys — excluded apps (one process name per line)");
            lines.Add("# Lines starting with # are comments");
            lines.Add("# Add the process name without .exe");
            lines.Add("");
            foreach (string app in excludedApps)
            {
                lines.Add(app);
            }
            File.WriteAllLines(settingsPath, lines.ToArray());
        }
        catch { }
    }

    // ===================== Foreground App Check =====================

    private static bool IsForegroundAppExcluded()
    {
        try
        {
            IntPtr hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return false;

            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid == 0) return false;

            using (Process proc = Process.GetProcessById((int)pid))
            {
                string name = proc.ProcessName;
                if (excludedApps.Contains(name))
                    return true;
            }
        }
        catch { }
        return false;
    }

    // ===================== Tray Icon =====================

    private static Icon CreateCmdIcon(bool active)
    {
        Bitmap bmp = new Bitmap(16, 16);
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

            Color bg = active ? Color.FromArgb(50, 140, 255) : Color.Gray;
            using (SolidBrush bgBrush = new SolidBrush(bg))
            {
                g.FillRectangle(bgBrush, 0, 0, 16, 16);
            }

            using (Font f = new Font("Segoe UI", 9f, FontStyle.Bold))
            using (SolidBrush fb = new SolidBrush(Color.White))
            {
                StringFormat sf = new StringFormat();
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                g.DrawString("\u2318", f, fb, new RectangleF(0, 0, 16, 16), sf);
            }
        }
        IntPtr hIcon = bmp.GetHicon();
        return Icon.FromHandle(hIcon);
    }

    // ===================== Preferences Window =====================

    private void ShowPreferences()
    {
        Form prefs = new Form();
        prefs.Text = "Mac Keys — Preferences";
        prefs.Size = new Size(460, 420);
        prefs.StartPosition = FormStartPosition.CenterScreen;
        prefs.FormBorderStyle = FormBorderStyle.FixedDialog;
        prefs.MaximizeBox = false;
        prefs.MinimizeBox = false;
        prefs.ShowInTaskbar = true;
        prefs.TopMost = true;

        Label lbl = new Label();
        lbl.Text = "Disabled apps (Mac Keys turns off when these are in the foreground):";
        lbl.Location = new Point(12, 12);
        lbl.Size = new Size(420, 18);
        prefs.Controls.Add(lbl);

        ListBox listBox = new ListBox();
        listBox.Location = new Point(12, 34);
        listBox.Size = new Size(310, 240);
        listBox.Sorted = true;
        foreach (string app in excludedApps)
            listBox.Items.Add(app);
        prefs.Controls.Add(listBox);

        // Remove button
        Button btnRemove = new Button();
        btnRemove.Text = "Remove";
        btnRemove.Location = new Point(330, 34);
        btnRemove.Size = new Size(100, 28);
        btnRemove.Click += delegate {
            if (listBox.SelectedItem != null)
            {
                string sel = listBox.SelectedItem.ToString();
                listBox.Items.Remove(listBox.SelectedItem);
                excludedApps.Remove(sel);
                SaveSettings();
            }
        };
        prefs.Controls.Add(btnRemove);

        // --- Add by typing ---
        Label lblAdd = new Label();
        lblAdd.Text = "Add by name (without .exe):";
        lblAdd.Location = new Point(12, 284);
        lblAdd.Size = new Size(200, 18);
        prefs.Controls.Add(lblAdd);

        TextBox txtAdd = new TextBox();
        txtAdd.Location = new Point(12, 304);
        txtAdd.Size = new Size(200, 22);
        prefs.Controls.Add(txtAdd);

        Button btnAdd = new Button();
        btnAdd.Text = "Add";
        btnAdd.Location = new Point(218, 303);
        btnAdd.Size = new Size(60, 24);
        btnAdd.Click += delegate {
            string name = txtAdd.Text.Trim().ToLowerInvariant().Replace(".exe", "");
            if (!string.IsNullOrEmpty(name) && !excludedApps.Contains(name))
            {
                excludedApps.Add(name);
                listBox.Items.Add(name);
                SaveSettings();
                txtAdd.Clear();
            }
        };
        prefs.Controls.Add(btnAdd);

        // --- Pick from running apps ---
        Button btnPick = new Button();
        btnPick.Text = "Pick from running apps...";
        btnPick.Location = new Point(12, 338);
        btnPick.Size = new Size(200, 28);
        btnPick.Click += delegate {
            Form picker = new Form();
            picker.Text = "Select an app";
            picker.Size = new Size(360, 400);
            picker.StartPosition = FormStartPosition.CenterParent;
            picker.FormBorderStyle = FormBorderStyle.FixedDialog;
            picker.MaximizeBox = false;
            picker.MinimizeBox = false;
            picker.TopMost = true;

            Label plbl = new Label();
            plbl.Text = "Running processes (double-click to add):";
            plbl.Location = new Point(12, 12);
            plbl.Size = new Size(320, 18);
            picker.Controls.Add(plbl);

            ListBox procList = new ListBox();
            procList.Location = new Point(12, 34);
            procList.Size = new Size(320, 280);
            procList.Sorted = true;

            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                foreach (Process p in Process.GetProcesses())
                {
                    try
                    {
                        string pname = p.ProcessName;
                        // Skip system/background noise
                        if (pname.Equals("Idle", StringComparison.OrdinalIgnoreCase) ||
                            pname.Equals("System", StringComparison.OrdinalIgnoreCase) ||
                            pname.Equals("svchost", StringComparison.OrdinalIgnoreCase) ||
                            pname.Equals("csrss", StringComparison.OrdinalIgnoreCase) ||
                            pname.Equals("conhost", StringComparison.OrdinalIgnoreCase))
                            continue;

                        if (!seen.Contains(pname))
                        {
                            seen.Add(pname);
                            string title = "";
                            try { title = p.MainWindowTitle; } catch { }
                            string display = string.IsNullOrEmpty(title)
                                ? pname
                                : pname + "  —  " + title;
                            procList.Items.Add(display);
                        }
                    }
                    catch { }
                    finally { p.Dispose(); }
                }
            }
            catch { }

            procList.DoubleClick += delegate {
                if (procList.SelectedItem != null)
                {
                    string sel = procList.SelectedItem.ToString();
                    // Extract process name (before " — ")
                    int dash = sel.IndexOf("  \u2014  ");
                    string procName = (dash > 0 ? sel.Substring(0, dash) : sel).Trim().ToLowerInvariant();
                    if (!excludedApps.Contains(procName))
                    {
                        excludedApps.Add(procName);
                        listBox.Items.Add(procName);
                        SaveSettings();
                    }
                    picker.Close();
                }
            };

            picker.Controls.Add(procList);
            picker.ShowDialog(prefs);
        };
        prefs.Controls.Add(btnPick);

        prefs.ShowDialog(this);
    }

    // ===================== Constructor =====================

    public MacKeysTray()
    {
        this.ShowInTaskbar = false;
        this.WindowState = FormWindowState.Minimized;
        this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        this.Opacity = 0;
        this.Size = new Size(0, 0);

        LoadSettings();

        pauseItem = new MenuItem("Pause", OnPauseToggle);
        statusItem = new MenuItem("Mac Keys — Active") { Enabled = false };

        MenuItem prefsItem = new MenuItem("Preferences...", delegate { ShowPreferences(); });

        ContextMenu menu = new ContextMenu(new MenuItem[]
        {
            statusItem,
            new MenuItem("-"),
            prefsItem,
            pauseItem,
            new MenuItem("-"),
            new MenuItem("Exit", OnExit)
        });

        trayIcon = new NotifyIcon();
        trayIcon.Icon = CreateCmdIcon(true);
        trayIcon.Text = "Mac Keys — Active";
        trayIcon.ContextMenu = menu;
        trayIcon.Visible = true;
        trayIcon.DoubleClick += OnPauseToggle;

        InstallHook();
    }

    private void OnPauseToggle(object sender, EventArgs e)
    {
        paused = !paused;
        if (paused)
        {
            pauseItem.Text = "Resume";
            trayIcon.Icon = CreateCmdIcon(false);
            trayIcon.Text = "Mac Keys — Paused";
            statusItem.Text = "Mac Keys — Paused";
        }
        else
        {
            pauseItem.Text = "Pause";
            trayIcon.Icon = CreateCmdIcon(true);
            trayIcon.Text = "Mac Keys — Active";
            statusItem.Text = "Mac Keys — Active";
        }
    }

    private void OnExit(object sender, EventArgs e)
    {
        if (hookId != IntPtr.Zero)
            UnhookWindowsHookEx(hookId);
        trayIcon.Visible = false;
        trayIcon.Dispose();
        Application.Exit();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (hookId != IntPtr.Zero)
            UnhookWindowsHookEx(hookId);
        trayIcon.Visible = false;
        trayIcon.Dispose();
        base.OnFormClosing(e);
    }

    // ===================== Hook Setup =====================

    private void InstallHook()
    {
        hookProc = HookCallback;
        using (Process proc = Process.GetCurrentProcess())
        using (ProcessModule mod = proc.MainModule)
        {
            hookId = SetWindowsHookEx(WH_KEYBOARD_LL, hookProc,
                         GetModuleHandle(mod.ModuleName), 0);
        }
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

        int  msg    = wParam.ToInt32();
        bool isDown = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
        bool isUp   = (msg == WM_KEYUP   || msg == WM_SYSKEYUP);
        uint vk     = data.vkCode;

        // Track Left Win (Command key)
        if (vk == (uint)VK_LWIN)
        {
            // Check if we should be disabled for the current foreground app
            bool disabled = paused || IsForegroundAppExcluded();

            if (disabled)
            {
                // Let the real Win key through so native shortcuts work
                return CallNextHookEx(hookId, nCode, wParam, lParam);
            }

            if (isDown)
            {
                cmdKeyDown = true;
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
            return (IntPtr)1;  // suppress real Left Win
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
                return (IntPtr)1;
            }
        }

        if (isUp)
            return CallNextHookEx(hookId, nCode, wParam, lParam);

        // Cmd+Q -> Alt+F4
        if (vk == 0x51)
        {
            SendKey((ushort)VK_LMENU, true,  false);
            SendKey((ushort)VK_F4,    true,  false);
            SendKey((ushort)VK_F4,    false, false);
            SendKey((ushort)VK_LMENU, false, false);
            return (IntPtr)1;
        }

        // Cmd+Backspace -> Ctrl+Backspace
        if (vk == (uint)VK_BACK)
        {
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)VK_BACK,     true,  false);
            SendKey((ushort)VK_BACK,     false, false);
            SendKey((ushort)VK_LCONTROL, false, false);
            return (IntPtr)1;
        }

        // Cmd+Letter -> Ctrl+Letter
        if (ctrlMappedKeys.Contains(vk))
        {
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)vk,          true,  false);
            SendKey((ushort)vk,          false, false);
            SendKey((ushort)VK_LCONTROL, false, false);
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

        // Cmd+Up -> Ctrl+Home
        if (vk == (uint)VK_UP)
        {
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)VK_HOME,     true,  true);
            SendKey((ushort)VK_HOME,     false, true);
            SendKey((ushort)VK_LCONTROL, false, false);
            return (IntPtr)1;
        }

        // Cmd+Down -> Ctrl+End
        if (vk == (uint)VK_DOWN)
        {
            SendKey((ushort)VK_LCONTROL, true,  false);
            SendKey((ushort)VK_END,      true,  true);
            SendKey((ushort)VK_END,      false, true);
            SendKey((ushort)VK_LCONTROL, false, false);
            return (IntPtr)1;
        }

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

    // ===================== Main =====================

    public static void Main()
    {
        Application.EnableVisualStyles();
        Application.Run(new MacKeysTray());
    }
}
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing

[MacKeysTray]::Main()
