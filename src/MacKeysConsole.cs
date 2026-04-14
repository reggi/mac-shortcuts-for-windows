public static class MacKeysConsole
{
    public static void Run()
    {
        if (!MacKeysEngine.InstallHook())
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

        Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e) {
            e.Cancel = true;
            Application.ExitThread();
        };

        Application.Run();

        MacKeysEngine.UninstallHook();
        Console.WriteLine("Hook removed. Bye!");
    }
}
