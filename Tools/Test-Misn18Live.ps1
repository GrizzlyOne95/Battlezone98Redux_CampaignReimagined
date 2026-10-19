# Mission 18 live scenarios for the OpenShim co-op flow harness (Run-BZRCoopMission.ps1).
#
# Dot-sourced by the harness after the lobby has launched the mission on every
# client, so the Invoke-CRFlow family, Save-CRFlowShots and the probe are in
# scope. Use Tools\Run-Misn18Live.ps1 to stage the content, build the lobby
# listing and run one or more cases. Nothing here focuses a window, sends input
# or touches a game process: every action is a Lua chunk run inside the mission
# by the probe, and captures are PrintWindow grabs of each client.
#
#   -Case smoke   the mission loads with CR active; storm, water and wake modules
#                 initialise and report no errors
#   -Case storm   the full storm ladder (opening, search, found, core1-3, collapse,
#                 final) and then the win, the extraction ending and the result
#   -Case win     the shortest honest win: thrusters, transdestroyedcam shot,
#                 home before the countdown ends, extraction, success
#   -Case loss    the countdown expires with the leader past 400 m: left-behind shot
#                 and failure
#   -Case wakes   craft driven low over water and mud (CRWake), captured from a
#                 scripted view
#
# One scripted free view (a pair of camera pods) keeps the HUD out of the frames.
# It is released before every mission cinematic: the mission pops the camera stack
# itself and a test camera across it raises a modal "Camera Stack" alert.
param(
    [ValidateSet('smoke', 'storm', 'win', 'loss', 'wakes')][string]$Case = 'smoke',
    [int]$HostClient = 0,
    [int]$OpeningTimeoutSeconds = 150
)

$script:M18Clients = @(Get-CRFlowClientIndices)
$script:M18Guests = @($script:M18Clients | Where-Object { $_ -ne $HostClient })
$script:M18Peers = $script:M18Clients.Count

# ------------------------------------------------------------------ helpers --

function Invoke-All([string]$Lua) {
    foreach ($c in $script:M18Clients) { Invoke-CRFlow $c $Lua | Out-Null }
}

function Save-Shot([string]$Name) {
    # Same numbering as the step shots; the name keeps every shot distinct.
    Save-CRFlowShots $Name | Out-Null
}

function Get-LiveClientLog([int]$Client) {
    $c = Get-CRFlowClient $Client
    Get-CRFlowLogPath $c
}

$script:SetupLua = @'
pcall(function()
  if exu and exu.SetViewportOverlaysEnabled then exu.SetViewportOverlaysEnabled(false) end
  local p = require("PersistentConfig"); p.Settings.WeaponStatsHud = false; p._DestroyAllPdaOverlays()
end)
every('liveHeal', 0.5, function() heal(me()) end)
return true
'@

# Hold the Fury waves away from the player; never touches the transport or thrusters.
$script:PurgeLua = @'
every('livePurge', 1.5, function() killTeam(6, '^hvs'); killTeam(6, '^crfraz'); return false end)
return true
'@

function Get-ViewLua([double]$Dist, [double]$Up, [double]$Bearing, [double]$LookD, [double]$LookY, [bool]$Tornado = $false) {
@"
M.liveView = { dist = $Dist, up = $Up, brg = $Bearing, lookd = $LookD, looky = $LookY, tornado = $($Tornado.ToString().ToLower()) }
local function pod(n, v)
  local h = M[n]
  if not (h and IsValid(h)) then h = BuildObject('apcamr', 0, v); M[n] = h end
  SetPosition(h, v)
  return h
end
if not M.liveViewOn then
  M.liveViewOn = true
  CameraReady()
  every('liveView', 0.05, function()
    local v = M.liveView
    local me = GetPlayerHandle()
    if not (v and IsValid(me)) then return end
    local p = GetPosition(me)
    local r = math.rad(v.brg)
    local ax, az = p.x + math.sin(r) * v.dist, p.z + math.cos(r) * v.dist
    local ay = math.max(p.y + v.up, (GetTerrainHeightAndNormal(SetVector(ax, 0, az))) + 3)
    local bx, by, bz = p.x - math.sin(r) * v.lookd, p.y + v.looky, p.z - math.cos(r) * v.lookd
    local s = M.cr18Storm
    if v.tornado and s and s.tornado then
      bx, bz = s.tornadoX, s.tornadoZ
      by = (GetTerrainHeightAndNormal(SetVector(bx, 0, bz))) + 90
    end
    pod('liveCamA', SetVector(ax, ay, az)); pod('liveCamB', SetVector(bx, by, bz))
    CameraObject(M.liveCamA, 0, 0, 0, M.liveCamB)
  end)
end
return true
"@
}

$script:ReleaseViewLua = @'
if M.liveViewOn then
  M.liveViewOn = false
  cancel('liveView')
  CameraFinish()
end
for _, n in ipairs({ 'liveCamA', 'liveCamB' }) do
  if M[n] and IsValid(M[n]) then RemoveObject(M[n]) end
  M[n] = nil
end
return true
'@

function Set-View([int]$Client, [double]$Dist = 26, [double]$Up = 5, [double]$Bearing = 200, [double]$LookD = 40, [double]$LookY = 8, [switch]$Tornado) {
    Invoke-CRFlow $Client (Get-ViewLua $Dist $Up $Bearing $LookD $LookY ([bool]$Tornado)) | Out-Null
}

function Set-ViewAll([double]$Dist = 26, [double]$Up = 5, [double]$Bearing = 200, [double]$LookD = 40, [double]$LookY = 8, [switch]$Tornado) {
    foreach ($c in $script:M18Clients) { Set-View $c $Dist $Up $Bearing $LookD $LookY -Tornado:$Tornado }
}

function Clear-ViewAll { Invoke-All $script:ReleaseViewLua }

function Get-StormState([int]$Client) {
    Invoke-CRFlow $Client @'
local s = M.cr18Storm
if not s then return { missing = true } end
return { name = s.name, phase = s.phase, level = s.level, wind = s.wind, bolts = s.bolts, boltsSent = s.boltsSent, tornado = s.tornado,
  tornadoFx = s.tornadoFx, tiles = s.tiles, totalTiles = s.totalTiles, cracks = s.cracks, errors = s.errors, error = s.error,
  groundError = s.groundError, templates = s.templates, quake = s.quakeMagnitude, sky = s.sky, water = s.water, age = s.age }
'@
}

function Wait-Phase([int]$Client, [string]$Name, [int]$TimeoutSeconds = 40) {
    Wait-CRFlow $Client "local s = M.cr18Storm; return s and s.name == '$Name' and s" -TimeoutSeconds $TimeoutSeconds | Out-Null
}

function Get-Systems([int]$Client) {
    Invoke-CRFlow $Client @'
local out = { wake = {}, weather = {} }
local okW, W = pcall(require, 'CRWake')
if okW and type(W) == 'table' then
  out.wake = { initialized = W.Initialized, usable = W.Usable, disabled = W.Disabled, count = W.Count, avail = W.Avail, failures = W.Failures, stats = W.Stats, surface = type(W.Surface) == 'string' and W.Surface or (W.Surface and 'resolver' or nil) }
end
local okC, C = pcall(require, 'CRWeather')
if okC and type(C) == 'table' and C.DescribeLiveSystems then
  local ok, n = pcall(C.DescribeLiveSystems)
  out.weather = { ok = ok, live = ok and n or tostring(n) }
end
return out
'@
}

function Get-Flags([int]$Client) {
    Invoke-CRFlow $Client @'
return { started = M.coopMissionStarted, opening = M.openingcindone, found = M.transportfound, z = M.z, trans = M.transdestroyed,
  won = M.missionwon, blast = M.blastoff, fail1 = M.fail1, fail3 = M.fail3, coopFailed = M.coopFailed, result = M.coopResult,
  cin = M.cr18 and M.cr18.cin ~= nil, timerStarted = M.cr18 and M.cr18.timerStarted, phase = M.cr18 and M.cr18.phase,
  ext = M.cr18 and M.cr18.ext ~= nil, extractDone = M.cr18 and M.cr18.extractDone, timer = GetCockpitTimer and GetCockpitTimer() }
'@
}

# Dropships and the base cargo as one client sees them, for host/guest comparison.
function Get-ExtractionSample([int]$Client) {
    Invoke-CRFlow $Client @'
local out = {}
local iter = (type(AllObjects) == 'function' and AllObjects) or AllCraft
for h in iter() do
  local odf = GetOdf(h) or ''
  if odf:find('^avdrop') or odf:find('^avrecy') or odf:find('^avmuf') then
    local p = GetPosition(h)
    out[#out + 1] = { odf = odf, x = math.floor(p.x * 10) / 10, y = math.floor(p.y * 10) / 10, z = math.floor(p.z * 10) / 10 }
  end
end
table.sort(out, function(a, b) if a.odf ~= b.odf then return a.odf < b.odf end if a.x ~= b.x then return a.x < b.x end return a.z < b.z end)
return { t = GetTime(), n = #out, objs = out }
'@
}

function Compare-Extraction($HostSample, $GuestSample, [string]$Label, [double]$Tolerance = 25) {
    # Pair objects of the same odf nearest-first; report the worst gap and any object only one side has.
    $worst = 0.0
    $unmatched = 0
    $guestObjs = New-Object System.Collections.ArrayList
    foreach ($o in @($GuestSample.objs)) { [void]$guestObjs.Add($o) }
    foreach ($o in @($HostSample.objs)) {
        $best = $null; $bestD = 1e9
        foreach ($g in $guestObjs) {
            if ($g.odf -ne $o.odf) { continue }
            $d = [math]::Sqrt([math]::Pow($g.x - $o.x, 2) + [math]::Pow($g.z - $o.z, 2))
            if ($d -lt $bestD) { $best = $g; $bestD = $d }
        }
        if ($best) { [void]$guestObjs.Remove($best); if ($bestD -gt $worst) { $worst = $bestD } } else { $unmatched++ }
    }
    $extra = $guestObjs.Count
    Add-CRFlowCheck "$Label host and guest see the dropship fleet within ${Tolerance} m" ($worst -le $Tolerance -and $unmatched -eq 0 -and $extra -eq 0) @{ worst = [math]::Round($worst, 1); hostOnly = $unmatched; guestOnly = $extra; host = $HostSample.n; guest = $GuestSample.n }
}

function Wait-OpeningDone {
    Wait-CRFlow $HostClient 'return M.openingcindone == true' -TimeoutSeconds $OpeningTimeoutSeconds | Out-Null
}

# ----------------------------------------------------------------- steps --

function Step-Load {
    Invoke-CRFlowStep 'mission 18 loads on every peer with the storm, water and wake modules' {
        $out = @{}
        foreach ($c in $script:M18Clients) {
            Wait-CRFlow $c 'return M.coopMissionStarted == true' -TimeoutSeconds 150 | Out-Null
            Invoke-CRFlow $c $script:SetupLua | Out-Null
            $storm = Wait-CRFlow $c 'local s = M.cr18Storm; return s and s.templates and s' -TimeoutSeconds 90
            $sys = Get-Systems $c
            Add-CRFlowCheck "c$c storm director is running without errors" ((-not $storm.missing) -and ([int]$storm.errors -eq 0) -and (-not $storm.error)) $storm
            Add-CRFlowCheck "c$c storm particle templates registered" ([bool]$storm.templates) $storm
            Add-CRFlowCheck "c$c storm ground (tiles/cracks) reports no error" (-not $storm.groundError) $storm
            Add-CRFlowCheck "c$c CRWake initialised and usable" ([bool]$sys.wake.initialized -and [bool]$sys.wake.usable -and (-not $sys.wake.disabled)) $sys.wake
            $out["c$c"] = @{ storm = $storm; sys = $sys }
        }
        if ($script:M18Guests.Count) { Invoke-CRFlow $HostClient $script:PurgeLua | Out-Null }
        else { Invoke-CRFlow $HostClient $script:PurgeLua | Out-Null }
        $out
    }
}

function Step-Opening {
    Invoke-CRFlowStep 'the opening cinematic plays and the storm opens its search phase' {
        # Without an audio endpoint the opening voice-over reports done at once and the shot is skipped or
        # trivially short (the machine has none over RDP): a missing shot is a warning, not a failure.
        foreach ($c in $script:M18Clients) {
            $seen = $true
            try { Wait-CRFlowOp $c 'CameraPath' -TimeoutSeconds 25 | Out-Null } catch { $seen = $false }
            Add-CRFlowCheck "c$c saw the opening camera path" $seen $null -WarnOnly
        }
        Save-Shot 'opening-mid'
        Wait-OpeningDone
        foreach ($c in $script:M18Clients) { Wait-Phase $c 'search' 30 }
        Get-StormState $HostClient
    }
}

function Step-Found {
    Invoke-CRFlowStep 'the transport is found: storm enters found' {
        Invoke-CRFlow $HostClient 'return tp("transfound", 40)' | Out-Null
        Wait-CRFlow $HostClient 'return M.transportfound == true' -TimeoutSeconds 30 | Out-Null
        foreach ($c in $script:M18Clients) { Wait-Phase $c 'found' 40 }
        Set-View $HostClient -Dist 40 -Up 8 -Bearing 200 -LookD 60 -LookY 55
        Start-Sleep -Seconds 4
        Save-Shot 'found-sky'
        Get-StormState $HostClient
    }
}

function Step-Core([int]$N) {
    Invoke-CRFlowStep "thruster $N destroyed: storm core$N" {
        $name = @('thrusterone', 'thrustertwo', 'thrusterthree', 'thrusterfour')[$N - 1]
        Invoke-CRFlow $HostClient "Damage(M.$name, 1e9); return true" | Out-Null
        Wait-CRFlow $HostClient "return (M.z or 0) >= $N" -TimeoutSeconds 30 | Out-Null
        foreach ($c in $script:M18Clients) { Wait-Phase $c "core$N" 40 }
        Start-Sleep -Seconds 3
        Set-ViewAll -Dist 40 -Up 8 -Bearing (200 + 40 * $N) -LookD 60 -LookY (40 + 8 * $N)
        Start-Sleep -Seconds 4
        Save-Shot "core$N-sky"
        Set-ViewAll -Dist 60 -Up 10 -Bearing 20 -LookD 10 -LookY 10 -Tornado
        Start-Sleep -Seconds 4
        Save-Shot "core$N-tornado"
        Get-StormState $HostClient
    }
}

function Step-Collapse {
    Invoke-CRFlowStep 'fourth thruster: the transport-destroyed shot, the collapse and the countdown' {
        Clear-ViewAll
        Start-Sleep -Seconds 1
        Invoke-CRFlow $HostClient 'Damage(M.thrusterfour, 1e9); return true' | Out-Null
        Wait-CRFlow $HostClient 'return M.transdestroyed == true' -TimeoutSeconds 30 | Out-Null
        foreach ($c in $script:M18Clients) { Wait-Phase $c 'collapse' 40 }
        Start-Sleep -Milliseconds 2500
        Save-Shot 'transdestroyed-shot-a'
        Start-Sleep -Seconds 3
        Save-Shot 'transdestroyed-shot-b'
        foreach ($c in $script:M18Clients) { Wait-CRFlowOp $c 'StartCockpitTimer' -TimeoutSeconds 40 | Out-Null }
        $t1 = Invoke-CRFlow $HostClient 'return { timer = (M.cr18 and M.cr18.timerEnd) and (M.cr18.timerEnd - GetTime()) or -1, engine = GetCockpitTimer(), now = GetTime() }'
        Start-Sleep -Seconds 6
        $t2 = Invoke-CRFlow $HostClient 'return { timer = (M.cr18 and M.cr18.timerEnd) and (M.cr18.timerEnd - GetTime()) or -1, engine = GetCockpitTimer(), now = GetTime() }'
        Add-CRFlowCheck 'the leader script countdown is counting down (the engine GetCockpitTimer is the mission clock in MultSTMission)' (([double]$t2.timer -lt [double]$t1.timer - 3) -and ([double]$t1.timer -le 180)) @{ first = $t1; second = $t2 }
        $flags = Get-Flags $HostClient
        Add-CRFlowCheck 'the shot ended and the countdown started on the leader' ([bool]$flags.timerStarted -and (-not $flags.cin)) $flags
        $flags
    }
}

function Step-Final {
    Invoke-CRFlowStep 'the countdown reaches its last 30 seconds: storm enters final' {
        Set-ViewAll -Dist 45 -Up 8 -Bearing 300 -LookD 60 -LookY 50
        # About 150 s of the 180 s countdown; a win would end it, so the leader stays at the thrusters.
        foreach ($c in $script:M18Clients) { Wait-Phase $c 'final' 200 }
        Start-Sleep -Seconds 3
        Save-Shot 'final-sky'
        Set-ViewAll -Dist 60 -Up 10 -Bearing 20 -LookD 10 -LookY 10 -Tornado
        Start-Sleep -Seconds 3
        Save-Shot 'final-tornado'
        $st = Get-StormState $HostClient
        Add-CRFlowCheck 'storm at final has no errors' (([int]$st.errors -eq 0) -and (-not $st.error)) $st
        $st
    }
}

function Step-Sys([string]$Label) {
    Invoke-CRFlowStep "particle systems ($Label)" {
        $out = @{}
        foreach ($c in $script:M18Clients) { $out["c$c"] = Get-Systems $c }
        $out
    } -Soft
}

function Step-Win([switch]$Fast) {
    Invoke-CRFlowStep 'every human gets home: the win opens the extraction ending' {
        Clear-ViewAll
        Start-Sleep -Seconds 1
        # Guests spawn at the base; only the leader has to come home.
        Invoke-CRFlow $HostClient 'return tp(M.avrec, 60)' | Out-Null
        foreach ($c in $script:M18Clients) { Wait-Phase $c 'extract' 60 }
        $flags = Get-Flags $HostClient
        Add-CRFlowCheck 'the win latched and the ending is running on the leader' ([bool]$flags.won -and [bool]$flags.ext) $flags
        $flags
    }
    Invoke-CRFlowStep 'extraction shot 1: dropships land and load' {
        Start-Sleep -Seconds 9
        Save-Shot 'extract-landing'
        $h = Get-ExtractionSample $HostClient
        $guestSamples = @()
        foreach ($g in $script:M18Guests) { $guestSamples += , (Get-ExtractionSample $g) }
        if ($h.n -lt 2) { Add-CRFlowCheck 'the fleet exists on the leader (at least one dropship and the base cargo)' $false $h }
        foreach ($gs in $guestSamples) { Compare-Extraction $h $gs 'shot1 (t~9s)' }
        Start-Sleep -Seconds 8
        Save-Shot 'extract-loading'
        $h2 = Get-ExtractionSample $HostClient
        foreach ($g in $script:M18Guests) { Compare-Extraction $h2 (Get-ExtractionSample $g) 'shot1 (t~17s)' }
        Start-Sleep -Seconds 6
        Save-Shot 'extract-liftoff'
        @{ leader = $h2 }
    }
    Invoke-CRFlowStep 'extraction shot 2: the ascent through the storm' {
        foreach ($c in $script:M18Clients) { Wait-Phase $c 'ascent' 40 }
        Start-Sleep -Seconds 3
        Save-Shot 'ascent-a'
        $h = Get-ExtractionSample $HostClient
        foreach ($g in $script:M18Guests) { Compare-Extraction $h (Get-ExtractionSample $g) 'ascent (t~30s)' -Tolerance 120 }
        Start-Sleep -Seconds 4
        Save-Shot 'ascent-b'
        Get-StormState $HostClient
    }
    Invoke-CRFlowStep 'the mission succeeds on every peer after the ending' {
        foreach ($c in $script:M18Clients) { Wait-CRFlowOp $c 'SucceedMission' -TimeoutSeconds 60 | Out-Null }
        Get-Flags $HostClient
    }
    Test-CRFlowResultParity -Expect SucceedMission -Clients $script:M18Clients
}

# ------------------------------------------------------------------ cases --

function Case-Smoke {
    Step-Load
    Step-Opening
    Invoke-CRFlowStep 'a scripted view of the opening-search sky and ground' {
        Set-ViewAll -Dist 40 -Up 6 -Bearing 200 -LookD 60 -LookY 35
        Start-Sleep -Seconds 4
        Save-Shot 'search-sky'
        Set-ViewAll -Dist 30 -Up 10 -Bearing 120 -LookD 40 -LookY -6
        Start-Sleep -Seconds 3
        Save-Shot 'search-ground'
        Clear-ViewAll
    }
    Step-Sys 'smoke'
}

function Case-Storm {
    Step-Load
    Step-Opening
    Step-Found
    Step-Core 1
    Step-Core 2
    Step-Core 3
    Step-Collapse
    Step-Final
    Step-Sys 'final'
    Step-Win
}

function Case-Win {
    Step-Load
    Step-Opening
    Step-Found
    Invoke-CRFlowStep 'three thrusters down quickly' {
        foreach ($n in 1..3) {
            $name = @('thrusterone', 'thrustertwo', 'thrusterthree')[$n - 1]
            Invoke-CRFlow $HostClient "Damage(M.$name, 1e9); return true" | Out-Null
            Wait-CRFlow $HostClient "return (M.z or 0) >= $n" -TimeoutSeconds 30 | Out-Null
        }
        foreach ($c in $script:M18Clients) { Wait-Phase $c 'core3' 40 }
    }
    Step-Collapse
    Step-Win -Fast
}

function Case-Loss {
    Step-Load
    Step-Opening
    Step-Found
    Invoke-CRFlowStep 'all four thrusters down' {
        foreach ($n in 1..4) {
            $name = @('thrusterone', 'thrustertwo', 'thrusterthree', 'thrusterfour')[$n - 1]
            if ($n -eq 4) { Clear-ViewAll }
            Invoke-CRFlow $HostClient "Damage(M.$name, 1e9); return true" | Out-Null
            Wait-CRFlow $HostClient "return (M.z or 0) >= $n" -TimeoutSeconds 30 | Out-Null
        }
        Wait-CRFlow $HostClient 'return M.transdestroyed == true' -TimeoutSeconds 30 | Out-Null
    }
    Invoke-CRFlowStep 'the transport-destroyed shot and the countdown start' {
        foreach ($c in $script:M18Clients) { Wait-CRFlowOp $c 'StartCockpitTimer' -TimeoutSeconds 40 | Out-Null }
        Save-Shot 'countdown-started'
        Get-Flags $HostClient
    }
    Invoke-CRFlowStep 'the countdown runs out with the leader past 400 m: left behind' {
        # The leader stays at the thrusters (about 2.9 km from the Texas). Any guest also stays put at the base
        # in a co-op run, so the all-near and any-far gates are both exercised by the leader alone.
        foreach ($c in $script:M18Clients) { Wait-CRFlow $c 'return M.cr18Storm and M.cr18Storm.name == "final"' -TimeoutSeconds 200 | Out-Null }
        Save-Shot 'loss-final'
        Wait-CRFlow $HostClient 'return M.blastoff == true' -TimeoutSeconds 60 | Out-Null
        Start-Sleep -Seconds 4
        Save-Shot 'left-behind-a'
        Start-Sleep -Seconds 4
        Save-Shot 'left-behind-b'
        foreach ($c in $script:M18Clients) { Wait-CRFlowOp $c 'FailMission' -TimeoutSeconds 60 | Out-Null }
        Get-Flags $HostClient
    }
    Test-CRFlowResultParity -Expect FailMission -Clients $script:M18Clients
}

$script:WakeRun = @'
-- Craft shuttled over a stretch of ground at speed. Mask water first, then mud; the mover sets position and velocity
-- every tick (CRWake reads GetVelocity), cameras follow from a pod pair.
local function terrain(x, z) return (GetTerrainHeightAndNormal(SetVector(x, 0, z))) end
local function waterCell()
  local sites = require('CRStorm18Sites')
  local m = sites.watermask
  if not m then return nil end
  local best
  for i, row in ipairs(m.rows) do
    local rowIndex = m.firstRow + i - 1
    if #row >= 2 and (not best or row[2] > best.len) then
      best = { len = row[2], x = (row[1] + row[2] / 2) * m.cell + m.originX, z = rowIndex * m.cell + m.originZ, span = row[2] * m.cell }
    end
  end
  return best
end
local w = waterCell()
return w
'@

function Case-Wakes {
    Step-Load
    Step-Opening
    Invoke-CRFlowStep 'find a stretch of water in the mission mask' {
        $w = Invoke-CRFlow $HostClient $script:WakeRun
        Add-CRFlowCheck 'the mission water mask has a cell wide enough to drive across' ($null -ne $w) $w
        $script:WakeWater = $w
        $w
    }
    foreach ($surface in @('water', 'mud')) {
        Invoke-CRFlowStep "craft shuttled over $surface" {
            $w = $script:WakeWater
            # Mud: a stretch of the plain 400 m north of the water.
            $x0 = [double]$w.x
            $z0 = if ($surface -eq 'water') { [double]$w.z } else { [double]$w.z + 400 }
            foreach ($c in $script:M18Clients) {
                Invoke-CRFlow $c @"
M.wakeSurface = '$surface'
M.wakeCraft = M.wakeCraft or {}
local x0, z0 = $x0, $z0
local function terrain(x, z) return (GetTerrainHeightAndNormal(SetVector(x, 0, z))) end
for i = 1, 3 do
  local h = M.wakeCraft[i]
  if not (h and IsValid(h)) then h = BuildObject(i == 2 and 'avtank' or 'avfimp', 1, SetVector(x0, terrain(x0, z0) + 2, z0 + i * 6)); M.wakeCraft[i] = h end
end
M.wakeT = 0
every('wakeMove', 0.05, function()
  M.wakeT = M.wakeT + 0.05
  local speed = 26
  local span = 90
  local s = (M.wakeT * speed) % (2 * span)
  local dir = 1
  if s > span then s = 2 * span - s; dir = -1 end
  for i, h in ipairs(M.wakeCraft) do
    if IsValid(h) then
      local x = x0 + s - span / 2
      local z = z0 + i * 7
      SetPosition(h, SetVector(x, terrain(x, z) + 1.6, z))
      SetVelocity(h, SetVector(speed * dir, 0, 0))
    end
  end
  return false
end)
SetPosition(GetPlayerHandle(), SetVector(x0 - 50, terrain(x0 - 50, z0 - 30) + 3, z0 - 30))
return true
"@ | Out-Null
                # A fixed view over the lane: 28 m south of it, 7 m up, looking along the shuttling craft.
                Invoke-CRFlow $c @"
local x0, z0 = $x0, $z0
local function terrain(x, z) return (GetTerrainHeightAndNormal(SetVector(x, 0, z))) end
local function pod(n, v)
  local h = M[n]
  if not (h and IsValid(h)) then h = BuildObject('apcamr', 0, v); M[n] = h end
  SetPosition(h, v)
  return h
end
if not M.liveViewOn then M.liveViewOn = true; CameraReady() end
cancel('liveView')
every('liveView', 0.05, function()
  pod('liveCamA', SetVector(x0 - 10, terrain(x0 - 10, z0 - 26) + 8, z0 - 26))
  pod('liveCamB', SetVector(x0, terrain(x0, z0 + 14) + 1, z0 + 14))
  CameraObject(M.liveCamA, 0, 0, 0, M.liveCamB)
end)
return true
"@ | Out-Null
            }
            Start-Sleep -Seconds 5
            Save-Shot "wake-$surface-a"
            Start-Sleep -Seconds 3
            Save-Shot "wake-$surface-b"
            $out = @{}
            foreach ($c in $script:M18Clients) { $out["c$c"] = Get-Systems $c }
            $stats = $out["c$HostClient"].wake
            Add-CRFlowCheck "CRWake created systems over $surface" ([int]$stats.stats.created -gt 0 -or [int]$stats.count -gt 0) $stats
            Add-CRFlowCheck "CRWake raised no Lua errors over $surface" ([int]$stats.stats.errors -eq 0 -and -not $stats.disabled) $stats
            $out
        }
    }
    Invoke-CRFlowStep 'wake craft removed' {
        Clear-ViewAll
        Invoke-All "cancel('wakeMove'); for _, h in ipairs(M.wakeCraft or {}) do if IsValid(h) then RemoveObject(h) end end; M.wakeCraft = nil; return true"
    }
}

# ------------------------------------------------------------------- run --

Write-Host "[misn18] case '$Case' with $($script:M18Peers) peer(s)"
try {
switch ($Case) {
    'smoke' { Case-Smoke }
    'storm' { Case-Storm }
    'win'   { Case-Win }
    'loss'  { Case-Loss }
    'wakes' { Case-Wakes }
}

}
catch {
    try { Clear-ViewAll } catch { }
    throw
}

# Snapshot the engine logs so the evidence survives even if the teardown loses them.
Invoke-CRFlowStep 'collect log excerpts' {
    $dir = New-Item -ItemType Directory -Force -Path (Join-Path $script:CRFlowRun.runDir 'live-logs')
    $pattern = 'CR18|CRWake|CR17|StormSwirl|Mud|Cascade|CRDrop|particle|Particle|material|Material|shader|Shader|Lua .*error|CreateParticleSystem'
    foreach ($c in $script:M18Clients) {
        $client = Get-CRFlowClient $c
        $log = Get-CRFlowLogPath $client
        if ($log) {
            Copy-Item -LiteralPath $log -Destination (Join-Path $dir "c$c-BZLogger.txt") -Force -ErrorAction SilentlyContinue
        }
        foreach ($name in 'BZOgreLogfile.log', 'openshim.log') {
            $p = Get-ChildItem -LiteralPath $client.dir, (Join-Path $client.dir 'logs') -Filter $name -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($p) {
                Copy-Item -LiteralPath $p.FullName -Destination (Join-Path $dir "c$c-$name") -Force -ErrorAction SilentlyContinue
                Select-String -LiteralPath $p.FullName -Pattern $pattern -ErrorAction SilentlyContinue | Select-Object -First 200 |
                    ForEach-Object { $_.Line } | Set-Content -LiteralPath (Join-Path $dir "c$c-$name.excerpt.txt")
            }
        }
    }
    $dir.FullName
}
