/// <summary>
/// Deterministic shortcut rules shared by the keyboard hook and unit tests.
/// This class deliberately has no Windows API dependencies.
/// </summary>
public static class MacKeysRules
{
    private static readonly System.Collections.Generic.HashSet<uint> CtrlMappedKeys =
        new System.Collections.Generic.HashSet<uint>
    {
        0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4B, 0x4E, 0x4F, 0x50, 0x52, 0x53, 0x54, 0x55,
        0x56, 0x57, 0x58, 0x5A
    };

    private static readonly System.Collections.Generic.HashSet<uint> PassthroughKeys =
        new System.Collections.Generic.HashSet<uint>
    {
        0x10, 0xA0, 0xA1, // Shift
        0x11, 0xA2, 0xA3, // Control
        0xA4, 0xA5,       // Alt
        0x14, 0x90, 0x91  // Caps Lock, Num Lock, Scroll Lock
    };

    public static bool IsCtrlMappedKey(uint virtualKey)
    {
        return CtrlMappedKeys.Contains(virtualKey);
    }

    public static bool IsCommandPassthroughKey(uint virtualKey)
    {
        return PassthroughKeys.Contains(virtualKey);
    }

    public static bool IsExplorerWindowClass(string className)
    {
        return className == "CabinetWClass" ||
               className == "Progman" ||
               className == "WorkerW";
    }

    /// <summary>
    /// Maps Explorer's macOS-style item actions. Zero means no mapping.
    /// </summary>
    public static ushort GetExplorerItemTarget(uint virtualKey)
    {
        if (virtualKey == 0x0D) return 0x71; // Enter -> F2 (rename)
        if (virtualKey == 0x20) return 0x0D; // Space -> Enter (open)
        return 0;
    }

    /// <summary>
    /// Maps horizontal Command navigation. Zero means no mapping.
    /// </summary>
    public static ushort GetCommandHorizontalTarget(uint virtualKey)
    {
        if (virtualKey == 0x25) return 0x24; // Left -> Home
        if (virtualKey == 0x27) return 0x23; // Right -> End
        return 0;
    }
}