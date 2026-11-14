# ReleaseStress.Lib.ps1 -- helpers for Invoke-ReleaseStress.ps1 (dot-sourced).
# Windows PowerShell 5.1 (System.Drawing capture). No dependency on sibling repos.

if (-not ('RS.Native' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
namespace RS {
public static class Native {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    static Native() { SetProcessDPIAware(); }
    delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
    [DllImport("user32.dll")] static extern uint GetGuiResources(IntPtr h, uint f);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool b, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }

    public static IntPtr MainWindow(uint pid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, lp) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
                if (sb.Length > 0) { found = h; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static bool Hung(IntPtr h) { return IsHungAppWindow(h); }
    // A minimized game stops simulating (no ESC, 1x1 captures). SW_SHOWNOACTIVATE restores it without taking focus.
    public static bool RestoreIfMinimized(IntPtr h) {
        if (h == IntPtr.Zero || !IsIconic(h)) return false;
        ShowWindow(h, 4); return true;
    }
    // -1 = no answer within timeoutMs, else round-trip ms.
    public static int Ping(IntPtr h, uint timeoutMs) {
        var sw = System.Diagnostics.Stopwatch.StartNew(); IntPtr r;
        IntPtr x = SendMessageTimeout(h, 0, IntPtr.Zero, IntPtr.Zero, 2, timeoutMs, out r);
        return x == IntPtr.Zero ? -1 : (int)sw.ElapsedMilliseconds;
    }
    public static uint Gui(int pid, uint flag) {
        IntPtr p = OpenProcess(0x1000, false, pid);
        if (p == IntPtr.Zero) return 0;
        uint v = GetGuiResources(p, flag); CloseHandle(p); return v;
    }
    public static void Capture(IntPtr h, string path) {
        RECT r; GetClientRect(h, out r);
        using (var bmp = new Bitmap(Math.Max(1, r.R - r.L), Math.Max(1, r.B - r.T), PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc(); PrintWindow(h, hdc, 3); g.ReleaseHdc(hdc);
            bmp.Save(path, ImageFormat.Png);
        }
    }
    // The shell only builds a queued screen while the app believes it is active.
    public static void Activate(IntPtr h) {
        PostMessage(h, 0x001C, (IntPtr)1, IntPtr.Zero);
        PostMessage(h, 0x0006, (IntPtr)1, IntPtr.Zero);
        PostMessage(h, 0x0007, IntPtr.Zero, IntPtr.Zero);
    }
    public static void Key(IntPtr h, int vk, int holdMs) {
        Activate(h);
        PostMessage(h, 0x0100, (IntPtr)vk, (IntPtr)1);
        System.Threading.Thread.Sleep(holdMs);
        PostMessage(h, 0x0101, (IntPtr)vk, unchecked((IntPtr)(int)0xC0000001));
    }
    public static void Close(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }
}
public static class Launcher {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inh, uint fl, IntPtr env, string cwd, ref STARTUPINFO si, out PI pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    // SW_SHOWNOACTIVATE so the first ShowWindow cannot steal the user's focus.
    public static int Start(string exe, string cwd) {
        var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO)); si.dwFlags = 1; si.wShowWindow = 4;
        PI pi;
        if (!CreateProcessW(exe, "\"" + exe + "\" /nointro", IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, cwd, ref si, out pi))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        CloseHandle(pi.hThread); CloseHandle(pi.hProcess); return pi.dwProcessId;
    }
}
}
'@
}

$script:Latin1 = [Text.Encoding]::GetEncoding(28591)

# ------------------------------------------------------------ settings files --
function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'MISSING' }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Set-IniValue([string]$Text, [string]$Section, [string]$Key, [string]$Value) {
    # Replaces "Key = ..." inside [Section] (or adds it right under the header, or adds the section).
    $nl = if ($Text -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [Collections.Generic.List[string]]($Text -split "`r?`n")
    $secIdx = -1; $end = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+?)\]\s*$') {
            if ($secIdx -ge 0) { $end = $i; break }
            if ($Matches[1] -ieq $Section) { $secIdx = $i }
        }
    }
    if ($secIdx -lt 0) { $lines.Add("[$Section]"); $lines.Add("$Key = $Value"); return ($lines -join $nl) }
    for ($i = $secIdx + 1; $i -lt $end; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $lines[$i] = "$Key = $Value"; return ($lines -join $nl) }
    }
    $lines.Insert($secIdx + 1, "$Key = $Value")
    ($lines -join $nl)
}

function Set-OgreVideo([string]$Text, [string]$Width, [string]$Height) {
    # Edits only the active render system's section.
    $nl = if ($Text -match "`r`n") { "`r`n" } else { "`n" }
    if ($Text -notmatch '(?m)Render System=(.+?)\s*$') { throw 'Ogre.cfg has no Render System line' }
    $active = $Matches[1]
    $lines = [Collections.Generic.List[string]]($Text -split "`r?`n")
    $in = $false; $mode = $false; $full = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\[(.+)\]\s*$') { $in = ($Matches[1] -eq $active); continue }
        if (-not $in) { continue }
        if ($lines[$i] -match '^Video Mode=') { $lines[$i] = ('Video Mode={0} x {1,4} @ 32-bit colour' -f $Width, $Height); $mode = $true }
        if ($lines[$i] -match '^Full Screen=') { $lines[$i] = 'Full Screen=No'; $full = $true }
    }
    if (-not ($mode -and $full)) { throw "Ogre.cfg section [$active] lacks Video Mode/Full Screen" }
    ($lines -join $nl)
}

# --------------------------------------------------------------------- logs --
function Read-LogFrom([string]$Path, [long]$Offset) {
    # Returns @{ Text; Length }. Shares with the game's writer. A file shorter than Offset was rotated.
    if (-not (Test-Path -LiteralPath $Path)) { return @{ Text = ''; Length = 0 } }
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite,Delete')
    try {
        if ($fs.Length -lt $Offset) { $Offset = 0 }
        [void]$fs.Seek($Offset, 'Begin')
        $buf = New-Object byte[] ($fs.Length - $Offset)
        $n = $fs.Read($buf, 0, $buf.Length)
        # Offset + bytes read, never $fs.Length: the game may append between the read and that call,
        # and those lines would be skipped for good (a missed trigger/transition line).
        @{ Text = $script:Latin1.GetString($buf, 0, $n); Length = $Offset + $n }
    } finally { $fs.Dispose() }
}

# ---------------------------------------------------------------- cdb stacks --
function Save-Stacks([int]$ProcessId, [string]$OutFile, [string]$CdbPath) {
    if (-not (Test-Path -LiteralPath $CdbPath)) { Set-Content $OutFile "cdb not found at $CdbPath"; return }
    $cmds = [IO.Path]::ChangeExtension($OutFile, '.cdbcmds')
    Set-Content -Path $cmds -Value @('.lines -n', '~*kb 40', 'q') -Encoding ASCII
    $p = Start-Process -FilePath $CdbPath -ArgumentList @('-pv', '-p', $ProcessId, '-cf', "`"$cmds`"") `
        -RedirectStandardOutput $OutFile -RedirectStandardError "$OutFile.err" -NoNewWindow -PassThru
    if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch {} ; Add-Content $OutFile "`n[cdb timed out after 90 s]" }
}

function Copy-LogsSince([string]$GameDir, [string[]]$Dirs, [datetime]$SinceUtc, [string]$Dest) {
    # Copies every .log/.txt/.dmp in $Dirs (top level) modified since $SinceUtc into $Dest, reading with
    # share-delete so a log the game still holds open is copied. Names are flattened (dir__file).
    $null = New-Item -ItemType Directory -Force -Path $Dest
    foreach ($d in $Dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.log', '.txt', '.dmp' -and $_.LastWriteTimeUtc -ge $SinceUtc -and $_.Name -ne 'uiperf_trigger.txt' })) {
            $rel = $f.FullName.Substring($GameDir.Length).TrimStart('\') -replace '[\\/]', '__'
            try {
                $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite,Delete')
                try { $out = [IO.File]::Create((Join-Path $Dest $rel)); try { $fs.CopyTo($out) } finally { $out.Dispose() } } finally { $fs.Dispose() }
            } catch { Write-Warning "copy $($f.Name): $_" }
        }
    }
}
