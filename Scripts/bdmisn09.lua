-- BlackDog09Mission: stock BZR / Lua 5.1 port.
-- Upstream blob: 0f93213b17334acf7c0a408a44cdaf3791e1e644.
-- Complete C++, including comments, unused members and native serialization:
-- References/BlackDog09Source/BlackDog09Mission.cpp.
-- Requires Redux 2.1+ ActivatePortal and IsTouching; no helper/shim required.

local NEVER = 999999.9
local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused in source
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false}, -- unused camera info
        trigger1 = false, oneOfTheEnemy = false, deviateSpawned = false,
        gotoBeacon2 = false, gotoBeacon3 = false,
        sound7Played = false, sound2Played = false,
        tankArrived1 = false, tankArrived2 = false, tankArrived3 = false,
        strayed = false, portalActive = false, lost = false, won = false,
        sound1Time = NEVER, sound2Time = NEVER, sound3Time = NEVER,
        sound6Time = NEVER, orderGotoTime1 = NEVER, deviateTime = NEVER,
        -- PORT FIX: Setup used NEVER, but the timer can only arm while < 0.
        -- Start disarmed so the existing ten-minute leave/return mechanic works
        -- even if the player never enters an ODF named cvtnkb before leaving.
        -- The source's ODF test, duration and failure delay remain unchanged.
        tankTimeout = -1,
        -- Native zero handles/messages are nil in Lua. Retained fields:
        -- user, lastUser, fakeUser, portal, cvtnk1..5, beacon1..3;
        -- winSound, sound1, sound2, sound3, sound5, sound7.
    }
end
local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Distance(a, b)
    -- PORT FIX: absent/deleted objects must not satisfy proximity checks.
    -- In particular beacon1/2/3 do not exist at mission startup. Infinity also
    -- treats destroyed convoy members as absent for the straying test.
    if not Valid(a) or (type(b) ~= "string" and not Valid(b)) then
        return math.huge
    end
    return GetDistance(a, b)
end
local function Odf(h, name)
    return Valid(h) and IsOdf(h, name)
end
local function Perceived(team)
    if Valid(M.user) then SetPerceivedTeam(M.user, team) end
end
local function AttackPlayer(h)
    -- Invalid/deleted units and failed builds cannot receive commands in Lua.
    if Valid(h) and Valid(M.user) then Attack(h, M.user) end
end
local function AnyTankNear(beacon)
    for i = 1, 5 do
        if Distance(beacon, M["cvtnk" .. i]) < 100 then return true end
    end
    return false
end

function Start()
    M = NewState()
    -- units (native Setup)
    M.portal = GetHandle("portal")
    for i = 1, 5 do M["cvtnk" .. i] = GetHandle("cvtnk" .. i) end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()

    if not M.startDone then
        SetScrap(1, 0)
        SetPilot(1, 0)
        -- don't do this part after the first shot
        M.startDone = true
        M.sound1Time = now + 1
        ClearObjectives()
        AddObjective("bd09001.otf", "white")
        if Valid(M.cvtnk1) then SetObjectiveOn(M.cvtnk1) end
    end

    -- SOE #1
    if M.sound1Time < now then
        M.sound1Time = NEVER
        M.sound1 = AudioMessage("bd09001.wav")
    end
    if M.sound1 ~= nil and IsAudioMessageDone(M.sound1) then
        M.sound1 = nil
        M.sound2Time = now + 15
    end

    -- SOE #2
    if M.sound2Time < now then
        M.sound2Time = NEVER
        if Odf(M.user, "cvapc") then
            M.sound2Played = true
            M.oneOfTheEnemy = true
            M.sound2 = AudioMessage("bd09002.wav")
        end
    end
    if not M.sound2Played and Valid(M.user) and not Odf(M.user, "cvapc") then
        M.oneOfTheEnemy = false
        Perceived(1)
        -- get the guys to attack
        for i = 2, 5 do AttackPlayer(M["cvtnk" .. i]) end
        -- PORT FIX: assigning now+1 every frame prevented SOE #10 from ever
        -- firing while exposed. Arm once; detection, units and one-second
        -- response delay are unchanged, and no repeat ambush is introduced.
        if M.deviateTime == NEVER and not M.deviateSpawned then
            M.deviateTime = now + 1
        end
    end
    if M.sound2 ~= nil and IsAudioMessageDone(M.sound2) then
        M.sound2 = nil
        -- C++ cut content: SetPerceivedTeam(user, 2);
        -- SetPerceivedTeam(M.user, 2)
    end
    if M.oneOfTheEnemy then Perceived(2) end

    -- SOE #3
    if M.objective1Complete and Valid(M.user) and not M.strayed then
        -- check distance to each of the other cvtnks
        if Distance(M.user, M.cvtnk2) > 75 and
           Distance(M.user, M.cvtnk3) > 75 and
           Distance(M.user, M.cvtnk4) > 75 and
           Distance(M.user, M.cvtnk5) > 75 then
            Perceived(1)
            M.strayed = true
            -- cut to SOE #10
            M.deviateTime = now + 2
        end
    end

    -- SOE #4
    if not M.objective1Complete and Valid(M.user) and
       M.user == M.cvtnk1 and M.sound2Played then
        M.oneOfTheEnemy = false
        M.objective1Complete = true
        SetObjectiveOff(M.cvtnk1)
        M.sound3Time = now + 5
        M.beacon1 = BuildObject("apcamr", 1, "spawn_beacon1")
    end
    if M.sound3Time < now and not M.deviateSpawned then
        M.sound3Time = NEVER
        M.sound3 = AudioMessage("bd09003.wav")
    end
    if M.sound3 ~= nil and IsAudioMessageDone(M.sound3) then
        M.sound3 = nil
        ClearObjectives()
        -- C++ cut content: AddObjective("bd09001.otf", GREEN);
        -- AddObjective("bd09001.otf", "green")
        AddObjective("bd09002.otf", "white")
        M.orderGotoTime1 = now + 1
    end

    -- SOE #5
    if M.orderGotoTime1 < now then
        M.orderGotoTime1 = NEVER
        for i = 2, 5 do
            local h = M["cvtnk" .. i]
            if Valid(h) and IsAlive(h) then Goto(h, "tank_path", 1) end
        end
    end

    -- SOE #6
    if not M.tankArrived1 and AnyTankNear(M.beacon1) then
        M.tankArrived1 = true
        -- spawn the next beacon
        M.beacon2 = BuildObject("apcamr", 1, "spawn_beacon2")
    end
    if M.objective1Complete and not M.gotoBeacon2 and not M.deviateSpawned then
        -- has the player arrived?
        if Distance(M.user, M.beacon1) < 100 then
            M.gotoBeacon2 = true
            AudioMessage("bd09004.wav")
        end
    end

    -- SOE #7
    if not M.tankArrived2 and AnyTankNear(M.beacon2) then
        M.tankArrived2 = true
        -- spawn the next beacon
        M.beacon3 = BuildObject("apcamr", 1, "spawn_beacon3")
    end
    if M.objective1Complete and not M.gotoBeacon3 and not M.deviateSpawned then
        -- has the player arrived?
        if Distance(M.user, M.beacon2) < 100 then
            M.gotoBeacon3 = true
            AudioMessage("bd09005.wav")
            M.sound6Time = now + 5
        end
    end

    -- #SOE #8
    if M.sound6Time < now then
        M.sound6Time = NEVER
        AudioMessage("bd09006.wav")
        if Valid(M.portal) then SetObjectiveOn(M.portal) end
    end
    if not M.objective2Complete then
        if M.gotoBeacon2 and M.gotoBeacon3 and Distance(M.user, M.beacon3) < 100 then
            M.objective2Complete = true
            ClearObjectives()
            AddObjective("bd09001.otf", "green")
            AddObjective("bd09002.otf", "green")
            AddObjective("bd09003.otf", "white")
        end
    end

    -- SOE #10
    if M.deviateTime < now and not M.deviateSpawned then
        Perceived(1)
        M.deviateTime = NEVER
        M.deviateSpawned = true
        local wave = {
            {"cvfigh", "spawn_deviate1"}, {"cvfigh", "spawn_deviate1"},
            {"cvltnk", "spawn_deviate2"}, {"cvltnk", "spawn_deviate2"},
            {"cvhtnk", "spawn_deviate3"},
            {"cvrckt", "spawn_deviate4"}, {"cvrckt", "spawn_deviate4"},
            {"cvfigh", "spawn_deviate5"}, {"cvfigh", "spawn_deviate5"},
            {"cvtnk", "spawn_deviate6"}, {"cvtnk", "spawn_deviate6"},
        }
        for _, unit in ipairs(wave) do AttackPlayer(BuildObject(unit[1], 2, unit[2])) end
        AudioMessage("bd09007.wav")
        -- Native GameObject::objectList traversal; AllObjects is stock Lua.
        for h in AllObjects() do
            if Odf(h, "cvturrc") then AttackPlayer(h) end
        end
    end

    if M.objective1Complete and Valid(M.user) and not Odf(M.user, "cvtnkb") and M.tankTimeout < 0 then
        M.tankTimeout = now + 10 * 60
    end
    if M.tankTimeout > 0 and Odf(M.user, "cvtnkb") then
        -- player is back into a cvtnk
        M.tankTimeout = -1
    end
    if M.tankTimeout > 0 and M.tankTimeout < now and not M.won and not M.lost then
        -- the player has been out of the tank for too long
        M.tankTimeout = -1
        -- PORT FIX: source omitted lost here, allowing portal touch/destruction
        -- to replace this failure during its one-second delay. Latch the same
        -- failure as other endings; timeout length and failure time stay intact.
        M.lost = true
        FailMission(now + 1, "bd09lose.des")
    end

    -- SOE #11
    if Distance(M.user, "trigger_1") < 200 and not M.trigger1 then
        M.trigger1 = true
        for i = 0, 4 do AttackPlayer(BuildObject("cvtnk", 2, "last_one")) end
    end

    -- SOE #12
    if Distance(M.user, M.portal) < 250 and not M.portalActive then
        M.portalActive = true
        -- Native activatePortal(portal, true) maps to the stock Lua API.
        ActivatePortal(M.portal)
        M.winSound = AudioMessage("bd09008.wav")
    end
    -- Native isTouching maps to stock Redux IsTouching (case is significant).
    -- Keep immediate victory: no objective-completion/audio gate is added.
    if Valid(M.user) and Valid(M.portal) and IsTouching(M.user, M.portal) and not M.won and not M.lost then
        M.won = true
        SucceedMission(now, "bd09win.des")
    end
    -- lost the portal? Native GetHealth also fails for a destroyed portal.
    if (not Valid(M.portal) or GetHealth(M.portal) <= 0) and not M.lost and not M.won then
        M.lost = true
        FailMission(now + 1, "bd09lseb.des")
    end
end

function Save()
    return M
end
function Load(state)
    -- LuaMission restores table/handle/message values; do not replay Setup.
    M = state
end
