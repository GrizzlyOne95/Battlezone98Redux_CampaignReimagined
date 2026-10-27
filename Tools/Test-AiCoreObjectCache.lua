-- The aiCore object cache is incremental: AddObject/DeleteObject feed it, and the world is only
-- fully scanned on Load.
local H = dofile("Tools/AiCoreTestHarness.lua")
local source = arg and arg[1] or "Scripts/aiCore.lua"
local aiCore = H.load(source)
local check, handle = H.check, H.handle

local function contains(list, h)
    for _, v in ipairs(list) do if v == h then return true end end
    return false
end

H.try("tracking", function()
    aiCore.ResetObjectCacheTracking()
    local tank = handle { team = 2, odf = "svtank", class = "wingman", craft = true }
    local tank2 = handle { team = 2, odf = "svfigh", class = "wingman", craft = true }
    local tower = handle { team = 2, odf = "sbtowe", class = "turret", building = true }
    local pilot = handle { team = 2, odf = "sspilo", class = "person", person = true }
    local scrap = handle { team = 0, odf = "npscr1", class = "scrap" }
    for _, h in ipairs({ tank, tank2, tower, pilot, scrap }) do aiCore.TrackWorldObject(h) end
    check("craft, buildings, persons and scrap land in their own lists",
        contains(aiCore.GetCachedTeamCraft(2), tank) and contains(aiCore.GetCachedBuildings(2), tower)
        and contains(aiCore.GetCachedPilotPersons(), pilot) and contains(aiCore.GetCachedScrapObjects(), scrap)
        and not contains(aiCore.GetCachedTeamCraft(2), tower))
    check("the most recently tracked craft comes first", aiCore.GetCachedTeamCraft(2)[1] == tank2)
    local targets = aiCore.GetCachedTeamTargets(2)
    check("team targets are the team's craft plus buildings", #targets == 3 and contains(targets, tower))
    aiCore.UntrackWorldObject(tank)
    check("untracking removes the handle from every list and from the target list",
        not contains(aiCore.GetCachedTeamCraft(2), tank) and not contains(aiCore.GetCachedTeamTargets(2), tank))
end)

H.try("revalidation", function()
    aiCore.ResetObjectCacheTracking()
    local a = handle { team = 2, odf = "svtank", class = "wingman", craft = true }
    local b = handle { team = 2, odf = "svfigh", class = "wingman", craft = true }
    aiCore.TrackWorldObject(a); aiCore.TrackWorldObject(b)
    local listBefore = aiCore.GetCachedTeamCraft(2)
    a.team = 5
    b.alive = false
    H.now = H.now + 2.0
    aiCore.RefreshObjectCache(false)
    check("a craft that changed team moves to the new team's list",
        contains(aiCore.GetCachedTeamCraft(5), a) and not contains(aiCore.GetCachedTeamCraft(2), a))
    check("a dead craft leaves the lists but is still tracked until DeleteObject",
        not contains(aiCore.GetCachedTeamCraft(2), b) and aiCore.ObjectCache.handleSet[b] == true)
    check("revalidation edits lists in place (no rebuild)", aiCore.GetCachedTeamCraft(2) == listBefore)
    b.valid = false
    H.now = H.now + 2.0
    aiCore.RefreshObjectCache(false)
    check("a handle the engine no longer knows is dropped", aiCore.ObjectCache.handleSet[b] == nil)
end)

H.try("no world scans", function()
    H.allObjectsCalls = 0
    aiCore.ResetObjectCacheTracking()
    local h = H.addObject { team = 2, odf = "svtank", class = "wingman", craft = true }
    aiCore.AddObject(h)
    for _ = 1, 20 do
        H.now = H.now + 1.0
        aiCore.RefreshObjectCache(false)
        aiCore.GetCachedTeamCraft(2)
        aiCore.GetCachedTeamTargets(2)
    end
    check("AddObject feeds the cache and refreshes never scan the world", H.allObjectsCalls == 0
        and contains(aiCore.GetCachedTeamCraft(2), h))
    aiCore.DeleteObject(h)
    check("DeleteObject removes the handle", not contains(aiCore.GetCachedTeamCraft(2), h))
    aiCore.Load({ teams = {}, producer = {} })
    -- Load() runs before the engine attaches AI processes, so it must not touch live objects.
    check("Load itself does not scan the world", H.allObjectsCalls == 0)
    aiCore.Update()
    check("the first Update after Load is the one place that rebuilds from the world", H.allObjectsCalls == 1)
    aiCore.Update()
    check("the post-load rebuild runs once", H.allObjectsCalls == 1)
    H.objects = {}
end)

-- The EXU callback multiplexer is registered once; modules that chain onto it later (CRReactive
-- style) must neither be overwritten nor recurse forever.
H.try("exu mux", function()
    local calls = 0
    aiCore.RegisterExuCallback("BulletInit", function() calls = calls + 1 end)
    local wrapper = exu.BulletInit
    check("registering installs the multiplexer on exu", type(wrapper) == "function")
    local previous = exu.BulletInit
    local chainedCalls = 0
    exu.BulletInit = function(...)
        chainedCalls = chainedCalls + 1
        return previous(...)
    end
    local chained = exu.BulletInit
    aiCore.RegisterExuCallback("BulletInit", function() end)   -- a later registration must not re-arm
    for _ = 1, 5 do
        H.now = H.now + 1.5
        aiCore.Update()
    end
    check("later modules' chain stays in place (no per-second re-arm)", exu.BulletInit == chained)
    local ok = pcall(exu.BulletInit, "odf", nil, nil, nil)
    check("the chained callback reaches our handler exactly once", ok and calls == 1 and chainedCalls == 1)
    -- Explicit re-arm adopts the chain as `external`; the re-entry guard stops the recursion.
    aiCore.EnsureExuCallbackMultiplexer()
    calls, chainedCalls = 0, 0
    local ok2 = pcall(exu.BulletInit, "odf", nil, nil, nil)
    check("re-adopting a chained callback does not recurse", ok2 and calls == 1)
end)

H.finish("aiCore object-cache")
