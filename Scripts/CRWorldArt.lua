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
Art.Skies={mars="CRSKYMA.MAP",venus="CRSKYVE.MAP",titan="CRSKYTI.MAP",achilles="CRSKYAC.MAP",elysium="CRSKYEL.MAP"}
Art.SkyCalibration={}
function Art.UpdateSky(api,world)
    local material=Art.Skies[world]
    if not material or type(api.GetEffectiveRenderProfile)~="function" or type(api.SetMaterialPassColors)~="function" then return end
    local ok,profile=pcall(api.GetEffectiveRenderProfile)
    if not ok or type(profile)~="string" then return end
    local enhanced=profile:lower()=="enhanced"
    if Art.SkyCalibration[material]==enhanced then return end
    local accepted,result=pcall(api.SetMaterialPassColors,material,{specular={r=enhanced and 1 or 0,g=0,b=0,a=1}},0,0,"General")
    if accepted and result==true then
        Art.SkyCalibration[material]=enhanced
        print("WorldArt: sky fog calibration -> "..profile:lower())
    end
end
function Art.InitializeSky(api,world,mapName)
    -- The orbital film temporarily replaces the dome and restores its enabled
    -- state. Keep its original no-dome baseline intact.
    if tostring(mapName or ""):lower():match("misn06%.?[^/\\]*$") then return false end
    local material=Art.Skies[world]
    if not material or not api or type(api.SetSkyDome)~="function" or type(api.MaterialExists)~="function" then return false end
    -- Respect map-owned cinematics and weather skies. This baseline reuses
    -- the world's original sky art, with a continuous fog-coloured lower edge.
    for _,name in ipairs({"GetSkyDomeEnabled","GetSkyPlaneEnabled","GetSkyBoxEnabled"}) do
        if type(api[name])~="function" then return false end
        local ok,enabled=pcall(api[name]);if not ok or enabled then return false end
    end
    local ok,exists=pcall(api.MaterialExists,material,"General")
    if not ok or not exists then return false end
    -- Draw behind scene geometry/effects with far-plane depth. Redux
    -- suppresses its native sky when an Ogre sky is enabled, so this material
    -- must draw the original texture rather than a transparent haze alone.
    local accepted,result=pcall(api.SetSkyDome,material,10,8,4000,true,32,16,-1,"General")
    if accepted and result==true then Art.UpdateSky(api,world) end
    return accepted and result==true
end
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
