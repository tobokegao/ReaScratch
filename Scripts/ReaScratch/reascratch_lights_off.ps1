# ReaScratch (⚪124): every light of the controllers off once REAPER has closed. reascratch_video_sync.lua starts this when it
# starts; it waits for the REAPER that started it to close. On quit REAPER closes its MIDI outputs before scripts end
# (nothing a script sends then arrives), and while REAPER runs it holds the outputs, so this opens them itself after
# REAPER is gone and sends note / CC value 0 on every channel to the outputs listed in -NamesFile (one name a line,
# written by the video sync while it runs). One a REAPER (a second one for the same REAPER ends at once).
# -Names "a|b" instead of the file, -Now = no waiting (for a test)
param([string]$NamesFile = "", [string]$Names = "", [switch]$Now)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class RsMidiOut {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CAPS { public ushort wMid; public ushort wPid; public uint vDriverVersion;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
    public ushort wTechnology; public ushort wVoices; public ushort wNotes; public ushort wChannelMask; public uint dwSupport; }
  [DllImport("winmm.dll")] public static extern uint midiOutGetNumDevs();
  [DllImport("winmm.dll", CharSet = CharSet.Unicode)] public static extern uint midiOutGetDevCaps(UIntPtr id, ref CAPS caps, uint size);
  [DllImport("winmm.dll")] public static extern uint midiOutOpen(out IntPtr h, uint id, IntPtr cb, IntPtr inst, uint flags);
  [DllImport("winmm.dll")] public static extern uint midiOutShortMsg(IntPtr h, uint msg);
  [DllImport("winmm.dll")] public static extern uint midiOutClose(IntPtr h);
  public static string Name(uint i) { CAPS c = new CAPS(); midiOutGetDevCaps((UIntPtr)i, ref c, (uint)Marshal.SizeOf(c)); return c.szPname; }
}
// ((⚪165) note / CC 0 on every channel, here: one by one from PowerShell took about 1.5 s a device. The devices take them
// at MIDI's speed (the Reloop Buddy 4 s, the APC40 mkII 1.6 s), so each has its own thread (one after the other, the
// APC40 went dark 6 s after REAPER closed, user's report 2026-10-14). Cancel (a newer REAPER) ends them at the next channel
public class RsOff {
  public static volatile bool Cancel;
  public IntPtr H; public string Name; public int Channels; public long Ms; System.Threading.Thread T;
  public RsOff(IntPtr h, string name) {
    H = h; Name = name;
    T = new System.Threading.Thread(Run); T.IsBackground = true; T.Start();
  }
  void Run() {
    var sw = System.Diagnostics.Stopwatch.StartNew();
    for (uint ch = 0; ch < 16 && !Cancel; ch++) {
      for (uint k = 0; k < 128; k++) { RsMidiOut.midiOutShortMsg(H, (0x90u | ch) | (k << 8)); RsMidiOut.midiOutShortMsg(H, (0xB0u | ch) | (k << 8)); }
      Channels = (int)ch + 1;
    }
    Ms = sw.ElapsedMilliseconds;
    RsMidiOut.midiOutClose(H);
  }
  public bool Alive { get { return T.IsAlive; } }
}
"@

$log = if ($NamesFile -ne "") { [IO.Path]::ChangeExtension($NamesFile, ".log") } else { "" }
function Say($t) { if ($log -ne "") { Add-Content -Path $log -Value ((Get-Date -Format "HH:mm:ss.fff") + " " + $t) } }
# ((2026-10-13, user's report: sometimes the lights stayed on) the log kept across runs (the last 300 lines), to see why
if ($log -ne "" -and (Test-Path $log)) { $old = @(Get-Content $log -Encoding UTF8); if ($old.Count -gt 300) { Set-Content -Path $log -Value $old[($old.Count - 300)..($old.Count - 1)] -Encoding UTF8 } }
Say "---- start"
if (-not $Now) {
  # the REAPER that started this (its parent, or the parent's parent through a shell)
  $rp = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
  $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$rp" -ErrorAction SilentlyContinue
  Say ("parent " + $rp + " " + $(if ($pp) { $pp.Name } else { "(gone)" }))
  if ($pp -and $pp.Name -notlike "reaper*") { $rp = $pp.ParentProcessId; Say ("its parent " + $rp) }
  $proc = Get-Process -Id $rp -ErrorAction SilentlyContinue
  # ((2026-10-13) one a REAPER, not one in all: the mutex was one name, so the watcher of a REAPER started while the last
  # one's was still sending ended at once, and that REAPER's lights then stayed on at quit)
  $mtx = New-Object System.Threading.Mutex($false, "ReaScratchLightsOff_" + $rp)
  if (-not $mtx.WaitOne(0)) { Say ("already waiting for " + $rp); exit 0 }
  $born = if ($proc) { $proc.StartTime } else { Get-Date }
  if ($proc) { Say ("waiting for " + $proc.ProcessName + " " + $rp); $proc.WaitForExit() } else { Say "no REAPER found" }
  Start-Sleep -Milliseconds 500
}
# ((2026-10-13, user's report: the APC40's knob rings dark after a restart) a REAPER started after this one (a restart)
# owns the lights now: the zeros sent here also set the rings' type to none, which it sends only at its start.
# ((⚪165, user's report 2026-10-14: the APC40 blinked at start, sometimes) looked at before every device and every try to
# open it, not only once: the log showed the APC40's zeros 0.4-1.2 s after the restarted REAPER's video sync had started)
function Newer {
  if ($Now) { return $false }
  $nw = @(Get-Process reaper* -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $born })
  if ($nw.Count -gt 0) { Say ("a newer REAPER runs (" + $nw[0].Id + "): lights left alone"); return $true }
  return $false
}
if (-not $Now) {
  if (Newer) { $mtx.ReleaseMutex(); exit 0 }
} else {
  $mtx = New-Object System.Threading.Mutex($false, "ReaScratchLightsOff_now")
  if (-not $mtx.WaitOne(0)) { exit 0 }
}

$list = @()
if ($NamesFile -ne "" -and (Test-Path $NamesFile)) { $list = Get-Content $NamesFile -Encoding UTF8 } else { $list = $Names.Split("|") }
$want = $list | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim().ToLower() }
$n = [RsMidiOut]::midiOutGetNumDevs()
$jobs = @()
$stop = $false
for ($i = 0; $i -lt $n -and -not $stop; $i++) {
  $nm = [RsMidiOut]::Name($i).ToLower()
  if (-not ($want -contains $nm)) { continue }
  $h = [IntPtr]::Zero
  # ((2026-10-13) right after REAPER closes the output can still be busy: try again for up to 10 s (it was given up at once)
  $r = 1
  for ($t = 0; $t -lt 40; $t++) {
    if (Newer) { $stop = $true; break }
    $r = [RsMidiOut]::midiOutOpen([ref]$h, $i, [IntPtr]::Zero, [IntPtr]::Zero, 0); if ($r -eq 0) { break }; Start-Sleep -Milliseconds 250
  }
  if ($stop) { if ($r -eq 0) { [void][RsMidiOut]::midiOutClose($h) }; break }
  if ($r -ne 0) { Say ("could not open " + $nm + " (error " + $r + ")"); continue }
  if ($t -gt 0) { Say ("opened " + $nm + " after " + $t + " tries") }
  $jobs += New-Object RsOff($h, $nm)   # (starts sending at once, while the next device is opened)
}
# every device at the same time; a newer REAPER (looked for every 0.1 s) stops them all
if ($stop) { [RsOff]::Cancel = $true }
while (@($jobs | Where-Object { $_.Alive }).Count -gt 0) {
  if (-not [RsOff]::Cancel -and (Newer)) { [RsOff]::Cancel = $true }
  Start-Sleep -Milliseconds 100
}
foreach ($j in $jobs) {
  if ($j.Channels -lt 16) { Say ("stopped at channel " + ($j.Channels + 1) + ": " + $j.Name) }
  else { Say ("lights off: " + $j.Name + " (" + $j.Ms + " ms)") }
}
$mtx.ReleaseMutex()
