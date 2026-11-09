<#
.SYNOPSIS
Encodes the HD mission-briefing planet videos and their .pvi sidecars into Assets\Movies.

.DESCRIPTION
The stock briefing ignores mod copies of its own emspin.ogv etc., so CR
missions use planet = "custom" with planetDisplay = "cr<world>.ogv". OpenShim's
Custom Planet Video Playback hook reads the matching .pvi sidecar: the clip
plays its approach once from frame 0, then repeats from LoopStartSeconds to
the end. IntroSound is the stock briefing sound for that world (mspin.wav for
the 76-frame Mars/Venus/Elysium clips, emspin.wav for the rest).

The 1440x1080 15 fps masters are an intro followed by a 60-frame rotation that
repeats exactly (from frame 96, or 74-76 for Mars, Venus and Elysium). Each
clip is cut to loop frame + 60 frames, so its last frame leads seamlessly
back to the loop frame. Video only: the sidecar's IntroSound plays the WAV.
Theora quality 10 (the encoder maximum) at the masters' native size.
The masters are not in this repository; pass -SourceDir if they live elsewhere.
#>
param(
    [string]$SourceDir = (Join-Path $env:USERPROFILE "Documents\Google Drive\Ian Files\Battlezone Files\Archives\HD Planet Intros"),
    [string]$OutDir = (Join-Path $PSScriptRoot "..\Assets\Movies")
)
$ErrorActionPreference = "Stop"

$Fps = 15
$Rotation = 60
$Clips = @(
    @{ Out = "crmoon";   Src = "emspin_ex.mp4";  Loop = 96; Sound = "emspin.wav" }  # Moon
    @{ Out = "creuropa"; Src = "jespin_ex.mp4";  Loop = 96; Sound = "emspin.wav" }  # Europa
    @{ Out = "crganym";  Src = "jgspin_ex.mp4";  Loop = 96; Sound = "emspin.wav" }  # Ganymede
    @{ Out = "crio";     Src = "jispin_ex.mp4";  Loop = 96; Sound = "emspin.wav" }  # Io
    @{ Out = "crtitan";  Src = "stspin_ex.mp4";  Loop = 96; Sound = "emspin.wav" }  # Titan
    @{ Out = "crachil";  Src = "uaspin_ex.mp4";  Loop = 96; Sound = "emspin.wav" }  # Achilles
    @{ Out = "crmars";   Src = "maspin_ex.mp4";  Loop = 76; Sound = "mspin.wav" }   # Mars
    @{ Out = "crvenus";  Src = "vnspin_ex.mp4";  Loop = 76; Sound = "mspin.wav" }   # Venus
    @{ Out = "crelys";   Src = "Elysium_ex.mp4"; Loop = 76; Sound = "mspin.wav" }   # Elysium
)

New-Item -ItemType Directory -Force $OutDir | Out-Null
foreach ($clip in $Clips) {
    $src = Join-Path $SourceDir $clip.Src
    $dst = Join-Path $OutDir "$($clip.Out).ogv"
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing master: $src" }
    $frames = $clip.Loop + $Rotation
    $tmp = "$dst.tmp.ogv"
    # Keyframe interval divides the loop frame, so every loop seek lands on a
    # keyframe (libtheora ignores -force_key_frames).
    $gop = if ($clip.Loop % 12 -eq 0) { 12 } else { 19 }
    if ($clip.Loop % $gop -ne 0) { throw "No keyframe interval for loop frame $($clip.Loop)" }
    & ffmpeg -v error -y -i $src -an -frames:v $frames -pix_fmt yuv420p `
        -g $gop -c:v libtheora -q:v 10 $tmp
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed for $($clip.Src)" }
    $count = & ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 $tmp
    if ($LASTEXITCODE -ne 0 -or [int]$count -ne $frames) { Remove-Item -LiteralPath $tmp; throw "$($clip.Out): '$count' frames, expected $frames" }
    Move-Item -LiteralPath $tmp -Destination $dst -Force

    # OpenShim rounds LoopStartSeconds to the nearest decoded frame.
    $seconds = ($clip.Loop / $Fps).ToString("0.0###", [Globalization.CultureInfo]::InvariantCulture)
    $pvi = "[PlanetVideo]`r`nLoopStartSeconds = $seconds`r`nIntroSound = `"$($clip.Sound)`"`r`nStartAtLoop = 0`r`n"
    [IO.File]::WriteAllText((Join-Path $OutDir "$($clip.Out).pvi"), $pvi, [Text.UTF8Encoding]::new($false))
    "{0,-9} {1,4} frames  loop {2} ({3} s)  {4:N1} MB" -f $clip.Out, $count, $clip.Loop, $seconds, ((Get-Item $dst).Length / 1MB)
}
