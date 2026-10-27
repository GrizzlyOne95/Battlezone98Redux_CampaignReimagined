-- misn06-14 must initialize PersistentConfig, or X never opens the PDA and
-- ScriptSubtitles/AutoSave fall back to defaults. Checks each mission's
-- "CR PDA" block, its Start/Update/AddObject call sites, and that mission
-- results reach PersistentConfig's SucceedMission/FailMission cleanup hooks.
local checks, failed = 0, 0
local function check(ok, message)
    checks = checks + 1
    if not ok then
        failed = failed + 1
        print("FAIL: " .. message)
    end
end

local function readSource(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

-- Top-level function bodies end at the first column-0 "end".
local function body(source, header)
    local first = source:find("\nfunction " .. header, 1, true)
    if not first then return nil end
    local last = source:find("\nend", first + 1, true)
    return last and source:sub(first, last) or nil
end

local function runBlock(block, mission)
    local calls = {Initialize = 0, UpdateInputs = 0, UpdateHeadlights = 0, objects = {}}
    local config = {
        Initialize = function() calls.Initialize = calls.Initialize + 1 end,
        UpdateInputs = function(cinematic)
            calls.UpdateInputs = calls.UpdateInputs + 1
            calls.cinematic = cinematic
        end,
        UpdateHeadlights = function() calls.UpdateHeadlights = calls.UpdateHeadlights + 1 end,
        OnObjectCreated = function(h) calls.objects[#calls.objects + 1] = h end,
    }
    local chunk = assert(loadstring(block .. "\nreturn missionPda", mission .. " PDA block"))
    setfenv(chunk, {require = function(name)
        assert(name == "PersistentConfig", name)
        return config
    end})
    return chunk(), calls
end

for index = 6, 14 do
    local mission = string.format("misn%02d", index)
    local source = readSource("Scripts/" .. mission .. ".lua")
    -- Compiles the whole chunk, so the 200-local and 60-upvalue limits apply.
    local compiled, compileError = loadstring(source, mission)
    check(compiled ~= nil, mission .. " compiles under Lua 5.1: " .. tostring(compileError))

    local block = source:match("\n(%-%- CR PDA >>.-%-%- CR PDA <<)\n")
    check(block ~= nil, mission .. " has the CR PDA block")
    check(block and block:find('require("PersistentConfig")', 1, true),
        mission .. " requires PersistentConfig")

    local start, update, addObject = body(source, "Start()"), body(source, "Update("), body(source, "AddObject(h)")
    -- Call sites outside an existing CR region carry their own "CR PDA" markers.
    local function call(text) return ((text or ""):gsub("\n%-%- CR PDA [<>][<>]", "")) end
    start, update, addObject = call(start), call(update), call(addObject)
    check(start:find("    subtit.Initialize()\n    missionPda.Init()\n", 1, true),
        mission .. " Start initializes PersistentConfig after subtitles")
    -- Before any coopResult/leader-departed early return, so the PDA works on every peer.
    local updateCall = update and update:find("missionPda.Update(", 1, true)
    local firstReturn = update and update:find("return", 1, true)
    check(updateCall and (not firstReturn or updateCall < firstReturn),
        mission .. " Update drives PersistentConfig before any early return")
    local cinematic = source:find("local cameraSkipped, localCameraActive", 1, true)
    check(update and update:find(cinematic and "missionPda.Update(localCameraActive)" or "missionPda.Update()", 1, true),
        mission .. " passes its cinematic camera state to UpdateInputs")
    check(addObject:find("^\nfunction AddObject%(h%)\n    missionPda%.Object%(h%)\n"),
        mission .. " AddObject forwards new objects to PersistentConfig first")

    check(source:find("SucceedMission = function(...) return _G.SucceedMission(...) end,", 1, true)
        and source:find("FailMission = function(...) return _G.FailMission(...) end,", 1, true),
        mission .. " native results resolve PersistentConfig's hooks at call time")
    check(not source:find("=%s*SucceedMission%s*[,\n]") and not source:find("=%s*FailMission%s*[,\n]"),
        mission .. " captures no load-time SucceedMission/FailMission")

    if block then
        -- Fresh mission: Start initializes once, Update only ticks.
        local pda, calls = runBlock(block, mission)
        pda.Object(101)
        check(#calls.objects == 0, mission .. " ignores objects before Initialize")
        pda.Init()
        pda.Update(true)
        pda.Update(false)
        check(calls.Initialize == 1 and calls.UpdateInputs == 2 and calls.UpdateHeadlights == 2
            and calls.cinematic == false, mission .. " Start path initializes once and ticks inputs")
        pda.Object(nil)
        pda.Object(102)
        check(#calls.objects == 1 and calls.objects[1] == 102, mission .. " forwards valid objects after Initialize")

        -- Loaded save: locals reset and Start is not rerun, so Update initializes.
        pda, calls = runBlock(block, mission)
        pda.Update()
        pda.Update()
        check(calls.Initialize == 1 and calls.UpdateInputs == 2, mission .. " load path initializes once from Update")
    end
end

if failed > 0 then
    error(string.format("mission PDA wiring: %d of %d checks failed", failed, checks))
end
print(string.format("mission PDA wiring: %d checks passed (misn06-14)", checks))
