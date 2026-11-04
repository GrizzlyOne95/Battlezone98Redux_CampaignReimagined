-- Native "Hold" command for player-team craft whose ODF sets
-- [CraftClass] holdOrder = 1 (single-player only).
-- Replaces the stock Hunt button: Defend(unit, 0) stands still, then EXU marks
-- the unit held so it shoots the closest enemy and never chases.
-- Event-driven: no per-frame work. Every EXU call is guarded and degrades silently.
local H = {}
local ok, exu = pcall(require, "exu")
if not ok then exu = {} end

local STOCK_CMD, LABEL = "Hunt", "Hold"

local function singlePlayer()
    return not (type(IsNetGame) == "function" and IsNetGame())
end

local function hasApi(name)
    return type(exu) == "table" and type(exu[name]) == "function"
end

-- Same lookup as aiCore's cloakAllowed check: OpenODF the craft's cleaned ODF name.
local function wantsHold(h)
    if type(GetOdf) ~= "function" or type(OpenODF) ~= "function" or type(GetODFBool) ~= "function" then
        return false
    end
    local name = GetOdf(h)
    if not name then return false end
    name = string.lower((tostring(name):gsub("%z.*$", "")))
    local ok2, odf = pcall(OpenODF, name)
    if not ok2 or not odf then return false end
    local ok3, v = pcall(GetODFBool, odf, "CraftClass", "holdOrder", false)
    return ok3 and v == true
end

local function playerTeam()
    local p = type(GetPlayerHandle) == "function" and GetPlayerHandle() or nil
    if p and (type(IsValid) ~= "function" or IsValid(p)) then return GetTeamNum(p) end
    return 1
end

-- Return true: handled, stock Hunt is suppressed (EXU resets the command to None).
local function holdCallback(unit)
    if type(IsValid) == "function" and not IsValid(unit) then return true end
    pcall(Defend, unit, 0)
    if hasApi("SetAiHold") then pcall(exu.SetAiHold, unit, true) end
    return true
end

local function register(h)
    if not hasApi("ReplaceStockCmd") then return end
    if type(IsValid) == "function" and not IsValid(h) then return end
    if GetTeamNum(h) ~= playerTeam() or not wantsHold(h) then return end
    pcall(exu.ReplaceStockCmd, h, STOCK_CMD, LABEL, holdCallback)
end

function H.Setup()
    if not singlePlayer() then return end
    if hasApi("SetFollowEngageEnabled") then pcall(exu.SetFollowEngageEnabled, true) end
    if hasApi("SetDefendRefreshEnabled") then pcall(exu.SetDefendRefreshEnabled, true) end
end

function H.OnAddObject(h)
    if not singlePlayer() or not h then return end
    register(h)
end

-- EXU resets the replacement registry when the Lua state is rebuilt, so a save
-- reload must register again for hold-capable craft that already exist.
function H.Load()
    if not singlePlayer() then return end
    H.Setup()
    if type(AllCraft) ~= "function" then return end
    for h in AllCraft() do
        register(h)
        -- OpenShim's hold table is not saved: re-arm craft still on Defend(h, 0).
        if hasApi("SetAiHold") and wantsHold(h) and GetTeamNum(h) == playerTeam()
            and type(GetCurrentCommand) == "function" and type(AiCommand) == "table"
            and GetCurrentCommand(h) == AiCommand.DEFEND
            and not (type(GetCurrentWho) == "function" and GetCurrentWho(h) and IsValid(GetCurrentWho(h))) then
            pcall(exu.SetAiHold, h, true)
        end
    end
end

return H
