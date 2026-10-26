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
-- Domes drawn by a shader that takes the frame state (CR_marssky): the sun,
-- night blend and clarity go into the technique 0 pass colours, and the stock
-- engine cloud sprites are hidden because the dome draws its own clouds.
Art.SkyFrames={mars={hide={"ACLOUD2.MAP","ACLOUD.MAP"}}}
Art.SkyFrameState={}
-- Airless worlds get the catalog sky box instead of a dome. Its stars and
-- Milky Way replace the TRN's STARS.MAP sprites and MILKYWAY.MAP quad; the
-- other [Stars] quads (Earth, meteors) still draw over the opaque box.
-- The box also draws the sun, so Config/spritea.st points the engine's sun.0
-- sprite at its own material, crsun, which is hidden once the box's sun is
-- anchored. The sprite still rasterizes, so the lens flare's occlusion test
-- keeps working.
-- The TRN's Earth quad uses CREARTH.MAP, a sphere lit from sunDirection, so
-- the box's sun also gives the Earth its phase.
Art.StarBoxes={moon={material="CR_Sky/CatalogStars",hide={"STARS.MAP","MILKYWAY.MAP"},sunSprite="crsun",earth="CREARTH.MAP"}}
Art.SunAnchored={}
-- The box turns the star sphere so the sun sits at the March equinox, which
-- keeps the Milky Way at least 60 degrees from it. The engine's sun sprite
-- never follows the light, so the TRN direction read at install is the anchor.
local function sun_vector(api)
    if type(api.GetSunDirection)~="function" or type(api.SetMaterialShaderVector)~="function" then return nil end
    -- A game VECTOR_3D is userdata, so read the fields under pcall.
    local ok,x,y,z=pcall(function() local d=api.GetSunDirection();return tonumber(d.x),tonumber(d.y),tonumber(d.z) end)
    if not ok then return nil end
    local len=x and y and z and math.sqrt(x*x+y*y+z*z) or 0
    if len<1e-6 then return nil end
    -- The light travels away from the sun.
    return {-x/len,-y/len,-z/len}
end
local function write_sun(api,material,s)
    local ok,n=pcall(api.SetMaterialShaderVector,material,"sunDirection",s[1],s[2],s[3],1,-1,-1,"Autodetect")
    return ok and tonumber(n) or 0
end
-- Ogre draws the box with one clone per face, <scene manager>SkyBoxPlane0..5.
-- A uniform written to the base before SetSkyBox does not reach them in game,
-- so the clones are written after it; each reinstall copies the base (no sun)
-- over them again. Redux has one scene manager,
-- normally SceneManagerInstance1; the next few names are tried in case.
local function anchor_box_faces(api,s)
    for instance=1,4 do
        local prefix="SceneManagerInstance"..instance.."SkyBoxPlane"
        if write_sun(api,prefix.."0",s)>0 then
            for face=1,5 do write_sun(api,prefix..face,s) end
            return true
        end
    end
    return false
end
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
    local sun=sun_vector(api)
    Art.SunAnchored[world]=sun~=nil and anchor_box_faces(api,sun)
    if sun and box.earth then
        -- Engine sky materials take the TRN's case.
        for _,material in ipairs({box.earth,box.earth:lower()}) do write_sun(api,material,sun) end
    end
    if sun and not Art.SunAnchored[world] then print("WorldArt: star box faces not found; the stock sun stays") end
    Art.HideSkySprites(api,world)
    print("WorldArt: catalog star box at "..tostring(far*0.2))
    return true
end
local function hide_sprites(api,names)
    if type(api.SetMaterialTexture)~="function" then return end
    -- Engine sky materials report false to MaterialExists, and their case follows the TRN.
    for _,name in ipairs(names) do
        for _,material in ipairs({name,name:lower()}) do pcall(api.SetMaterialTexture,material,"cr06void.dds") end
    end
end
-- Re-hides the stock sprites a dome replaces; the misn06 orbit film restores
-- their textures when it ends.
function Art.HideSkySprites(api,world)
    local spec=Art.StarBoxes[world] or Art.SkyFrames[world]
    if spec and api then
        hide_sprites(api,spec.hide)
        if spec.sunSprite and Art.SunAnchored[world] then hide_sprites(api,{spec.sunSprite}) end
    end
end
-- frame (optional): {sun={x,y,z} toward the sun, night=0..1, clarity=0..1}.
-- Specular stays (Enhanced flag, sun direction); emissive is (night, clarity,
-- cloud cover, 0). Writes are skipped until something moves noticeably.
local function update_sky_frame(api,material,enhanced,frame)
    local s=frame.sun
    local night=math.max(0,math.min(1,tonumber(frame.night) or 0))
    local clarity=math.max(0,math.min(1,tonumber(frame.clarity) or 1))
    local last=Art.SkyFrameState[material]
    if last and last.enhanced==enhanced and math.abs(last.x-s.x)+math.abs(last.y-s.y)+math.abs(last.z-s.z)<0.002
        and math.abs(last.night-night)<0.004 and math.abs(last.clarity-clarity)<0.004 then return true end
    local accepted,result=pcall(api.SetMaterialPassColors,material,{specular={r=enhanced and 1 or 0,g=s.x,b=s.y,a=s.z},emissive={r=night,g=clarity,b=clarity,a=0}},0,0,"General")
    if not accepted or result~=true then return false end
    Art.SkyFrameState[material]={enhanced=enhanced,x=s.x,y=s.y,z=s.z,night=night,clarity=clarity}
    return true
end
function Art.UpdateSky(api,world,frame)
    local material=Art.Skies[world]
    if not material or type(api.GetEffectiveRenderProfile)~="function" or type(api.SetMaterialPassColors)~="function" then return end
    local ok,profile=pcall(api.GetEffectiveRenderProfile)
    if not ok or type(profile)~="string" then return end
    local enhanced=profile:lower()=="enhanced"
    local accepted,result
    if Art.SkyFrames[world] and type(frame)=="table" and type(frame.sun)=="table" then
        -- The frame write carries the calibration flag too.
        accepted,result=true,update_sky_frame(api,material,enhanced,frame)
        if Art.SkyCalibration[material]==enhanced then return end
    else
        if Art.SkyCalibration[material]==enhanced then return end
        accepted,result=pcall(api.SetMaterialPassColors,material,{specular={r=enhanced and 1 or 0,g=0,b=0,a=1}},0,0,"General")
        -- That cleared the sun direction; the next frame must rewrite it.
        Art.SkyFrameState[material]=nil
    end
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
    if accepted and result==true then
        Art.SkyFrameState[material]=nil
        Art.HideSkySprites(api,world)
        Art.UpdateSky(api,world)
    end
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
