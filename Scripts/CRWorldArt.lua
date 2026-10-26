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
-- Airless worlds get the catalog sky box instead of a dome. Its stars and
-- Milky Way replace the TRN's STARS.MAP sprites and MILKYWAY.MAP quad; the
-- other [Stars] quads (Earth, meteors) still draw over the opaque box.
Art.StarBoxes={moon={material="CR_Sky/CatalogStars",hide={"STARS.MAP","MILKYWAY.MAP"}}}
function Art.InstallStarBox(api,world)
    local box=Art.StarBoxes[world]
    if not box or not api or type(api.SetSkyBox)~="function" then return false end
    -- Like the misn06 orbit box: at 0.2x far its corners stay inside the sky cull limit.
    local far=3000
    if type(api.GetCameraClipDistances)=="function" then
        local ok,_,f=pcall(api.GetCameraClipDistances)
        if ok and tonumber(f) and f>0 then far=f end
    end
    local accepted,result=pcall(api.SetSkyBox,box.material,far*0.2,true)
    if not accepted or result~=true then return false end
    if type(api.SetMaterialTexture)=="function" then
        -- Engine sky materials report false to MaterialExists, and their case follows the TRN.
        for _,name in ipairs(box.hide) do
            for _,material in ipairs({name,name:lower()}) do pcall(api.SetMaterialTexture,material,"cr06void.dds") end
        end
    end
    print("WorldArt: catalog star box at "..tostring(far*0.2))
    return true
end
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
-- (Re)installs the world dome. The misn06 orbital film replaces the dome
-- material on its fallback path and calls this (through
-- Environment.RestoreArtSky) when it ends. Atmosphere updates pause while the
-- film runs, and UpdateSky only writes material parameters (it never toggles
-- dome enablement), so it cannot fight the film.
function Art.InstallSky(api,world)
    if Art.StarBoxes[world] then return Art.InstallStarBox(api,world) end
    local material=Art.Skies[world]
    if not material or not api or type(api.SetSkyDome)~="function" then return false end
    -- Draw behind scene geometry/effects with far-plane depth. Redux
    -- suppresses its native sky when an Ogre sky is enabled, so this material
    -- must draw the original texture rather than a transparent haze alone.
    local accepted,result=pcall(api.SetSkyDome,material,10,8,4000,true,32,16,-1,"General")
    if accepted and result==true then Art.UpdateSky(api,world) end
    return accepted and result==true
end
function Art.InitializeSky(api,world)
    local box=Art.StarBoxes[world]
    local material=box and box.material or Art.Skies[world]
    if not material or not api or type(api.MaterialExists)~="function" then return false end
    if not box and type(api.SetSkyDome)~="function" then return false end
    -- Respect map-owned cinematics and weather skies. This baseline reuses
    -- the world's original sky art, with a continuous fog-coloured lower edge.
    for _,name in ipairs({"GetSkyDomeEnabled","GetSkyPlaneEnabled","GetSkyBoxEnabled"}) do
        if type(api[name])~="function" then return false end
        local ok,enabled=pcall(api[name]);if not ok or enabled then return false end
    end
    local ok,exists=pcall(api.MaterialExists,material,"General")
    if not ok or not exists then return false end
    return Art.InstallSky(api,world)
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
