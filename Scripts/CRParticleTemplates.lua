-- CR particle definitions are payloads, not automatically parsed Ogre scripts.
-- Load them only when a playable CR mission needs them. Setup does not require
-- this module, so a fresh stock installation can run the Workshop installer.
local exu = require("exu")
local bzfile = nil
local Templates = {}
local loaded = {}
local names = {"cr_reactive", "cr_weather", "weather_particles"}

local function ReadPayload(path)
    local file = bzfile.Open(path, "r")
    if not file then error("particle payload unavailable: " .. path) end
    local chunks = {}
    local ok, result = pcall(function()
        while true do
            local chunk = file:Read(65536)
            if not chunk or chunk == "" then break end
            chunks[#chunks + 1] = chunk
        end
        return table.concat(chunks)
    end)
    file:Close()
    if not ok then error(result) end
    return result
end

-- Ogre keeps templates across menu resource rebuilds and mission Lua states,
-- while `loaded` resets with each state. Reparsing would throw on duplicates.
local function AlreadyRegistered(text, filename)
    if type(exu.HasParticleTemplate) ~= "function" then return false end
    local total, present = 0, 0
    for templateName in text:gmatch("particle_system%s+([^%s{]+)") do
        total = total + 1
        if exu.HasParticleTemplate(templateName) then present = present + 1 end
    end
    if present > 0 and present < total then
        print(("CR particle payload %s partially registered (%d/%d); not reparsing."):format(filename, present, total))
    end
    return present > 0
end

function Templates.Ensure()
    if type(exu.ParseResourceScript) ~= "function" then
        print("CR particle templates require the bundled EXU runtime; run Setup / Repair.")
        return false
    end
    bzfile = require("bzfile")
    local RequireFix = require("RequireFix")
    local root = RequireFix.getActiveModRoot()
    if not root then
        -- Native bzfile is loaded from this same CR item after RequireFix has
        -- resolved it, including the engine's source-less mission chunks.
        local search = package.cpath or ""
        for entry in search:gmatch("[^;]+") do
            local candidate = entry:match("^(.*)[/\\]%?%.dll$")
            if candidate then
                local ok = pcall(ReadPayload, candidate .. "/cr_reactive.particle.payload")
                if ok then root = candidate; break end
            end
        end
    end
    if not root then print("CR particle payload root could not be resolved."); return false end
    for _, name in ipairs(names) do
        if not loaded[name] then
            local filename = name .. ".particle.payload"
            local ok, text = pcall(ReadPayload, root .. "/" .. filename)
            if not ok then print(tostring(text)); return false end
            local parsed, completed = true, true
            if not AlreadyRegistered(text, filename) then
                parsed, completed = pcall(exu.ParseResourceScript, text, filename, "Modable")
            end
            if not parsed or not completed then
                print("CR particle payload could not be parsed: " .. filename)
                return false
            end
            loaded[name] = true
        end
    end
    return true
end

return Templates
