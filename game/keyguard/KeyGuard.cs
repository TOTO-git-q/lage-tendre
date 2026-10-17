// KeyGuard: while L'age tendre is the foreground window, the keyboard's system shortcuts are switched off so the
// player can smash the keyboard; only Esc keeps its meaning (the game's pause).  Technique as in Microsoft's
// "Disabling Shortcut Keys in Games": a low-level keyboard hook (WH_KEYBOARD_LL) plus the accessibility shortcut
// keys (StickyKeys / FilterKeys / ToggleKeys hotkeys) turned off while running and restored on exit.
//
//   KeyGuard.exe <game pid> [--no-spi]
//
// - The hook only acts while a window of <game pid> is in the foreground.
// - Swallowed: both Windows keys, the Menu key, Caps Lock, both Ctrl keys, both Alt keys (so Alt+Tab / Alt+F4 / Alt+Space / Alt+Esc never form),
//   Esc while Ctrl is down (Ctrl+Esc, Ctrl+Shift+Esc), and the media / volume / browser / launch keys.
//   Every other key goes to the game untouched (no forwarding: input timing is unchanged).
// - A watchdog restores the settings and exits as soon as the game process is gone, crash included.
// Build: C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /out:KeyGuard.exe KeyGuard.cs
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

static class KeyGuard
{
    const int WH_KEYBOARD_LL = 13;
    const uint WM_QUIT = 0x0012;
    const uint LLKHF_INJECTED = 0x10;
    const uint SPI_GETSTICKYKEYS = 0x003A, SPI_SETSTICKYKEYS = 0x003B;
    const uint SPI_GETFILTERKEYS = 0x0032, SPI_SETFILTERKEYS = 0x0033;
    const uint SPI_GETTOGGLEKEYS = 0x0034, SPI_SETTOGGLEKEYS = 0x0035;
    const uint SKF_STICKYKEYSON = 0x1, SKF_HOTKEYACTIVE = 0x4, SKF_CONFIRMHOTKEY = 0x8;
    const uint FKF_FILTERKEYSON = 0x1, FKF_HOTKEYACTIVE = 0x4, FKF_CONFIRMHOTKEY = 0x8;
    const uint TKF_TOGGLEKEYSON = 0x1, TKF_HOTKEYACTIVE = 0x4, TKF_CONFIRMHOTKEY = 0x8;

    [StructLayout(LayoutKind.Sequential)] struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct STICKYKEYS { public uint cbSize, dwFlags; }
    [StructLayout(LayoutKind.Sequential)] struct TOGGLEKEYS { public uint cbSize, dwFlags; }
    [StructLayout(LayoutKind.Sequential)] struct FILTERKEYS { public uint cbSize, dwFlags, iWaitMSec, iDelayMSec, iRepeatMSec, iBounceMSec; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }
    delegate IntPtr LowLevelProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, LowLevelProc fn, IntPtr mod, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr hwnd, uint min, uint max);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread, uint msg, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfo")] static extern bool SpiSticky(uint a, uint b, ref STICKYKEYS p, uint f);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfo")] static extern bool SpiToggle(uint a, uint b, ref TOGGLEKEYS p, uint f);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfo")] static extern bool SpiFilter(uint a, uint b, ref FILTERKEYS p, uint f);

    static uint gamePid;
    static IntPtr hook = IntPtr.Zero;
    static LowLevelProc proc = Hook;                  // kept alive for the GC
    static STICKYKEYS sk0; static TOGGLEKEYS tk0; static FILTERKEYS fk0;
    static bool spiSaved = false;
    static readonly object restoreLock = new object();
    static bool restored = false;

    static bool GameInFront()
    {
        uint pid;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid == gamePid;
    }

    static bool Swallow(uint vk)
    {
        switch (vk)
        {
            case 0x5B: case 0x5C: case 0x5D: return true;               // LWin, RWin, Apps (menu)
            case 0x12: case 0xA4: case 0xA5: return true;               // Alt, LAlt, RAlt: no Alt+Tab / Alt+F4 / Alt+Space
            case 0x14: return true;                                     // Caps Lock: no caps toggle, no IME switch (owner 2026-10-16)
            case 0x11: case 0xA2: case 0xA3: return true;               // Ctrl, LCtrl, RCtrl: no Ctrl+Shift / Ctrl+Space IME switching
            case 0x1B: return GetAsyncKeyState(0x11) < 0;               // Esc only together with Ctrl (Ctrl+Esc, Ctrl+Shift+Esc)
        }
        return vk >= 0xA6 && vk <= 0xB7;                                // browser / volume / media / launch keys
    }

    static IntPtr Hook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && GameInFront())
        {
            var k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
            if ((k.flags & LLKHF_INJECTED) == 0 && Swallow(k.vkCode)) return (IntPtr)1;
        }
        return CallNextHookEx(hook, nCode, wParam, lParam);
    }

    static void SaveAndDisableShortcuts()
    {
        sk0 = new STICKYKEYS { cbSize = (uint)Marshal.SizeOf(typeof(STICKYKEYS)) };
        tk0 = new TOGGLEKEYS { cbSize = (uint)Marshal.SizeOf(typeof(TOGGLEKEYS)) };
        fk0 = new FILTERKEYS { cbSize = (uint)Marshal.SizeOf(typeof(FILTERKEYS)) };
        SpiSticky(SPI_GETSTICKYKEYS, sk0.cbSize, ref sk0, 0);
        SpiToggle(SPI_GETTOGGLEKEYS, tk0.cbSize, ref tk0, 0);
        SpiFilter(SPI_GETFILTERKEYS, fk0.cbSize, ref fk0, 0);
        spiSaved = true;
        // as in Microsoft's sample: only turn the hotkeys off when the feature itself is not in use
        var sk = sk0; if ((sk.dwFlags & SKF_STICKYKEYSON) == 0) { sk.dwFlags &= ~(SKF_HOTKEYACTIVE | SKF_CONFIRMHOTKEY); SpiSticky(SPI_SETSTICKYKEYS, sk.cbSize, ref sk, 0); }
        var tk = tk0; if ((tk.dwFlags & TKF_TOGGLEKEYSON) == 0) { tk.dwFlags &= ~(TKF_HOTKEYACTIVE | TKF_CONFIRMHOTKEY); SpiToggle(SPI_SETTOGGLEKEYS, tk.cbSize, ref tk, 0); }
        var fk = fk0; if ((fk.dwFlags & FKF_FILTERKEYSON) == 0) { fk.dwFlags &= ~(FKF_HOTKEYACTIVE | FKF_CONFIRMHOTKEY); SpiFilter(SPI_SETFILTERKEYS, fk.cbSize, ref fk, 0); }
    }

    static void Restore()
    {
        lock (restoreLock)
        {
            if (restored) return;
            restored = true;
            if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
            if (spiSaved)
            {
                SpiSticky(SPI_SETSTICKYKEYS, sk0.cbSize, ref sk0, 0);
                SpiToggle(SPI_SETTOGGLEKEYS, tk0.cbSize, ref tk0, 0);
                SpiFilter(SPI_SETFILTERKEYS, fk0.cbSize, ref fk0, 0);
            }
        }
    }

    static int Main(string[] args)
    {
        if (args.Length < 1 || !uint.TryParse(args[0], out gamePid)) return 2;
        bool spi = Array.IndexOf(args, "--no-spi") < 0;
        Process game;
        try { game = Process.GetProcessById((int)gamePid); } catch { return 3; }
        uint mainThread = GetCurrentThreadId();
        if (spi) SaveAndDisableShortcuts();
        AppDomain.CurrentDomain.ProcessExit += (s, e) => Restore();
        hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
        var watchdog = new Thread(() => { try { game.WaitForExit(); } catch { } Restore(); PostThreadMessage(mainThread, WM_QUIT, IntPtr.Zero, IntPtr.Zero); });
        watchdog.IsBackground = true;
        watchdog.Start();
        MSG m;
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
        Restore();
        return 0;
    }
}
