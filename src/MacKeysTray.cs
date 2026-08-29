public class MacKeysTray : Form
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    // ===================== State =====================

    private static bool paused = false;
    private static bool useAltAsCommand = false;
    private static volatile bool foregroundAppExcluded = false;

    private static HashSet<string> excludedApps = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    private static string settingsPath;
    private static string modePath;

    /// <summary>Set by PS1 host before Main() — full path to RunTray.vbs.</summary>
    public static string VbsPath = null;

    private const string StartupRunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string StartupValueName = "MacKeys";

    private NotifyIcon trayIcon;
    private MenuItem   pauseItem;
    private MenuItem   statusItem;
    private System.Windows.Forms.Timer foregroundTimer;

    // ===================== Settings =====================

    private static void LoadSettings()
    {
        string appDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "MacKeys");
        if (!Directory.Exists(appDir))
            Directory.CreateDirectory(appDir);
        settingsPath = Path.Combine(appDir, "excluded.txt");
        modePath = Path.Combine(appDir, "keyboard-mode.txt");

        // Load keyboard mode
        useAltAsCommand = false;
        if (File.Exists(modePath))
        {
            try
            {
                string mode = File.ReadAllText(modePath).Trim().ToLowerInvariant();
                useAltAsCommand = (mode == "standard");
            }
            catch { }
        }
        MacKeysEngine.UseAltAsCommand = useAltAsCommand;

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
            lines.Add("# Mac Keys - excluded apps (one process name per line)");
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

    // ===================== Startup =====================

    private static bool IsStartupEnabled()
    {
        try
        {
            using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(StartupRunKey))
                return key != null && key.GetValue(StartupValueName) != null;
        }
        catch { return false; }
    }

    private static void SetStartupEnabled(bool enabled)
    {
        try
        {
            if (enabled && VbsPath != null)
            {
                using (var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(StartupRunKey))
                    key.SetValue(StartupValueName, "wscript.exe \"" + VbsPath + "\"");
            }
            else
            {
                using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(StartupRunKey, true))
                    if (key != null) key.DeleteValue(StartupValueName, false);
            }
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
        prefs.Text = "Mac Keys - Preferences";
        prefs.Size = new Size(460, 450);
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
                                : pname + "  -  " + title;
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
                    int dash = sel.IndexOf("  -  ");
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

        CheckBox chkStartup = new CheckBox();
        chkStartup.Text = "Start at login";
        chkStartup.Location = new Point(12, 374);
        chkStartup.Size = new Size(200, 20);
        chkStartup.Checked = IsStartupEnabled();
        chkStartup.Enabled = (VbsPath != null);
        chkStartup.CheckedChanged += delegate { SetStartupEnabled(chkStartup.Checked); };
        prefs.Controls.Add(chkStartup);

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

        // Keep process inspection out of the low-level keyboard callback.
        // A slow callback can cause Windows to silently remove the hook.
        foregroundAppExcluded = IsForegroundAppExcluded();
        MacKeysEngine.IsDisabledCheck = () => paused || foregroundAppExcluded;
        foregroundTimer = new System.Windows.Forms.Timer();
        foregroundTimer.Interval = 250;
        foregroundTimer.Tick += delegate {
            bool wasExcluded = foregroundAppExcluded;
            foregroundAppExcluded = IsForegroundAppExcluded();
            if (!wasExcluded && foregroundAppExcluded)
                MacKeysEngine.ResetState();
        };
        foregroundTimer.Start();

        pauseItem = new MenuItem("Pause", OnPauseToggle);
        statusItem = new MenuItem("Mac Keys - Active") { Enabled = false };

        MenuItem macKbItem = new MenuItem("Mac Keyboard", OnKeyboardMode);
        MenuItem stdKbItem = new MenuItem("Standard Keyboard", OnKeyboardMode);
        macKbItem.Tag = "mac";
        stdKbItem.Tag = "standard";
        if (useAltAsCommand)
            stdKbItem.Checked = true;
        else
            macKbItem.Checked = true;

        MenuItem kbMenu = new MenuItem("Keyboard Layout",
            new MenuItem[] { macKbItem, stdKbItem });

        MenuItem prefsItem = new MenuItem("Preferences...", delegate { ShowPreferences(); });

        ContextMenu menu = new ContextMenu(new MenuItem[]
        {
            statusItem,
            new MenuItem("-"),
            kbMenu,
            prefsItem,
            pauseItem,
            new MenuItem("-"),
            new MenuItem("Exit", OnExit)
        });

        trayIcon = new NotifyIcon();
        trayIcon.Icon = CreateCmdIcon(true);
        trayIcon.Text = "Mac Keys - Active";
        trayIcon.ContextMenu = menu;
        trayIcon.Visible = true;
        trayIcon.DoubleClick += OnPauseToggle;

        if (!MacKeysEngine.InstallHook())
        {
            trayIcon.Visible = false;
            MessageBox.Show("Mac Keys could not install its keyboard hook.\n\nClose any older Mac Keys process and try again.",
                "Mac Keys", MessageBoxButtons.OK, MessageBoxIcon.Error);
            BeginInvoke((MethodInvoker)delegate { Close(); });
            return;
        }

        trayIcon.BalloonTipTitle = "Mac Keys";
        trayIcon.BalloonTipText = "Mac-style keyboard shortcuts are active.\nRight-click the tray icon for options.";
        trayIcon.BalloonTipIcon = ToolTipIcon.Info;
        trayIcon.ShowBalloonTip(3000);
    }

    private void OnPauseToggle(object sender, EventArgs e)
    {
        paused = !paused;
        MacKeysEngine.ResetState();
        if (paused)
        {
            pauseItem.Text = "Resume";
            trayIcon.Icon = CreateCmdIcon(false);
            trayIcon.Text = "Mac Keys - Paused";
            statusItem.Text = "Mac Keys - Paused";
        }
        else
        {
            pauseItem.Text = "Pause";
            trayIcon.Icon = CreateCmdIcon(true);
            trayIcon.Text = "Mac Keys - Active";
            statusItem.Text = "Mac Keys - Active";
        }
    }

    private void OnKeyboardMode(object sender, EventArgs e)
    {
        MenuItem clicked = (MenuItem)sender;
        string mode = (string)clicked.Tag;
        useAltAsCommand = (mode == "standard");
        MacKeysEngine.ResetState();
        MacKeysEngine.UseAltAsCommand = useAltAsCommand;

        // Update check marks
        foreach (MenuItem item in clicked.Parent.MenuItems)
            item.Checked = (item == clicked);

        // Persist
        try { File.WriteAllText(modePath, mode); } catch { }
    }

    private void OnExit(object sender, EventArgs e)
    {
        if (foregroundTimer != null) foregroundTimer.Stop();
        MacKeysEngine.UninstallHook();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        Application.Exit();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (foregroundTimer != null) foregroundTimer.Stop();
        MacKeysEngine.UninstallHook();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        base.OnFormClosing(e);
    }

    // ===================== Main =====================

    private static Mutex appMutex;

    public static void Main()
    {
        bool createdNew;
        appMutex = new Mutex(true, "MacKeysForWindows_SingleInstance", out createdNew);

        if (!createdNew)
        {
            // Do not restart a healthy instance when a startup shortcut or an
            // accidental double-click launches a duplicate.
            appMutex.Close();
            return;
        }

        Application.EnableVisualStyles();
        Application.Run(new MacKeysTray());

        appMutex.ReleaseMutex();
        appMutex.Close();
    }
}
