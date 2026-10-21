-- CR art tuning: scalar light balance preserves each map's authored palette.
-- Keep atmosphere ownership in Environment (or CRWeather's standalone path).
local Art = {}
Art.Worlds = {
    moon     = {ambient=1.10, diffuse=1.02, specular=0.90},
    mars     = {ambient=1.04, diffuse=0.98, specular=0.90},
    venus    = {ambient=1.06, diffuse=0.94, specular=0.85},
    io       = {ambient=1.02, diffuse=1.00, specular=0.90},
    europa   = {ambient=1.04, diffuse=0.96, specular=0.94},
    titan    = {ambient=1.08, diffuse=0.92, specular=0.88},
    ganymede = {ambient=1.06, diffuse=0.98, specular=0.94},
    achilles = {ambient=1.06, diffuse=0.96, specular=0.90},
    elysium  = {ambient=1.04, diffuse=0.98, specular=0.90},
}
local stems={mn="moon",ma="mars",ve="venus",io="io",eu="europa",ti="titan",ga="ganymede",ac="achilles",el="elysium"}
function Art.Detect(trn)
    if trn and type(GetODFString)=="function" then
        local atlas=string.lower(GetODFString(trn,"Atlases","MaterialName","") or "")
        return stems[atlas:sub(1,2)]
    end
end
function Art.Apply(world,frame)
    local settings=Art.Worlds[world]
    if not settings then return frame end
    for _,channel in ipairs({"ambient","diffuse","specular"}) do
        local c=frame[channel]
        if c then
            local gain=settings[channel]
            frame[channel]={r=math.max(0,math.min(1,c.r*gain)),g=math.max(0,math.min(1,c.g*gain)),b=math.max(0,math.min(1,c.b*gain))}
        end
    end
    return frame
end
return Art
