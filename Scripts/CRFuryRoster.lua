-- Saved deterministic composition for the faithful offline Mission 17/18 ports.
-- Existing waves, trigger order, destinations and total craft counts are retained.
local R = {}
function R.Select(odf, state)
    if odf ~= "hvsav" and odf ~= "hvsat" then return odf end
    state.crFuryIndex = (state.crFuryIndex or 0) + 1
    if state.crFuryIndex % 3 ~= 0 then return "crfraz" end
    return odf
end
return R
