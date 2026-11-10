-- Faithful stock misns5 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns5Mission.cpp
-- Source blob: 27a86be1800531bf576a211acb4fdd356458260e.
-- All disabled gameplay code is retained inline; exact original declarations,
-- comments, and native serialization are in References/Misns5Source/.
-- No EXU/OpenShim or campaign helper is required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/MISNS5_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Titan weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Misns5CoopSourceParity.py).
-- CR co-op layer <<

local function NewState()
    -- Native Load initializes all fields before Setup, including unused ones.
    return {
        camera1 = false, start_done = false, defender = false,
        com_dead = false, last_phase = false, third_attack = false,
        fourth_attack = false, won = false, lost = false,
        second_message = false, third_message = false,
        art_dead = false, apc_here = false,
        add_defender = 99999.0, wave = 99999.0, chaff = 99999.0,
        camera_time = 99999.0, apc_wave = 99999.0,
        wave_count = 0, wave_type = 0, aud = 0,
        -- Handles a1/a2, t1..t4, h1/h2, geyser1/2, recy, muf, commander,
        -- cam1 (unused), and killme begin nil, equivalent to native NULL.
    }
end

-- Initialize before map AddObject callbacks; Start must not erase discovery.
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/MISNS5_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/MISNS5_COOP.md, "Restored content").
local RESTORED_INTEL = true
local SCRAP_PER_GUEST = 10
local Restored
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "misns5", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2, blackDogUnits = true,
    rallyPoints = { [0] = "svrecy0_recycler" },
    -- The chaff fighters, the APC strike and the factory waves are the scaled spawns; the artillery, the
    -- commander walker, the enemy recycler with its guards and the scavengers are not.
    scaledOdfs = { avfigh = true, avapc = true, bvltnk = true, bvhraz = true },
    -- spawn3/spawn4 sit inside the player base; the three outer approaches and the map edge are the fallbacks.
    fallbackEntries = { "spawn5", "spawn6", "spawn7", "edge_path" },
    scrapPerGuest = SCRAP_PER_GUEST,
    failDes = "misns5l1.des",
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    weather = { module = "CRTitanWeather", sites = "CRTitanSitesS5", ops = { "TitanState", "TitanRoll" },
        startLevel = 1, targetLevel = 2,
        beats = function(titan, state, s)
            local beats = s.titanBeats
            if beats == nil then beats = {}; s.titanBeats = beats end
            -- Hazy once the opening briefing is over and the defenders are out.
            if (not beats.hazy) and state.defender then
                beats.hazy = true
                titan.SetTargetLevel(2)
            end
            -- Drizzle closes in with the APC strike on the factory.
            if (not beats.drizzle) and state.h1 ~= nil then
                beats.drizzle = true
                titan.SetTargetLevel(3)
            end
            -- The shroud falls for the last phase: the enemy recycler and the intelligence briefing.
            if (not beats.shroud) and state.last_phase then
                beats.shroud = true
                titan.SetTargetLevel(4)
            end
            if (not beats.easing) and state.won then
                beats.easing = true
                titan.SetTargetLevel(2)
            end
        end },
})
local RESTORED = campaignRuntime ~= nil and campaignRuntime ~= false
local spawn = campaignRuntime and campaignRuntime.Spawn
local BuildObject = campaignRuntime and function(odf, team, where)
    local h = spawn(odf, team, where)
    if odf == "spcamr" and Restored then Restored.Pod(h) end
    return h
end or BuildObject
local IsOdf = campaignRuntime and campaignRuntime.IsOdf or IsOdf
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local IsAlive = campaignRuntime and campaignRuntime.IsAlive or IsAlive
local GetDistance = campaignRuntime and campaignRuntime.GetDistance or GetDistance
local SetAIP = campaignRuntime and campaignRuntime.SetAIP or SetAIP
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraPath = campaignRuntime and campaignRuntime.CameraPath or CameraPath
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- The enemy is team 5 in the co-op map; the body still reads and writes the DLL's team 2.
-- Stock fix: AddObject's `GetTeamNum(h) ~= 2` filter would otherwise ignore every enemy (commander, routing).
local GetTeamNum = campaignRuntime and function(h)
    local team = GetTeamNum(h)
    if team == 5 then return 2 end
    return team
end or GetTeamNum
-- Stock fix: the DLL's strategic AI for team 2 is Start()'s SetAIControl(2, true); the runtime already enables
-- team 5 at chunk load (SetAIControl is a chunk-root call), so Start's call becomes a no-op.
local SetAIControl = campaignRuntime and function() end or SetAIControl
local SetPilot = campaignRuntime and function(team, amount)
    if team == 2 then team = 5 end
    return SetPilot(team, amount)
end or SetPilot
-- The 10 starting scrap is the shared base's: each guest adds a bounded bonus (same rule as SetScrap).
local AddScrap = campaignRuntime and function(team, amount)
    if team == 1 then amount = amount + SCRAP_PER_GUEST * (campaignRuntime.HumanCount() - 1)
    elseif team == 2 then team = 5 end
    return AddScrap(team, amount)
end or AddScrap
-- CR co-op runtime <<
local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Command(command, h, target)
    -- PORT FIX: native null/stale handles cannot issue useful orders. Guard
    -- Lua's handle overloads on failed spawns/missing map objects; valid orders,
    -- flags and timers remain in the same source order without adding retries.
    if Valid(h) and Valid(target) then command(h, target) end
end
-- CR restored content >>
-- Content the DLL left unfinished, restored in the CR layer only (Docs/MISNS5_COOP.md lists the source block).
-- Gated by a RESTORED_* flag and by the object actually existing.
Restored = {}
if campaignRuntime then
    -- Source: `SetObjectiveOn(killme);  // should be sam`. The intelligence pod (spcamr at path camera1) is built
    -- for the last phase but only the enemy recycler is ever marked. With the restoration the pod is marked too.
    function Restored.Pod(h)
        if not RESTORED_INTEL or not Valid(h) then return end
        pcall(campaignRuntime.SetObjectiveOn, h)
        pcall(campaignRuntime.SetObjectiveName, h, "Intelligence Camera")
    end
end
-- CR restored content <<

function Start()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    -- LuaMission must enable the native AiMission's strategic AI at startup
    -- so the later SetAIP works. Never call SetAIControl from Update or Load.
    SetAIControl(2, true)
end

function AddObject(h)
-- CR co-op callback >>
    if campaignRuntime then
        campaignRuntime.AddObject(h)
        -- Only the authority orders units; guests see the replicated objects.
        if not campaignRuntime.Coop.IsAuthority() then return end
    end
-- CR co-op callback <<
    if not Valid(h) or GetTeamNum(h) ~= 2 then return end
    if IsOdf(h, "avwalk") then
        --[[
				The first walker is
					"the commander"
        ]]
        -- PORT FIX: native commander=h overwrites the first walker whenever
        -- the final AIP builds another. Capture only the first, even after its
        -- death, so reinforcements cannot postpone the intended death trigger.
        -- The original single-commander sequence and 120-second delay are kept.
        if M.commander == nil or M.commander == 0 then M.commander = h end
    end
    if IsOdf(h, "bvltnk") or IsOdf(h, "bvhraz") or IsOdf(h, "avfigh") then
        -- Map objects can arrive before Execute binds recy. Resolve the same
        -- named recycler for those callbacks; later waves use the stored handle.
        Command(Goto, h, M.recy or GetHandle("svrecy0_recycler"))
    end
end

-- Stock bug: misns5.aip asks the Black Dog base for Soviet svturr turrets it cannot build; crns5.aip is the same plan
-- with bvturr.
local SetAIP = (function()
    local stockSetAIP = SetAIP
    local AIP = { ["misns5.aip"] = "crns5.aip" }
    return function(name, ...) return stockSetAIP(AIP[name] or name, ...) end
end)()

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    if not M.start_done then
        M.recy = GetHandle("svrecy0_recycler")
        AddScrap(1, 10)
        M.camera1 = true
        M.camera_time = GetTime() + 17.0
        M.apc_wave = GetTime() + 70.0
        M.start_done = true
        M.t4 = GetHandle("sbhang0_repairdepot")
        M.a1 = BuildObject("avartl", 2, "spawn1")
        M.a2 = BuildObject("avartl", 2, "spawn2")
        CameraReady()
        M.aud = AudioMessage("misns501.wav")
    end
    if M.camera1 then
        if Valid(M.t4) then CameraPath("campath", 5000, 2500, M.t4) end
        if IsAudioMessageDone(M.aud) and not M.second_message then
            M.aud = AudioMessage("misns503.wav")
            M.second_message = true
        end
        --[[
		if ((second_message) && (IsAudioMessageDone(aud))
			&& (!third_message))
		{
			aud=AudioMessage("misns503.wav");
			third_message=true;
		}
        ]]
        -- (GetTime()>camera_time)) -- source's disabled camera deadline.
        -- Keep the audio-driven ending: camera_time is intentionally unused.
        if CameraCancelled() or IsAudioMessageDone(M.aud) then
            M.chaff = GetTime() + 180.0
            M.t1 = GetHandle("sblpow2_powerplant")
            M.t2 = GetHandle("sblpow3_powerplant")
            M.t3 = GetHandle("sblpow4_powerplant")
            M.recy = GetHandle("svrecy0_recycler")
            M.muf = GetHandle("svmuf0_factory")
            M.geyser1 = GetHandle("eggeizr11_geyser")
            M.geyser2 = GetHandle("eggeizr12_geyser")
            Command(Goto, M.recy, M.geyser1)
            Command(Goto, M.muf, M.geyser2)
            Command(Attack, M.a1, M.t1)
            Command(Attack, M.a2, M.t2)
            M.add_defender = GetTime() + 10.0
            CameraFinish()
            ClearObjectives()
            AddObjective("misns501.otf", "white")
            StopAudioMessage(M.aud)
            M.camera1 = false
        end
    end
    if M.defender and not M.third_attack and not IsAlive(M.t1) then
        Command(Attack, M.a1, M.t3)
        M.third_attack = true
    end
    if M.defender and not M.fourth_attack and not IsAlive(M.t2) then
        Command(Attack, M.a2, M.t4)
        M.fourth_attack = true
    end
    if GetTime() > M.add_defender then
        BuildObject("avwalk", 2, "spawn3")
        -- BuildObject("avtank",2,"spawn3");
        M.add_defender = 99999.0
        SetPilot(2, 30) -- in case we load AIP
        M.defender = true
    end
    if M.defender and not M.art_dead and not IsAlive(M.a1) and not IsAlive(M.a2) then
        AudioMessage("misns504.wav")
        M.art_dead = true
    end
    -- PORT FIX: the source tests h1!=NULL but not whether either distance
    -- operand survives. A deleted APC/factory must not announce arrival or
    -- enter a bad overload. The living-APC <100m trigger is unchanged.
    if M.defender and Valid(M.h1) and Valid(M.muf) and not M.apc_here
        and GetDistance(M.h1, M.muf) < 100.0 then
        M.apc_here = true
        AudioMessage("misns505.wav")
    end
    if GetTime() > M.chaff then
        -- rand()%4*10.0f: keep the four discrete 50/60/70/80-second gaps.
        M.chaff = GetTime() + 50.0 + math.random(0, 3) * 10.0
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
        BuildObject("avfigh", 2, "spawn5")
    end
    if GetTime() > M.apc_wave then
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
        M.h1 = BuildObject("avapc", 2, "spawn6")
        M.h2 = BuildObject("avapc", 2, "spawn6")
        M.killme = BuildObject("avrecy", 2, "spawn7")
        local protect = BuildObject("bvtank", 2, "spawn7")
        -- Native Defend(protect,killme) maps to Lua Defend2, not Defend's
        -- priority overload; both guards must defend the enemy recycler.
        Command(Defend2, protect, M.killme)
        protect = BuildObject("bvtank", 2, "spawn7")
        Command(Defend2, protect, M.killme)
        Command(Attack, M.h1, M.muf)
        Command(Attack, M.h2, M.muf)
        M.apc_wave = 99999.0
    end
    if M.defender and not IsAlive(M.commander) and not M.com_dead then
        M.wave = GetTime() + 120.0
        M.com_dead = true
    end
    if GetTime() > M.wave then
        M.wave_count = M.wave_count + 1
        M.wave = GetTime() + 180.0
        --wave_type=rand()%2
        AudioMessage("misns505.wav")
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
        if M.wave_count ~= 1 then
            BuildObject("bvltnk", 2, "spawn5")
            BuildObject("bvltnk", 2, "spawn5")
            BuildObject("bvltnk", 2, "spawn5")
        else
            BuildObject("bvhraz", 2, "spawn6")
            BuildObject("bvhraz", 2, "spawn6")
            BuildObject("bvhraz", 2, "spawn6")
        end
        if M.wave_count == 3 then
            --[[
				Build a recycler
				at spawn7 avrecy
				
            ]]
            M.last_phase = true
            -- killme=BuildObject("avrecy",2,"spawn7");
            BuildObject("avscav", 2, "spawn7")
            BuildObject("avscav", 2, "spawn7")
            local sam = BuildObject("spcamr", 1, "camera1")
            if Valid(M.killme) then SetObjectiveOn(M.killme) end -- should be sam
            -- The source comment suggests sam, but the active code marks
            -- killme. Keep that marker and unused camera pod; changing the
            -- intelligence presentation requires an explicit design decision.
            AddObjective("misns502.otf", "white")
            AudioMessage("misns506.wav")
            --[[
				Now LoadAIP.
            ]]
            SetAIP("misns5.aip")
            --[[
				Our intelligence.
            ]]
        end
    end
    if M.last_phase and not IsAlive(M.killme) and not M.won and not M.lost then
        M.won = true
        AudioMessage("misns508.wav")
        SucceedMission(GetTime() + 10.0, "misns5w1.des")
    end
    if not IsAlive(M.recy) and not M.lost and not M.won then
        M.lost = true
        AudioMessage("misns507.wav")
        FailMission(GetTime() + 10.0, "misns5l1.des")
    end
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.AfterUpdate() end
-- CR co-op callback <<
end

function Save()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Save() end
-- CR co-op callback <<
    return M
end

function Load(state)
    -- LuaMission restores game handles/audio and primitive table fields;
    -- never replay Setup, briefing, spawns or timers on load.
    M = state
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Load() end
-- CR co-op callback <<
end
-- CR co-op callbacks >>
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
-- CR co-op callbacks <<
