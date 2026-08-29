using Xunit;

public class MacKeysRulesTests
{
    [Fact]
    public void ControlMappingMatchesTheDocumentedLetterSet()
    {
        const string mappedLetters = "ABCDEFGHIKNOPRSTUVWXZ";

        for (char letter = 'A'; letter <= 'Z'; letter++)
        {
            Assert.Equal(
                mappedLetters.Contains(letter),
                MacKeysRules.IsCtrlMappedKey(letter));
        }
    }

    [Theory]
    [InlineData(0x10)] // Shift
    [InlineData(0x11)] // Control
    [InlineData(0xA4)] // Left Alt
    [InlineData(0xA5)] // Right Alt
    [InlineData(0x14)] // Caps Lock
    [InlineData(0x90)] // Num Lock
    [InlineData(0x91)] // Scroll Lock
    public void ModifierAndLockKeysPassThroughCommand(uint virtualKey)
    {
        Assert.True(MacKeysRules.IsCommandPassthroughKey(virtualKey));
    }

    [Theory]
    [InlineData("CabinetWClass")]
    [InlineData("Progman")]
    [InlineData("WorkerW")]
    public void ExplorerWindowClassesAreRecognized(string className)
    {
        Assert.True(MacKeysRules.IsExplorerWindowClass(className));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("cabinetwclass")]
    [InlineData("Chrome_WidgetWin_1")]
    public void OtherWindowClassesAreNotRecognized(string? className)
    {
        Assert.False(MacKeysRules.IsExplorerWindowClass(className!));
    }

    [Theory]
    [InlineData(0x0D, 0x71)] // Enter -> F2
    [InlineData(0x20, 0x0D)] // Space -> Enter
    [InlineData(0x41, 0x00)] // Unmapped
    public void ExplorerItemKeysMapToExpectedTargets(uint input, ushort expected)
    {
        Assert.Equal(expected, MacKeysRules.GetExplorerItemTarget(input));
    }

    [Theory]
    [InlineData(0x25, 0x24)] // Left -> Home
    [InlineData(0x27, 0x23)] // Right -> End
    [InlineData(0x26, 0x00)] // Up is handled separately
    public void HorizontalNavigationMapsToExpectedTargets(uint input, ushort expected)
    {
        Assert.Equal(expected, MacKeysRules.GetCommandHorizontalTarget(input));
    }
}