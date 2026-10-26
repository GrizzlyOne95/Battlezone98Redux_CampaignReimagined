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
-- Domes drawn by a shader that takes the frame state (CR_marssky,
-- CR_venussky, CR_titansky, CR_achillessky): the sun, night blend and clarity
-- go into the technique 0 pass colours, and the stock engine cloud sprites are
-- hidden because the dome draws its own clouds. A dome flagged weather (Venus,
-- Titan, Achilles) also takes the weather's sky state. A dome flagged body
-- draws the world's shining body itself (Saturn over Titan, through the haze;
-- Uranus and its rings over Achilles, between the clouds), so its TRN quad is
-- hidden and the dome takes the body's direction. Titan's haze is opaque, so
-- its TRN star sprites go too. restore gives each hidden sprite's own texture
-- back while a mission hides the dome (misn18's storm, Art.RestoreSkySprites).
Art.SkyFrames={mars={hide={"ACLOUD2.MAP","ACLOUD.MAP"}},venus={hide={},weather=true},
    titan={hide={"ACLOUD2.MAP","SATURN.MAP","STARS.MAP"},weather=true,body=true},
    achilles={hide={"ACLOUD2.MAP","ACLOUD.MAP","URANUS.MAP"},weather=true,body=true,
        restore={["ACLOUD2.MAP"]="acloud2.tga",["ACLOUD.MAP"]="acloud.tga",["URANUS.MAP"]="uranus.dds"}}}
Art.SkyFrameState={}
-- Airless worlds get the catalog sky box instead of a dome. Its stars and
-- Milky Way replace the TRN's STARS.MAP sprites and MILKYWAY.MAP quad; the
-- other [Stars] quads (Earth, meteors) still draw over the opaque box.
-- The box also draws the sun, so Config/spritea.st points the engine's sun.0
-- sprite at its own material, crsun, which is hidden once the box's sun is
-- anchored. The sprite still rasterizes, so the lens flare's occlusion test
-- keeps working.
-- The TRN's sky bodies (bodies: the Earth over the Moon, CREARTH.MAP; Jupiter
-- and the other Galilean moons over Io and Europa, Shaders/CR_jovian.hlsl) are
-- spheres lit from sunDirection, so the box's sun also gives them their
-- phases. The Io and Europa TRNs name no sun sprite: the box's sun is the
-- only one.
Art.StarBoxes={moon={material="CR_Sky/CatalogStars",hide={"STARS.MAP","MILKYWAY.MAP"},sunSprite="crsun",bodies={"CREARTH.MAP"}},
    io={material="CR_Sky/IoStars",hide={"STARS.MAP"},bodies={"CRJOVIAN.MAP","CREUROPA.MAP","CRGANYME.MAP","CRCALLIS.MAP"}},
    europa={material="CR_Sky/EuropaStars",hide={"STARS.MAP"},bodies={"CRJOVIAN.MAP","CRIO.MAP","CRGANYME.MAP","CRCALLIS.MAP"}}}
Art.SunAnchored={}
-- A compass heading (0 along +z, 90 along +x) and elevation, in degrees, as a
-- unit vector. TRN [Stars] entries use this convention, in sim space; Redux
-- draws the world with z mirrored (render z = -sim z), so the entry's quad
-- stands at (x, y, -z). Every direction here is in that render space, the
-- one the sky shaders, GetSunDirection and the scene light use.
local function heading_vector(azimuth,elevation)
    local a,e=math.rad(tonumber(azimuth) or 0),math.rad(tonumber(elevation) or 0)
    return {x=math.sin(a)*math.cos(e),y=math.sin(e),z=-math.cos(a)*math.cos(e)}
end
-- The sky's sun, when a mission sets one (Environment's night mode). It stands
-- in for the light's direction wherever the sky needs the real sun: the star
-- box, the Earth's phase and its shine. The scene light can then come from
-- somewhere else, the Earth at lunar night.
Art.SkySun={}
function Art.SetSkySun(world,spec)
    Art.SkySun[world or ""]=nil
    if not world or type(spec)~="table" then return nil end
    local sun=heading_vector(spec.azimuth,spec.elevation)
    Art.SkySun[world]=sun
    return sun
end
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
local function write_vector(api,material,name,x,y,z,w)
    local ok,n=pcall(api.SetMaterialShaderVector,material,name,x,y,z,w,-1,-1,"Autodetect")
    return ok and tonumber(n) or 0
end
local function write_sun(api,material,s)
    return write_vector(api,material,"sunDirection",s[1],s[2],s[3],1)
end
-- Ogre draws the box with one clone per face, <scene manager>SkyBoxPlane0..5.
-- A uniform written to the base before SetSkyBox does not reach them in game,
-- so the clones are written after it; each reinstall copies the base (no sun)
-- over them again. Redux has one scene manager,
-- normally SceneManagerInstance1; the next few names are tried in case. On an
-- orbit world the faces also take the pole the sun circles.
Art.BoxFaces={}
local function anchor_box_faces(api,s,world,orbit)
    Art.BoxFaces[world]=nil
    for instance=1,4 do
        local prefix="SceneManagerInstance"..instance.."SkyBoxPlane"
        if write_sun(api,prefix.."0",s)>0 then
            for face=0,5 do
                if face>0 then write_sun(api,prefix..face,s) end
                if orbit then write_vector(api,prefix..face,"skyOrbit",orbit.pole.x,orbit.pole.y,orbit.pole.z,1) end
            end
            Art.BoxFaces[world]=prefix
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
    local sky=Art.SkySun[world]
    local sun=sky and {sky.x,sky.y,sky.z} or sun_vector(api)
    local orbit=Art.Orbit[world]
    Art.SunAnchored[world]=sun~=nil and anchor_box_faces(api,sun,world,orbit)
    Art.OrbitWritten[world]=nil
    if sun then
        -- Engine sky materials take the TRN's case.
        for _,name in ipairs(box.bodies or {}) do
            for _,material in ipairs({name,name:lower()}) do
                write_sun(api,material,sun)
                if orbit then write_vector(api,material,"bodyPole",orbit.pole.x,orbit.pole.y,orbit.pole.z,1) end
            end
        end
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
-- Gives the stock sprites back while a mission hides the dome that replaced
-- them; HideSkySprites takes them away again. False when the world names no
-- textures to restore.
function Art.RestoreSkySprites(api,world)
    local spec=Art.SkyFrames[world]
    if not spec or not spec.restore or not api or type(api.SetMaterialTexture)~="function" then return false end
    for name,texture in pairs(spec.restore) do
        for _,material in ipairs({name,name:lower()}) do pcall(api.SetMaterialTexture,material,texture) end
    end
    return true
end
local function unit(v) return math.max(0,math.min(1,tonumber(v) or 0)) end
-- Io keeps one face to Jupiter, so Jupiter hangs still in its sky while the
-- sun crosses it once an Io day along Jupiter's equator (Io orbits in that
-- plane) and passes behind the planet once an orbit. Art.SetOrbit works the
-- path out from Jupiter's TRN place, the world's shine source: the great circle
-- through Jupiter square to the pole P, the axis square to both Jupiter's
-- direction and east-west that tilts up. The hour angle h counts from noon,
-- where the sun stands highest: S(h) = cos h * noon + sin h * west.
-- Europa is the same, one moon out: a smaller Jupiter and a longer day.
-- radius: Jupiter's angular radius from the moon (degrees). spinTurns: how
-- often Jupiter turns, seen from the moon, in one of its days (Io: synodic
-- 12.95 h in 42.46 h; Europa: 11.23 h in 85.23 h); spin names the material
-- that turns, from longitude spinStart (radians), and spinLook carries the
-- rest of its bodySpin (Minnaert exponent, limb haze).
Art.Orbits={io={radius=9.625,spin="CRJOVIAN.MAP",spinTurns=3.28,spinStart=-0.3,spinLook={0.9,0.35}},
    europa={radius=6.115,spin="CRJOVIAN.MAP",spinTurns=7.59,spinStart=1.2,spinLook={0.9,0.35}}}
Art.Orbit={}
Art.OrbitWritten={}
local atan2=math.atan2 or math.atan
function Art.SetOrbit(world)
    Art.Orbit[world or ""]=nil
    Art.OrbitWritten[world or ""]=nil
    local spec,body=Art.Orbits[world],Art.ShineSource[world]
    if not spec or not body or body.y<0.05 then return nil end
    local len=math.sqrt(body.y*body.y+body.z*body.z)
    -- Render space is right-handed with z to the south, so this pole is north.
    local pole={x=0,y=body.z/len,z=-body.y/len}
    local noon={x=0,y=-pole.z,z=pole.y}
    local orbit={spec=spec,pole=pole,noon=noon,body=body,bodyHour=atan2(-body.x,body.y*noon.y+body.z*noon.z)}
    Art.Orbit[world]=orbit
    return orbit
end
-- Toward the sun at hour angle h (radians).
function Art.OrbitSun(world,hour)
    local o=Art.Orbit[world]
    if not o then return nil end
    local c,s=math.cos(hour),math.sin(hour)
    return {x=-s,y=c*o.noon.y,z=c*o.noon.z}
end
-- How much of the sun Jupiter hides: 1 with the sun behind the disc, easing
-- over 0.6 degrees either side of the limb.
function Art.OrbitEclipse(world,sun)
    local o=Art.Orbit[world]
    if not o or type(sun)~="table" then return 0 end
    local b=o.body
    local separation=math.deg(math.acos(math.max(-1,math.min(1,sun.x*b.x+sun.y*b.y+sun.z*b.z))))
    local t=unit((separation-(o.spec.radius-0.6))/1.2)
    return 1-t*t*(3-2*t)
end
-- Every frame on an orbit world: the box turns its stars with the sun and
-- hides it in eclipse, each body takes the sun for its phase and the pole for
-- its axis, and Jupiter turns. orbit = {sun={x,y,z} toward the sun, eclipse,
-- hour, startHour}. Writes wait until the sun has moved about a sixtieth of a
-- degree, well under a pixel of star motion.
local function update_orbit(api,world,orbit)
    local o,box,s=Art.Orbit[world],Art.StarBoxes[world],orbit.sun
    if not o or not box or type(s)~="table" or type(api.SetMaterialShaderVector)~="function" then return end
    local visible=1-unit(orbit.eclipse)
    local last=Art.OrbitWritten[world]
    if last and math.abs(last.x-s.x)+math.abs(last.y-s.y)+math.abs(last.z-s.z)<0.0003
        and math.abs(last.visible-visible)<0.005 then return end
    local p,spec=o.pole,o.spec
    -- Seen from Io, Jupiter's face drifts west to east (left to right, north up).
    local spin=(spec.spinStart-spec.spinTurns*((tonumber(orbit.hour) or 0)-(tonumber(orbit.startHour) or 0)))%(2*math.pi)
    local prefix=Art.BoxFaces[world]
    if prefix then
        for face=0,5 do
            write_vector(api,prefix..face,"sunDirection",s.x,s.y,s.z,1)
            write_vector(api,prefix..face,"skyOrbit",p.x,p.y,p.z,visible)
        end
    end
    for _,name in ipairs(box.bodies or {}) do
        for _,material in ipairs({name,name:lower()}) do
            write_vector(api,material,"sunDirection",s.x,s.y,s.z,1)
            write_vector(api,material,"bodyPole",p.x,p.y,p.z,1)
            if name==spec.spin then write_vector(api,material,"bodySpin",spin,0,spec.spinLook[1],spec.spinLook[2]) end
        end
    end
    Art.OrbitWritten[world]={x=s.x,y=s.y,z=s.z,visible=visible}
end
-- frame (optional): {sun={x,y,z} toward the sun, night=0..1, clarity=0..1,
-- weather={storm=0..1, bank=0..1, flash=0..1, flashDir={x,y,z}} (optional)}.
-- Specular stays (Enhanced flag, sun direction). Emissive is (night, clarity,
-- then cloud cover (the clarity) and 0, or on a weather dome the storm gloom
-- and fog bank; Titan's haze and haze roll take those two slots). Diffuse is
-- (direction toward the lightning, flash strength). On a body dome, ambient is
-- (direction toward the body, 1), or 0 in w when the map has none.
-- Writes are skipped until something moves noticeably.
local function update_sky_frame(api,material,enhanced,frame,spec,world)
    local s=frame.sun
    local night=unit(frame.night)
    local clarity=math.max(0,math.min(1,tonumber(frame.clarity) or 1))
    local w=spec.weather and (type(frame.weather)=="table" and frame.weather or {}) or nil
    local storm,bank,flash=unit(w and w.storm),unit(w and w.bank),unit(w and w.flash)
    local f=flash>0 and type(w.flashDir)=="table" and w.flashDir or {x=0,y=1,z=0}
    local fx,fy,fz=tonumber(f.x) or 0,tonumber(f.y) or 1,tonumber(f.z) or 0
    local last=Art.SkyFrameState[material]
    if last and last.enhanced==enhanced and math.abs(last.x-s.x)+math.abs(last.y-s.y)+math.abs(last.z-s.z)<0.002
        and math.abs(last.night-night)<0.004 and math.abs(last.clarity-clarity)<0.004
        and math.abs(last.storm-storm)<0.004 and math.abs(last.bank-bank)<0.004 and math.abs(last.flash-flash)<0.004 then return true end
    local colours={specular={r=enhanced and 1 or 0,g=s.x,b=s.y,a=s.z},
        emissive=w and {r=night,g=clarity,b=storm,a=bank} or {r=night,g=clarity,b=clarity,a=0},
        diffuse={r=fx,g=fy,b=fz,a=flash}}
    if spec.body then
        local b=Art.ShineSource[world]
        colours.ambient=b and {r=b.x,g=b.y,b=b.z,a=1} or {r=0,g=0,b=1,a=0}
    end
    local accepted,result=pcall(api.SetMaterialPassColors,material,colours,0,0,"General")
    if not accepted or result~=true then return false end
    Art.SkyFrameState[material]={enhanced=enhanced,x=s.x,y=s.y,z=s.z,night=night,clarity=clarity,storm=storm,bank=bank,flash=flash}
    return true
end
function Art.UpdateSky(api,world,frame)
    if Art.Orbit[world] then
        if api and type(frame)=="table" and type(frame.orbit)=="table" then update_orbit(api,world,frame.orbit) end
        return
    end
    local material=Art.Skies[world]
    if not material or type(api.GetEffectiveRenderProfile)~="function" or type(api.SetMaterialPassColors)~="function" then return end
    local ok,profile=pcall(api.GetEffectiveRenderProfile)
    if not ok or type(profile)~="string" then return end
    local enhanced=profile:lower()=="enhanced"
    local accepted,result
    if Art.SkyFrames[world] and type(frame)=="table" and type(frame.sun)=="table" then
        -- The frame write carries the calibration flag too.
        accepted,result=true,update_sky_frame(api,material,enhanced,frame,Art.SkyFrames[world],world)
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
-- Planetshine: the sunlit face of a big sky body lights the ground. It adds to
-- the ambient in the body's colour, scaled by how much of its lit face the
-- ground sees, (1 - cos(sun to body angle)) / 2, the phase the CREARTH.MAP
-- shader draws. Night uses the larger share. In daylight the real light is
-- tiny beside the sun, so the day share only tints the shadows.
-- texture names the body's TRN [Stars] entry, whose Azimuth/Elevation place it:
-- azimuth is a compass heading, 0 along +z and 90 along +x. GetODFString also
-- returns a found flag, so its string is taken alone before tonumber.
-- light (optional) is the body's strength as the night's directional light,
-- see Art.NightLight; a frame flagged bodyLight then takes only the bounce
-- share as ambient, since the light itself already carries the rest.
-- Io's is Jupiter: a warm tan light, full when the sun is opposite it (Io's
-- midnight) and new in eclipse. Its night share is small because, in orbit
-- mode, Jupiter is already the night's directional light. Its light stays
-- below the day's diffuse, so a full Jupiter still reads as night. From
-- Europa Jupiter covers 0.4 times the sky it does from Io, so its light is
-- weaker, but the bright ice gives more of it back.
-- Titan's is Saturn, which hangs still over the Saturn-facing side, full at
-- local midnight. By day the haze hides its light entirely; at night it is
-- the haze-reddened light that casts the shadows (Environment's night mode),
-- and the haze scatters a good share of it round as ambient.
-- Achilles' is Uranus, 25 degrees across in the TRN, so close that its pale
-- cyan light tints the day a little and the night a good deal. The real Uranus
-- gets a 360th of the Earth's sunlight; this one is lit for the screen.
Art.Shine={moon={texture="crearth.map",colour={r=0.62,g=0.74,b=1.00},day=0.10,night=0.30,light=0.45,bounce=0.08},
    io={texture="crjovian.map",colour={r=1.00,g=0.80,b=0.58},day=0.05,night=0.07,light=0.36},
    europa={texture="crjovian.map",colour={r=1.00,g=0.82,b=0.62},day=0.03,night=0.05,light=0.22},
    titan={texture="saturn.map",colour={r=1.00,g=0.70,b=0.40},day=0.0,night=0.06,light=0.26,bounce=0.10},
    achilles={texture="uranus.map",colour={r=0.62,g=0.86,b=1.00},day=0.04,night=0.22,light=0.24,bounce=0.07}}
Art.ShineSource={}
function Art.DetectShine(trn,world)
    Art.ShineSource[world or ""]=nil
    local spec=Art.Shine[world]
    if not spec or not trn or type(GetODFString)~="function" then return nil end
    for index=0,63 do
        local key=string.format("%02d",index)
        if string.lower(GetODFString(trn,"Stars","Texture"..key,"") or "")==spec.texture then
            local body=heading_vector((GetODFString(trn,"Stars","Azimuth"..key,"0")),(GetODFString(trn,"Stars","Elevation"..key,"0")))
            Art.ShineSource[world]=body
            return body
        end
    end
    return nil
end
-- frame.sun (toward the sun) and frame.night (0..1) are optional; without the
-- sun there is no phase and no shine.
local function apply_shine(world,frame)
    local spec,body,s,a=Art.Shine[world],Art.ShineSource[world],frame.sun,frame.ambient
    if not spec or not body or type(s)~="table" or not a then return end
    local len=math.sqrt(s.x*s.x+s.y*s.y+s.z*s.z)
    if len<1e-6 then return end
    local phase=(1-(s.x*body.x+s.y*body.y+s.z*body.z)/len)*0.5
    local night=math.max(0,math.min(1,tonumber(frame.night) or 0))
    local k=phase*(frame.bodyLight and spec.bounce or (spec.day+(spec.night-spec.day)*night))
    local c=spec.colour
    frame.ambient={r=math.min(1,a.r+c.r*k),g=math.min(1,a.g+c.g*k),b=math.min(1,a.b+c.b*k)}
    frame.shine=k
end
-- At night the shining body is the brightest thing in the sky, so it takes the
-- scene's directional light: shadows fall away from it, in its colour, as
-- strong as its phase allows. Nil when the world has no such body.
function Art.NightLight(world)
    local spec,body=Art.Shine[world],Art.ShineSource[world]
    if not spec or not body or not spec.light then return nil end
    local s=Art.SkySun[world]
    local phase=s and (1-(s.x*body.x+s.y*body.y+s.z*body.z))*0.5 or 1
    local k,c=spec.light*phase,spec.colour
    return {direction={x=-body.x,y=-body.y,z=-body.z},
        diffuse={r=c.r*k,g=c.g*k,b=c.b*k},specular={r=c.r*k*0.5,g=c.g*k*0.5,b=c.b*k*0.5}}
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
    apply_shine(world,frame)
    return frame
end
return Art
