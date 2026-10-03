-- Faithful stock misns5 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns5Mission.cpp
-- Source blob: 27a86be1800531bf576a211acb4fdd356458260e.
-- All disabled gameplay code is retained inline; exact original declarations,
-- comments, and native serialization are in References/Misns5Source/.
-- No EXU/OpenShim or campaign helper is required.

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
local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Command(command, h, target)
    -- PORT FIX: native null/stale handles cannot issue useful orders. Guard
    -- Lua's handle overloads on failed spawns/missing map objects; valid orders,
    -- flags and timers remain in the same source order without adding retries.
    if Valid(h) and Valid(target) then command(h, target) end
end

function Start()
    -- LuaMission must enable the native AiMission's strategic AI at startup
    -- so the later SetAIP works. Never call SetAIControl from Update or Load.
    SetAIControl(2, true)
end

function AddObject(h)
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

function Update(dt)
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
        BuildObject("avfigh", 2, "spawn5")
    end
    if GetTime() > M.apc_wave then
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
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores game handles/audio and primitive table fields;
    -- never replay Setup, briefing, spawns or timers on load.
    M = state
end
