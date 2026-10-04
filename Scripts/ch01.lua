-- Chinese01Mission.cpp -> stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Chinese01Mission.cpp
-- Source blob: 210bb8193c11836ffb299bb15bf89afd945e48c5.
-- Complete original source (including every comment, #if block, declaration,
-- and native Load/Save/PostLoad scaffold):
-- References/Chinese01Source/Chinese01Mission.cpp.
-- No Campaign Reimagined helpers, EXU, or OpenShim required.
-- Keep zero-based arrays and native strict timer/distance comparisons.

local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, objective4Complete = false,
        objective5Complete = false, -- unused in active source
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false}, -- unused native arrays
        hangarIdentified = false, recyclerDeployed = false,
        tugNearNav = false, arialsSpawned = false,
        focusOnExplosion = false, doingExplosion = false, doNuke = false,
        sound12Played = false, decoySpawned = false, won = false, lost = false,
        detectors = {},
        -- Native null handles and audio IDs are nil (Lua zero is truthy).
        -- All eleven native timers are assigned by Setup in Start below;
        -- unused wave5Time/explodeTime and tugDiedSound remain retained.
    }
end
local M = NewState()
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Alive(h) return Valid(h) and IsAlive(h) end
local function Health(h)
    -- PORT FIX: deleted objects cannot be queried safely. Treat them as dead,
    -- matching the native <=0 destruction gates. Unspawned slots are gated
    -- separately; intact units retain the native fractional-health tests.
    if not Valid(h) then return 0 end
    return GetHealth(h)
end
local function Distance(h, target, point)
    -- PORT FIX: nil/deleted handles must not satisfy proximity/safety tests
    -- or select the wrong Lua overload. Existing objects/paths are unchanged.
    if not Valid(h) or (type(target) ~= "string" and not Valid(target)) then
        return math.huge
    end
    if point ~= nil then return GetDistance(h, target, point) end
    return GetDistance(h, target)
end
local function Following(h, target)
    return Valid(h) and Valid(target) and IsFollowing(h, target)
end
local function HangarInfo()
    -- API ADAPTATION: native IsInfo takes a handle; stock Lua takes an ODF.
    -- Resolve the actual mapped hangar's ODF rather than assuming its class.
    return Valid(M.hangar) and IsInfo(GetOdf(M.hangar))
end
local function Airborne(odf, team, path, height)
    -- API ADAPTATION: native fourth argument is spawn height, while Lua's
    -- fourth path argument is a POINT INDEX. Use point 0's position plus the
    -- native 200/100-metre vertical offset; preserve unit and spawn order.
    local p = GetPosition(path, 0)
    p.y = p.y + height
    return BuildObject(odf, team, p)
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end
function Save() return M end
function Load(state)
    -- LuaMission serializes/remaps handles in tables. Do not rerun Setup or
    -- restart timers/messages after loading; native ConvertHandle is implicit.
    if state ~= nil then M = state end
end

function Start()
    M = NewState()
    local i = 0
    M.startDone = false
    M.objective1Complete = false
    M.objective2Complete = false
    M.objective3Complete = false
    M.objective4Complete = false
    M.objective5Complete = false
    M.hangarIdentified = false
    M.recyclerDeployed = false
    M.tugNearNav = false
    M.arialsSpawned = false
    M.focusOnExplosion = false
    M.doingExplosion = false
    M.doNuke = false
    M.sound12Played = false
    M.decoySpawned = false

    -- cameras
    for i = 0, 1 do
        M.cameraReady[i] = false
        M.cameraComplete[i] = false
    end

    -- units
    M.hangar = GetHandle("target_1")
    M.commTower= GetHandle("target_2")
    M.bbTower = GetHandle("bb_tower")
    M.recycler = nil
    M.tug = nil
    M.relic = nil
    M.escort1 = nil
    M.escort2 = nil
    M.detectors[0] = GetHandle("sp_turret_1")
    M.detectors[1] = GetHandle("sp_turret_2")
    M.detectors[2] = GetHandle("sp_turret_3")
    M.detectors[3] = GetHandle("sp_tower_1")
    M.detectors[4] = GetHandle("sp_tower_2")
    M.detectors[5] = GetHandle("sp_tower_3")
    M.detectors[6] = GetHandle("sp_tower_4")
    M.detectors[7] = GetHandle("sp_tower_5")
    M.detectors[8] = GetHandle("sp_tower_6")
    M.detectors[9] = GetHandle("sp_tower_7")

    -- navs
    M.navStart = nil
    M.navTug = nil
    M.navEnd = nil

    -- sounds
    M.openingSound = nil
    M.hangarSound = nil
    M.armourySound = nil
    M.tugDiedSound = nil
    M.failedSound = nil
    M.detectedSound = nil

    -- times
    M.openingSoundTime = 999999.9
    M.armourySoundTime = 999999.9
    M.wave1Time = 999999.9
    M.wave2Time = 999999.9
    M.wave3Time = 999999.9
    M.wave4Time = 999999.9
    M.wave5Time = 999999.9
    M.arial1Time = 999999.9
    M.arial2Time = 999999.9
    M.tugTime = 999999.9
    M.explodeTime = 999999.9
end

function Update(dt)
    local i = 0
    M.user = GetPlayerHandle(); --assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1,0)
        SetPilot(1,10)

        -- don't do this part after the first shot
        M.startDone = true

        M.openingSoundTime = GetTime() + 5.0

        -- disable all cloaking for this mission
        EnableAllCloaking(false)
        --[=[ Original disabled startup/debug block (#if 0):
        		relic = BuildObject("obdata", 0, "relic_loc");
        		SetObjectiveOn(relic);
        		tug = BuildObject("svhaula", 2, user);
        		//nuke = BuildObject("obdata", 0, tug);
        		//setCargo(tug, nuke);
        		//tugEquipedWithNuke = TRUE;
        		SetObjectiveOn(tug);
        		SetPerceivedTeam(user, 2);
        		objective3Complete = TRUE;
        		SetObjectiveOn(hangar);
        ]=]
    end
    -- #if 1 (active native code)
    if M.openingSoundTime < GetTime() then
        M.openingSoundTime = 999999.9

        M.openingSound = AudioMessage("ch01001.wav")
    end

    if M.openingSound ~= nil and IsAudioMessageDone(M.openingSound) then
        M.openingSound = nil

        -- spawn the nav camera
        M.navStart = BuildObject("apcamr", 1, "nav_start")
        SetName(M.navStart, "CCA Base")

        ClearObjectives()
        AddObjective("ch01001.otf", "white")
    end

    if not M.hangarIdentified and HangarInfo() then
        M.hangarIdentified = true

        -- play the message
        M.hangarSound = AudioMessage("ch01002.wav")

        -- update objectives
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        M.objective1Complete = true
    end

    if M.hangarSound ~= nil and IsAudioMessageDone(M.hangarSound) then
        M.hangarSound = nil

        M.armourySoundTime = GetTime() + 15.0
    end

    if M.armourySoundTime < GetTime() then
        M.armourySoundTime = 999999.9

        M.armourySound = AudioMessage("ch01003.wav")
    end

    if M.armourySound ~= nil and IsAudioMessageDone(M.armourySound) then
        M.armourySound = nil

        -- spawn the armoury
        BuildObject("cvslfb", 1, "armoury")
        AudioMessage("ch01004.wav")

        -- update objectives
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        AddObjective("ch01002.otf", "white")

        AddScrap(1, 99)
    end

    if not M.objective2Complete and Health(M.commTower) <= 0.0 then
        M.objective2Complete = true

        AudioMessage("ch01005.wav")

        M.recycler = BuildObject("cvrecyd", 1, "M.recycler")
        AddScrap(1, 50)

        -- update objectives
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        AddObjective("ch01002.otf", "green")
    end

    if Valid(M.recycler) and not M.recyclerDeployed and IsDeployed(M.recycler) then
        M.recyclerDeployed = true

        M.wave1Time = GetTime() + 60.0
    end

    if M.wave1Time < GetTime() then
        M.wave1Time = 999999.9

        -- spawn the first wave
        local h
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)

        -- time to next wave
        M.wave2Time = GetTime() + 300.0
    end

    if M.wave2Time < GetTime() then
        M.wave2Time = 999999.9

        -- spawn the second wave
        local h
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svltnk", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svltnk", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svltnk", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svfigh", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svfigh", 2, "wave_2")
        Goto(h, "follow_2", 1)

        -- time to next wave
        M.wave3Time = GetTime() + 300.0
    end

    if M.wave3Time < GetTime() then
        M.wave3Time = 999999.9

        -- spawn the second wave
        local h
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svhraz", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svhraz", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svhraz", 2, "wave_3")
        Goto(h, "follow_3", 1)

        -- next attack
        M.arial1Time = GetTime() + 180.0
    end

    if M.arial1Time < GetTime() then
        M.arial1Time = 999999.9

        -- spawn the arial units
        local h
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)

        -- next attack
        M.arial2Time = GetTime() + 30.0
    end

    if M.arial2Time < GetTime() then
        M.arial2Time = 999999.9

        -- spawn the arial units
        local h
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)

        -- next attack
        M.wave4Time = GetTime() + 60.0
    end

    if M.wave4Time < GetTime() then
        M.wave4Time = 999999.9

        -- spawn the wave
        local h
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)

        -- tug time
        M.tugTime = GetTime() + 120.0
    end

    if M.tugTime < GetTime() then
        M.tugTime = 999999.9

        M.tug = BuildObject("svhaula", 2, "relic_tug")
        Goto(M.tug, "tug_path", 1)

        local h
        h = BuildObject("svfigh", 2, "tug_defend")
        Defend2(h, M.tug, 1)
        h = BuildObject("svfigh", 2, "tug_defend")
        Defend2(h, M.tug, 1)
    end

    if Valid(M.tug) and not M.tugNearNav and Distance(M.tug, "nav_tug", 0) < 1000.0 then
        M.tugNearNav = true

        AudioMessage("ch01006.wav")

        M.navTug = BuildObject("apcamr", 1, "nav_tug")

        -- update objectives
        ClearObjectives()
        AddObjective("ch01002.otf", "green")
        AddObjective("ch01003.otf", "white")
    end

    -- has the tug been killed?
    if M.tug ~= nil and Health(M.tug) <= 0.0 and not M.lost and not M.won then
        M.lost = true

        M.failedSound = AudioMessage("ch01011.wav")
    end

    if M.failedSound ~= nil and IsAudioMessageDone(M.failedSound) then
        M.failedSound = nil

        FailMission(GetTime() + 1.0, "ch01lseb.des")
    end

    -- has the tug gotten away from us?
    if Valid(M.tug) and Distance(M.tug, "tug_fail") < 350.0 and GetTeamNum(M.tug) == 2 and not M.lost and not M.won then
        FailMission(GetTime() + 1.0, "ch01lsea.des")
        M.lost = true
    end

    -- is the tug within 75 metres of the recycler?
    if Valid(M.tug) and Distance(M.tug, M.recycler) < 75.0 and not M.objective3Complete then
        -- message
        AudioMessage("ch01007.wav")

        -- attack
        M.escort1 = BuildObject("svfigh", 1, "fighters")
        SetPerceivedTeam(M.escort1, 2)
        SetIndependence(M.escort1, 0)
        SetPerceivedTeam(M.escort1, 2)
        Goto(M.escort1, "fighters_to", 1)
        M.escort2 = BuildObject("svfigh", 1, "fighters")
        SetPerceivedTeam(M.escort2, 2)
        SetIndependence(M.escort2, 0)
        SetPerceivedTeam(M.escort2, 2)
        Goto(M.escort2, "fighters_to", 1)

        -- update objectives
        M.objective3Complete = true
        ClearObjectives()
        AddObjective("ch01003.otf", "green")
        AddObjective("ch01004.otf", "white")

        -- spawn the relic
        M.relic = BuildObject("obdata", 0, "relic_loc")

        -- units
        local h
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5")
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5")
    end

    if M.objective3Complete and not M.objective4Complete and not M.lost and not M.won then
        local withinRange = false
        for i = 0, 9 do
            if Alive(M.detectors[i]) and Distance(M.user, M.detectors[i]) < 150.0 then
                withinRange = true
                break
            end
        end

        if not M.arialsSpawned and withinRange then
            -- spawn the arial units
            local h
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            M.arialsSpawned = true
        end


        -- are we currently being escorted?
        if Following(M.escort1, M.user) and Following(M.escort2, M.user) then
            -- we're being escorted, we're safe
        elseif withinRange then
            -- our cover is blown
            M.lost = true
            M.detectedSound = AudioMessage("ch01008.wav")
            -- Native assertion: _ASSERTE(!objective4Complete);
        end
    end

    if M.objective3Complete and not M.objective4Complete then
        -- are we currently being escorted?
        if Following(M.escort1, M.user) and Following(M.escort2, M.user) then
            -- we're being escorted, we're safe
            SetPerceivedTeam(M.user, 2)
        else
            SetPerceivedTeam(M.user, 1)
        end
    end

    -- we've been detected
    if M.detectedSound ~= nil and IsAudioMessageDone(M.detectedSound) then
        M.detectedSound = nil
        --failedSound = AudioMessage("ch01011.wav");
        FailMission(GetTime(), "ch01lsec.des")
    end
    -- #endif (active native code)
    -- if we get the relic
    if M.objective3Complete and not M.objective4Complete and Valid(M.relic) and Valid(M.tug) and GetCargo(M.tug) == M.relic then
        --_DEBUGMSG0("Relic picked up by Tug");
        M.objective4Complete = true

        -- reset objectives
        ClearObjectives()
        AddObjective("ch01004.otf", "green")
        AddObjective("ch01005.otf", "white")

        M.navEnd = BuildObject("apcamr", 1, "nav_end")
        -- Native assertion: _ASSERTE(navEnd != NULL);
        SetName(M.navEnd, "Safe Distance")
        SetObjectiveOn(M.navEnd)

        StartCockpitTimer(180, 15, 5)
        M.explodeTime = GetTime() + 30.0
    end

    if M.objective4Complete and not M.decoySpawned then
        -- are we close enough to the turrets?
        local withinRange = false
        for i = 0, 9 do
            if Alive(M.detectors[i]) and Distance(M.user, M.detectors[i]) < 300.0 then
                withinRange = true
                break
            end
        end

        if withinRange then
            M.decoySpawned = true

            -- decoy sound
            AudioMessage("ch01009.wav")

            for i = 0, 6 do
                local h = BuildObject("cvhtnk", 1, "decoy_units")
                Goto(h, M.detectors[math.random(0, 9)], 1)
            end
        end
    end

    if M.objective4Complete and not M.doingExplosion then
        if GetCockpitTimer() <= 0 then
            M.explodeTime = 999999.9
            HideCockpitTimer()

            -- make the thing explode
            M.doNuke = true
            M.doingExplosion = true
            ColorFade(1.0, 0.5, 255, 255, 255)
        elseif GetCockpitTimer() <= 2.0  and not M.focusOnExplosion and M.cameraFinishTime == nil then
            -- pre-explosion
            local nukeDistance = Distance(M.navEnd, M.hangar) - 50
            if Valid(M.bbTower) and Distance(M.user, M.hangar) > nukeDistance and not M.focusOnExplosion and M.cameraFinishTime == nil then
                CameraReady()
                M.cameraFinishTime = GetTime() + 5.0
                CameraPath("cut_end", 3000, 0, M.bbTower)
                M.focusOnExplosion = true
            end
        end
    end

    if M.doNuke then
        M.doNuke = false
        if M.focusOnExplosion then M.cameraFinishTime = GetTime() + 3.0 end

        -- where's the relic?
        local nukeDistance = Distance(M.navEnd, M.hangar) - 50.0
        -- PORT FIX: a previously detected/killed/escaped tug must not turn
        -- an already-lost mission into a win at countdown expiry. Preserve
        -- the three-second result and distance test on nonterminal runs.
        -- Destroyed relic/nav/hangar cannot count as safely evacuated.
        if not M.lost and not M.won then
            if Valid(M.relic) and Valid(M.navEnd) and Valid(M.hangar) and
                Distance(M.relic, M.hangar) > nukeDistance then
                SucceedMission(GetTime() + 3.0, "ch01win.des")
                M.won = true
            else
                FailMission(GetTime() + 3.0, "ch01lsee.des")
                M.lost = true
            end
        end
        -- API ADAPTATION: native MakeExplosion(location, effect) is reversed
        -- in Lua. Redux uses the D3D effect; legacy renderer flag useD3D is
        -- unavailable. Original fallback xpltrsq is preserved in the archive.
        MakeExplosion("xpltrsn", "spawn_explosion1")
    end

    -- PORT FIX: native CameraPath is called only once and CameraFinish never
    -- runs. Pump the same stationary shot until result transition (3 seconds
    -- after detonation) or cancellation, then return camera control. This
    -- changes only camera cleanup, not countdown or mission-result gates.
    if M.focusOnExplosion then
        if CameraCancelled() or GetTime() >= M.cameraFinishTime or not Valid(M.bbTower) then
            CameraFinish()
            M.focusOnExplosion = false
        else
            CameraPath("cut_end", 3000, 0, M.bbTower)
        end
    end

    -- has the recycler been lost?
    if M.recycler ~= nil and Health(M.recycler) <= 0.0 and not M.objective3Complete and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime() + 1.0, "ch01lsed.des")
    end
end
