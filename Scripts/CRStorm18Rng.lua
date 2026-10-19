-- CRStorm18Rng: the storm's deterministic randomness, exact in Lua 5.1 doubles.
--
-- Park-Miller (x * 16807 mod 2^31-1) never leaves 2^46, well inside the 2^53
-- a double holds exactly, so every peer reproduces every sequence bit for bit.
--   Rng.New(seed)            stateful generator; :Float() in [0,1), :Range(a,b),
--                            :Int(n) in 1..n, plus .state for Save/Load
--   Rng.Hash(seed, a, b, c)  stateless uniform [0,1) from integers: the same
--                            inputs give the same number on every peer, which is
--                            how a leader event (seed, serial) becomes the same
--                            strike geometry everywhere without more packets
local Rng = {}
local M = 2147483647
local A = 16807

local function wrap(seed)
    seed = math.floor(tonumber(seed) or 1) % M
    if seed == 0 then seed = 1 end
    return seed
end

function Rng.New(seed)
    local r = { state = wrap(seed) }
    function r:Float()
        self.state = (self.state * A) % M
        return (self.state - 1) / (M - 1)
    end
    function r:Range(a, b) return a + (b - a) * self:Float() end
    function r:Int(n) return 1 + math.floor(self:Float() * n) end
    return r
end

-- Small multipliers keep every product under 2^53; three rounds of the
-- generator spread neighbouring inputs across the whole interval.
function Rng.Hash(seed, a, b, c)
    local h = ((math.floor(seed or 0) % M) * 48271 + (math.floor(a or 0) % M) * 69621
        + (math.floor(b or 0) % M) * 40692 + (math.floor(c or 0) % M) * 31337 + 12345) % M
    if h == 0 then h = 1 end
    h = (h * A) % M
    h = (h * A) % M
    h = (h * A) % M
    return (h - 1) / (M - 1)
end

return Rng
