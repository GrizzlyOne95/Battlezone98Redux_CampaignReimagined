-- Run from repository root: lua5.1 Tests/requirefix_gamedir_spec.lua
-- RequireFix game-directory detection across install layouts, fed Redux's
-- stock Lua 5.1 search paths (built from the executable directory).
local file = arg[1] or "Scripts/RequireFix.lua"
local BS = string.char(92)
local cases = {
  { "C:" .. BS .. "BZRCoop" .. BS .. "instances" .. BS .. "Instance0", "non-standard folder (test instance)" },
  { "C:" .. BS .. "Program Files (x86)" .. BS .. "GOG Galaxy" .. BS .. "Games" .. BS .. "Battlezone 98 Redux", "GOG default" },
  { "D:" .. BS .. "SteamLibrary" .. BS .. "steamapps" .. BS .. "common" .. BS .. "Battlezone 98 Redux", "Steam library" },
  { "D:" .. BS .. "Games" .. BS .. "BZR", "renamed install" },
}
local fails = 0
for _, c in ipairs(cases) do
  local g = c[1]
  package.path = "." .. BS .. "?.lua;" .. g .. BS .. "lua" .. BS .. "?.lua;" .. g .. BS .. "lua" .. BS .. "?" .. BS .. "init.lua;"
    .. g .. BS .. "?.lua;" .. g .. BS .. "?" .. BS .. "init.lua"
  package.cpath = "." .. BS .. "?.dll;" .. g .. BS .. "?.dll;" .. g .. BS .. "loadall.dll"
  local RF = dofile(file)
  local got = RF.getGameDirectory()
  local ok = got == g
  if not ok then fails = fails + 1 end
  print((ok and "PASS " or "FAIL ") .. c[2] .. ": " .. tostring(got))
end
os.exit(fails == 0 and 0 or 1)
