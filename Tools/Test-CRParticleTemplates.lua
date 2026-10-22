-- lua Tools/Test-CRParticleTemplates.lua Scripts
local dir = ... or "Scripts"
package.path = dir .. "/?.lua;" .. package.path
local calls, closed, fail = {}, 0, nil
local fakeExu = {
    ParseResourceScript = function(text, source, group)
        assert(text == "particle_system " .. source)
        assert(group == "Modable")
        calls[#calls + 1] = source
        return source ~= fail
    end,
}
package.loaded.exu = fakeExu
package.loaded.RequireFix = {getActiveModRoot = function() return "workshop/item" end}
package.loaded.bzfile = {Open = function(path, mode)
    assert(mode == "r")
    assert(path:match("^workshop/item/"))
    local name = path:match("[^/]+$")
    local done = false
    return {
        Read = function()
            if done then return nil end
            done = true
            return "particle_system " .. name
        end,
        Close = function() closed = closed + 1 end,
    }
end}
local templates = require("CRParticleTemplates")
assert(#calls == 0, "requiring the module must not parse templates")
fail = "cr_weather.particle.payload"
assert(templates.Ensure() == false)
assert(calls[1] == "CR_reactive.material", "particle materials must parse before any template")
assert(#calls == 3 and closed == 3)
fail = nil
assert(templates.Ensure() == true)
assert(#calls == 6 and closed == 6, "retry must preserve completed payloads and materials")
assert(templates.Ensure() == true and #calls == 6, "no duplicate declarations in a Lua state")
-- A new mission Lua state must not reparse templates Ogre still holds.
local ogre = {}
for _, source in ipairs(calls) do ogre[source] = true end
fakeExu.HasParticleTemplate = function(name) return ogre[name] == true end
fakeExu.MaterialExists = function(name, group)
    assert(name == "CR_FX/Rain" and group == "Modable")
    return ogre["CR_reactive.material"] == true
end
package.loaded.CRParticleTemplates = nil
local fresh = require("CRParticleTemplates")
assert(fresh.Ensure() == true and #calls == 6, "templates and materials surviving in Ogre must not be reparsed")
-- A material parse failure warns but leaves the templates usable.
ogre = {}
fail = "CR_reactive.material"
package.loaded.CRParticleTemplates = nil
assert(require("CRParticleTemplates").Ensure() == true, "material failure must not fail Ensure")
assert(#calls == 11 and calls[7] == "CR_reactive.material", "materials and all payloads attempted")
fail = nil
fakeExu.MaterialExists = nil
fakeExu.HasParticleTemplate = nil
fakeExu.ParseResourceScript = nil
package.loaded.bzfile = nil
assert(templates.Ensure() == false, "unavailable runtime must fail without file loading")
print("CR PARTICLE TEMPLATES OK")
