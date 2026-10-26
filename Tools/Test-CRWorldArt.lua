local scripts=... or "Scripts"
package.path=scripts.."/?.lua;"..package.path
local Art=require("CRWorldArt")
local count=0
local function check(ok,message) count=count+1;assert(ok,message) end
for world,spec in pairs(Art.Worlds) do
 local frame={ambient={r=.2,g=.3,b=.4},diffuse={r=.5,g=.4,b=.3},specular={r=.1,g=.2,b=.3},fog={r=.3,g=.2,b=.1}}
 local fog=frame.fog
 Art.Apply(world,frame)
 check(math.abs(frame.ambient.r/frame.ambient.g-2/3)<1e-8,world.." ambient palette")
 check(math.abs(frame.diffuse.r/frame.diffuse.g-1.25)<1e-8,world.." sunlight palette")
 check(frame.fog==fog,world.." atmosphere ownership")
 check(frame.diffuse.r<=1 and frame.ambient.r>=0,world.." bounded lighting")
end
local f={ambient={r=.2,g=.3,b=.4}}
check(Art.Apply(nil,f)==f and f.ambient.r==.2,"unknown worlds retain native lighting")
GetODFString=function() return "GA_DETAIL_ATLAS" end
check(Art.Detect({})=="ganymede","material identifies world independently of weather preset")
local draws=0
local api={MaterialExists=function() return true end,
 GetSkyDomeEnabled=function() return false end,
 GetSkyPlaneEnabled=function() return false end,
 GetSkyBoxEnabled=function() return false end,
 SetSkyDome=function(material,curvature,tiling,distance,drawFirst)
  check(material=="CRSKYMA.MAP" and drawFirst==true,"owned sky draws behind scene geometry and transparent effects")
  draws=draws+1;return true
 end}
check(not Art.InitializeSky(api,"moon") and draws==0,"airless world without a sky box API keeps stock sky")
local boxes,hidden={},{}
api.GetCameraClipDistances=function() return 1,2500 end
api.SetSkyBox=function(material,distance,drawFirst) boxes[#boxes+1]={material,distance,drawFirst};return true end
api.SetMaterialTexture=function(material,texture) hidden[material]=texture;return true end
check(Art.InitializeSky(api,"moon") and draws==0 and #boxes==1,"airless world installs the catalog star box, not a dome")
check(boxes[1][1]=="CR_Sky/CatalogStars" and boxes[1][2]==500 and boxes[1][3]==true,"star box draws first at 0.2x far")
check(hidden["STARS.MAP"]=="cr06void.dds" and hidden["milkyway.map"]=="cr06void.dds","star box hides the TRN star sprites and Milky Way quad")
check(hidden["crsun"]==nil,"without a sun anchor the engine sun sprite stays")
check(Art.InstallSky(api,"moon") and #boxes==2,"star box can be reinstalled after a cinematic")
local vectors,faces={},{}
-- The game returns VECTOR_3D userdata, not a table.
local light=newproxy(true);getmetatable(light).__index=function(_,k) return ({x=0,y=-3,z=4})[k] end
api.GetSunDirection=function() return light end
api.SetMaterialShaderVector=function(material,name,x,y,z,w)
 vectors[#vectors+1]={material,name,x,y,z,w,#boxes}
 return material:match("^SceneManagerInstance2SkyBoxPlane%d$") and 1 or 0
end
check(Art.InstallSky(api,"moon") and #vectors==9,"star box anchors its sun on each face and the Earth")
for i=1,#vectors do local v=vectors[i];if v[6]==1 and v[1]:match("^SceneManagerInstance2") then faces[v[1]]=v end end
local v=faces["SceneManagerInstance2SkyBoxPlane5"]
check(next(faces)~=nil and v and v[2]=="sunDirection" and v[7]==3,"faces are written after the box clones them")
check(math.abs(v[3])<1e-9 and math.abs(v[4]-0.6)<1e-9 and math.abs(v[5]+0.8)<1e-9,"sun points back along the light, normalized")
check(vectors[1][1]=="SceneManagerInstance1SkyBoxPlane0","the usual scene manager is tried first")
check(hidden["crsun"]=="cr06void.dds","an anchored sun hides the engine sun sprite")
local earth={}
for i=1,#vectors do local v=vectors[i];if v[1]:upper()=="CREARTH.MAP" then earth[v[1]]=v end end
check(earth["CREARTH.MAP"] and earth["crearth.map"],"the Earth is lit under both material cases")
check(earth["crearth.map"][2]=="sunDirection" and math.abs(earth["crearth.map"][4]-0.6)<1e-9 and earth["crearth.map"][6]==1,"the Earth takes the box's sun")
vectors={}
local faceless=api.SetMaterialShaderVector
api.SetMaterialShaderVector=function(material,...) vectors[#vectors+1]=material;return 0 end
Art.InstallSky(api,"moon")
check(vectors[#vectors]=="crearth.map","the Earth is lit even when the box faces are not found")
api.SetMaterialShaderVector=faceless
hidden={}
api.SetMaterialShaderVector=function() return 0 end
check(Art.InstallSky(api,"moon") and hidden["crsun"]==nil and hidden["STARS.MAP"],"unfound faces keep the engine sun")
api.GetSunDirection=function() return {x=0,y=0,z=0} end
check(Art.InstallSky(api,"moon") and hidden["crsun"]==nil,"a zero light keeps the engine sun")
api.GetSunDirection=function() error("no light") end
check(Art.InstallSky(api,"moon") and #boxes==7,"a failing light read still installs the box")
api.SetSkyBox,api.SetMaterialTexture,api.GetCameraClipDistances,api.GetSunDirection,api.SetMaterialShaderVector=nil,nil,nil,nil,nil
-- Only the sun row moves to crsun; the lens flare rings keep sprite_a.
local st=assert(io.open(scripts.."/../Config/spritea.st","rb")):read("*a")
local crsunRows,sunRow=0,nil
for line in st:gmatch("[^\r\n]+") do
 local name,material=line:match('^"([^"]+)"%s+(%S+)')
 if material=="crsun" then crsunRows=crsunRows+1 end
 if name=="sun.0" then sunRow=material end
 if name and name:match("^ring%.") then check(material=="sprite_a",name.." keeps sprite_a") end
end
check(crsunRows==1 and sunRow=="crsun","spritea.st points only sun.0 at crsun")
local sprites=assert(io.open(scripts.."/../Materials/sprites.material","rb")):read("*a")
check(sprites:find("material crsun : BZSprite/Additive",1,true)~=nil,"crsun material exists")
check(Art.InitializeSky(api,"mars") and draws==1,"atmospheric baseline installs")
check(Art.InitializeSky(api,"mars","misn06.trn") and draws==2,"Mission 6 owns the world dome like other Mars maps")
check(Art.InstallSky(api,"mars") and draws==3,"orbital film can reinstall the baseline dome")
check(not Art.InstallSky(api,"moon") and draws==3,"airless world has no dome to reinstall")
api.GetSkyDomeEnabled=function() return true end
check(not Art.InitializeSky(api,"mars") and draws==3,"existing cinematic or weather dome is preserved")
api.GetSkyDomeEnabled=function() return false end
api.MaterialExists=function() return false end
check(not Art.InitializeSky(api,"mars") and draws==3,"missing material preserves native sky")
check(not Art.InitializeSky({},"mars"),"missing optional renderer API preserves native sky")
api.MaterialExists=function() return true end
api.GetSkyPlaneEnabled=function() error("unavailable") end
check(not Art.InitializeSky(api,"mars") and draws==3,"failed ownership query preserves native sky")
local profile,writes="enhanced",{}
api.GetEffectiveRenderProfile=function() return profile end
api.SetMaterialPassColors=function(name,colours)
 writes[#writes+1]=colours.specular.r;return true
end
Art.UpdateSky(api,"mars");Art.UpdateSky(api,"mars")
check(#writes==1 and writes[1]==1,"Enhanced sky calibration is applied once")
profile="redux";Art.UpdateSky(api,"mars")
check(#writes==2 and writes[2]==0,"Redux switches the sky back to native fog colour")
local frames={}
api.SetMaterialPassColors=function(name,colours,technique)
 frames[#frames+1]={name=name,colours=colours,technique=technique};return true
end
local sun={x=-.62,y=.73,z=.29}
Art.UpdateSky(api,"mars",{sun=sun,night=0,clarity=1})
local last=frames[#frames]
check(#frames==1 and last.name=="CRSKYMA.MAP" and last.technique==0,"Mars dome takes the frame state")
check(last.colours.specular.r==0 and last.colours.specular.g==sun.x and last.colours.specular.b==sun.y and last.colours.specular.a==sun.z,"specular carries the calibration flag and the sun direction")
check(last.colours.emissive.r==0 and last.colours.emissive.g==1 and last.colours.emissive.b==1,"emissive carries night, clarity and cloud cover")
Art.UpdateSky(api,"mars",{sun={x=sun.x+.0003,y=sun.y,z=sun.z},night=.001,clarity=1})
check(#frames==1,"unchanged frame state is not rewritten")
Art.UpdateSky(api,"mars",{sun=sun,night=.5,clarity=2})
check(#frames==2 and frames[2].colours.emissive.r==.5 and frames[2].colours.emissive.g==1,"night moves rewrite, clarity clamps")
profile="enhanced";Art.UpdateSky(api,"mars",{sun=sun,night=.5,clarity=1})
check(#frames==3 and frames[3].colours.specular.r==1 and frames[3].colours.specular.b==sun.y,"profile change keeps the sun direction")
Art.UpdateSky(api,"achilles",{sun=sun,night=0,clarity=1})
check(frames[#frames].name=="CRSKYAC.MAP" and frames[#frames].colours.specular.g==0,"other domes keep the plain calibration")
check(frames[3].colours.emissive.a==0 and frames[3].colours.diffuse.a==0,"Mars carries no fog bank or flash")
-- Venus: the weather's storm gloom, fog bank and lightning ride with the frame.
local n=#frames
Art.UpdateSky(api,"venus",{sun=sun,night=0,clarity=.7})
last=frames[#frames]
check(#frames==n+1 and last.name=="CRSKYVE.MAP" and last.colours.specular.g==sun.x,"Venus dome takes the frame state")
check(last.colours.emissive.g==.7 and last.colours.emissive.b==0 and last.colours.emissive.a==0 and last.colours.diffuse.a==0,"no weather is a calm deck, not the clarity")
Art.UpdateSky(api,"venus",{sun=sun,night=0,clarity=.7,weather={storm=.6,bank=.2,flash=.8,flashDir={x=.3,y=.9,z=-.1}}})
last=frames[#frames]
check(#frames==n+2 and last.colours.emissive.b==.6 and last.colours.emissive.a==.2,"emissive carries the storm gloom and the fog bank")
check(last.colours.diffuse.r==.3 and last.colours.diffuse.g==.9 and last.colours.diffuse.b==-.1 and last.colours.diffuse.a==.8,"diffuse carries the lightning direction and strength")
Art.UpdateSky(api,"venus",{sun=sun,night=0,clarity=.7,weather={storm=.6,bank=.2,flash=.8,flashDir={x=.3,y=.9,z=-.1}}})
check(#frames==n+2,"an unchanged weather frame is not rewritten")
Art.UpdateSky(api,"venus",{sun=sun,night=0,clarity=.7,weather={storm=.6,bank=.2,flash=0,flashDir={x=.3,y=.9,z=-.1}}})
last=frames[#frames]
check(#frames==n+3 and last.colours.diffuse.a==0 and last.colours.diffuse.g==1,"the flash ending is written, pointing up")
Art.UpdateSky(api,"venus",{sun=sun,night=0,clarity=.7,weather={storm=3,bank=-1,flash=0}})
last=frames[#frames]
check(last.colours.emissive.b==1 and last.colours.emissive.a==0,"weather values clamp")
hidden={}
api.SetMaterialTexture=function(material,texture) hidden[material]=texture;return true end
check(Art.InstallSky(api,"mars") and hidden["ACLOUD2.MAP"]=="cr06void.dds" and hidden["acloud.map"]=="cr06void.dds","Mars dome hides the stock cloud sprites")
local n=#frames
Art.UpdateSky(api,"mars",{sun=sun,night=.5,clarity=1})
check(#frames==n+1,"reinstalling the dome rewrites the frame state")
hidden={}
Art.HideSkySprites(api,"venus");check(next(hidden)==nil,"other domes keep the stock clouds")
-- Planetshine: the Earth's TRN entry places it; the phase scales the ambient.
local stars={Texture00="earth.map",Texture02="CREARTH.MAP",Azimuth02="90",Elevation02="0"}
-- Like the game, GetODFString also returns whether the key was found.
GetODFString=function(_,section,key,default) if section=="Stars" and stars[key] then return stars[key],true end return default,false end
local earth=Art.DetectShine({},"moon")
check(earth and math.abs(earth.x-1)<1e-9 and math.abs(earth.y)<1e-9 and math.abs(earth.z)<1e-9,"TRN azimuth 90 places the Earth along +x")
stars.Azimuth02,stars.Elevation02="150","10"
earth=Art.DetectShine({},"moon")
check(math.abs(earth.x-math.sin(math.rad(150))*math.cos(math.rad(10)))<1e-9 and math.abs(earth.y-math.sin(math.rad(10)))<1e-9 and math.abs(earth.z+math.cos(math.rad(150))*math.cos(math.rad(10)))<1e-9,"azimuth is a compass heading from sim +z, drawn with z mirrored")
stars.Azimuth02,stars.Elevation02="90","0"
Art.DetectShine({},"moon")
local function shine(sun,night)
 local f=Art.Apply("moon",{ambient={r=.2,g=.2,b=.2},sun=sun,night=night})
 return f.shine or 0,f.ambient
end
check(shine({x=1,y=0,z=0},1)==0,"an Earth beside the sun shows its night side and gives no light")
local full,lit=shine({x=-2,y=0,z=0},1)
check(math.abs(full-Art.Shine.moon.night)<1e-9 and lit.b>lit.r,"a full Earth at night gives the whole night share, blue")
local half=shine({x=0,y=1,z=0},1)
check(math.abs(half-full*0.5)<1e-9,"a half-lit Earth gives half")
check(math.abs(shine({x=-1,y=0,z=0},0)-Art.Shine.moon.day)<1e-9,"daylight keeps only the day share")
check(shine(nil,1)==0 and shine({x=0,y=0,z=0},1)==0,"no sun, no phase, no shine")
local f=Art.Apply("mars",{ambient={r=.2,g=.2,b=.2},sun={x=-1,y=0,z=0},night=1})
check(f.shine==nil,"worlds without a shining body are untouched")
stars.Texture02=nil
check(Art.DetectShine({},"moon")==nil and shine({x=-1,y=0,z=0},1)==0,"a TRN without the Earth entry gives no shine")
-- Lunar night: the mission sets the sky's sun below the horizon and the Earth
-- takes the scene light.
stars.Texture02,stars.Azimuth02,stars.Elevation02="CREARTH.MAP","90","0"
Art.DetectShine({},"moon")
local skySun=Art.SetSkySun("moon",{azimuth=270,elevation=0})
check(math.abs(skySun.x+1)<1e-9 and math.abs(skySun.y)<1e-9 and Art.SkySun.moon==skySun,"the sky sun takes the TRN heading convention")
local night=Art.NightLight("moon")
check(night and math.abs(night.direction.x+1)<1e-9 and math.abs(night.direction.y)<1e-9,"the night light travels away from the Earth")
check(math.abs(night.diffuse.b-Art.Shine.moon.light)<1e-9 and night.diffuse.r<night.diffuse.b and math.abs(night.specular.b-night.diffuse.b*0.5)<1e-9,"a full Earth lights at full strength, blue")
check(math.abs(shine(skySun,1)-Art.Shine.moon.night)<1e-9,"the sky sun drives the shine's phase")
local bounce=Art.Apply("moon",{ambient={r=.02,g=.02,b=.02},sun=skySun,night=1,bodyLight=true})
check(math.abs(bounce.shine-Art.Shine.moon.bounce)<1e-9,"an Earth that also lights the scene adds only its bounce as ambient")
Art.SetSkySun("moon",{azimuth=90,elevation=0})
check(Art.NightLight("moon").diffuse.b<1e-9,"a new Earth gives no night light")
Art.SetSkySun("moon",{azimuth=0,elevation=0})
check(math.abs(Art.NightLight("moon").diffuse.b-Art.Shine.moon.light*0.5)<1e-9,"a half Earth gives half")
check(Art.NightLight("mars")==nil,"worlds without a shining body have no night light")
local box={vectors={}}
local boxApi={SetSkyBox=function() return true end,
 GetSunDirection=function() return {x=0,y=-1,z=0} end,
 SetMaterialShaderVector=function(material,name,x,y,z) box.vectors[material]={x,y,z};return 1 end}
Art.SetSkySun("moon",{azimuth=270,elevation=-20})
Art.InstallStarBox(boxApi,"moon")
local e=box.vectors["crearth.map"]
check(e and e[1]<0 and e[2]<0 and Art.SunAnchored.moon,"the star box and the Earth take the sky sun, not the light")
check(Art.SetSkySun("moon",nil)==nil and Art.SkySun.moon==nil,"clearing the sky sun goes back to the light")
Art.InstallStarBox(boxApi,"moon")
e=box.vectors["crearth.map"]
check(math.abs(e[2]-1)<1e-9,"without a sky sun the box anchors on the light")
-- Io: Jupiter stands still where the TRN puts it; the sun circles the pole of
-- Jupiter's equator through it.
local function near(a,b,eps) return math.abs(a-b)<(eps or 1e-6) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
stars={Texture31="CRJOVIAN.MAP",Azimuth31="120",Elevation31="32"}
local jupiter=Art.DetectShine({},"io")
check(jupiter and near(jupiter.y,math.sin(math.rad(32))),"Jupiter's entry is found past index 31")
check(Art.SetOrbit("mars")==nil,"worlds without an orbit get none")
local orbit=Art.SetOrbit("io")
check(orbit and near(dot(orbit.pole,jupiter),0) and near(dot(orbit.pole,orbit.noon),0) and orbit.pole.y>0,"the pole is square to Jupiter and the noon line, and tilts up")
local atJupiter=Art.OrbitSun("io",orbit.bodyHour)
check(near(dot(atJupiter,jupiter),1,1e-9),"the sun's path runs through Jupiter")
check(near(Art.OrbitSun("io",-math.pi/2).x,1) and near(Art.OrbitSun("io",math.pi/2).x,-1),"the sun rises in the east and sets in the west")
check(Art.OrbitSun("io",0).y>0.7,"noon stands high")
-- Jupiter is to the south (render +z), so the pole points north (render -z),
-- and in render space's right-handed frame the sky turns about the south pole.
local dawn,noon=Art.OrbitSun("io",-math.pi/2),Art.OrbitSun("io",0)
local turn={x=dawn.y*noon.z-dawn.z*noon.y,y=dawn.z*noon.x-dawn.x*noon.z,z=dawn.x*noon.y-dawn.y*noon.x}
check(jupiter.z>0 and orbit.pole.z<0 and near(dot(turn,orbit.pole),-1),"the pole is north and the sky turns about it the real way")
check(near(Art.OrbitEclipse("io",atJupiter),1),"behind Jupiter the sun is gone")
check(near(Art.OrbitEclipse("io",Art.OrbitSun("io",orbit.bodyHour+math.rad(12))),0),"twelve degrees off the disc the sun is whole")
local limb=Art.OrbitEclipse("io",Art.OrbitSun("io",orbit.bodyHour+math.rad(Art.Orbits.io.radius)))
check(limb>0.3 and limb<0.7,"at the limb the sun is half hidden")
Art.SkySun.io=atJupiter
check(Art.NightLight("io").diffuse.r<1e-9,"a new Jupiter in eclipse gives no light")
Art.SkySun.io={x=-jupiter.x,y=-jupiter.y,z=-jupiter.z}
local full=Art.NightLight("io")
check(near(full.diffuse.r,Art.Shine.io.light) and full.diffuse.r>full.diffuse.b,"a full Jupiter lights warm at full strength")
local io={vectors={}}
local ioApi={SetSkyBox=function() return true end,
 SetMaterialTexture=function() return true end,
 SetMaterialShaderVector=function(material,name,x,y,z,w) io.vectors[material..":"..name]={x,y,z,w};return 1 end}
Art.SkySun.io=Art.OrbitSun("io",-1.3)
check(Art.InstallStarBox(ioApi,"io") and io.vectors["SceneManagerInstance1SkyBoxPlane5:skyOrbit"],"the Io box faces take the pole")
check(io.vectors["crganyme.map:bodyPole"] and io.vectors["CRJOVIAN.MAP:sunDirection"],"every body takes the sun and the pole")
io.vectors={}
Art.UpdateSky(ioApi,"io",{sun={x=0,y=1,z=0},night=0})
check(next(io.vectors)==nil,"an orbit world ignores a frame without its orbit")
local sun=Art.OrbitSun("io",orbit.bodyHour)
Art.UpdateSky(ioApi,"io",{orbit={sun=sun,eclipse=1,hour=orbit.bodyHour,startHour=orbit.bodyHour}})
local o=io.vectors["SceneManagerInstance1SkyBoxPlane0:skyOrbit"]
check(o and near(o[4],0),"in eclipse the box hides the sun")
local spin=io.vectors["CRJOVIAN.MAP:bodySpin"]
check(spin and near(spin[1],Art.Orbits.io.spinStart%(2*math.pi)) and near(spin[3],Art.Orbits.io.spinLook[1]),"Jupiter starts at its start longitude")
check(io.vectors["crcallis.map:bodySpin"]==nil,"only Jupiter turns")
io.vectors={}
Art.UpdateSky(ioApi,"io",{orbit={sun=sun,eclipse=1,hour=orbit.bodyHour+1e-5,startHour=orbit.bodyHour}})
check(next(io.vectors)==nil,"a sun that has not moved is not rewritten")
Art.UpdateSky(ioApi,"io",{orbit={sun=Art.OrbitSun("io",orbit.bodyHour+0.01),eclipse=0.4,hour=orbit.bodyHour+0.01,startHour=orbit.bodyHour}})
spin=io.vectors["CRJOVIAN.MAP:bodySpin"]
check(spin and near(spin[1],(Art.Orbits.io.spinStart-Art.Orbits.io.spinTurns*0.01)%(2*math.pi)),"Jupiter turns spinTurns times as fast as the sun")
check(near(io.vectors["SceneManagerInstance1SkyBoxPlane3:skyOrbit"][4],0.6),"a partial eclipse dims the sun")
-- Europa: the same machinery one moon out, with misn12's Jupiter.
stars={Texture00="crjovian.map",Azimuth00="210",Elevation00="35",Texture01="crio.map",Azimuth01="172",Elevation01="40"}
local euJupiter=Art.DetectShine({},"europa")
check(euJupiter and near(euJupiter.y,math.sin(math.rad(35))),"Europa finds its Jupiter")
local euOrbit=Art.SetOrbit("europa")
check(euOrbit and near(dot(euOrbit.pole,euJupiter),0) and euOrbit.pole.y>0,"Europa's pole is square to Jupiter and tilts up")
local ioDir={x=math.sin(math.rad(172))*math.cos(math.rad(40)),y=math.sin(math.rad(40)),z=-math.cos(math.rad(172))*math.cos(math.rad(40))}
check(math.abs(dot(ioDir,euOrbit.pole))<math.sin(math.rad(1.5)),"Io sits on Jupiter's equator, within 1.5 degrees")
check(math.deg(math.acos(dot(ioDir,euJupiter)))<38.9,"Io stays inside its greatest elongation from Europa")
check(Art.Orbits.europa.radius<Art.Orbits.io.radius,"Jupiter is smaller from Europa than from Io")
local euAt=Art.OrbitSun("europa",euOrbit.bodyHour)
check(near(Art.OrbitEclipse("europa",euAt),1),"behind Jupiter Europa's sun is gone")
check(near(Art.OrbitEclipse("europa",Art.OrbitSun("europa",euOrbit.bodyHour+math.rad(8))),0),"eight degrees off Europa's Jupiter the sun is whole")
Art.SkySun.europa={x=-euJupiter.x,y=-euJupiter.y,z=-euJupiter.z}
local euFull=Art.NightLight("europa")
check(euFull and euFull.diffuse.r<full.diffuse.r and euFull.diffuse.r>euFull.diffuse.b,"a full Jupiter lights Europa warm, weaker than Io")
local eu={vectors={},box=nil}
local euApi={SetSkyBox=function(material) eu.box=material;return true end,
 SetMaterialTexture=function() return true end,
 SetMaterialShaderVector=function(material,name,x,y,z,w) eu.vectors[material..":"..name]={x,y,z,w};return 1 end}
Art.SkySun.europa=Art.OrbitSun("europa",-0.7)
check(Art.InstallStarBox(euApi,"europa") and eu.box=="CR_Sky/EuropaStars","Europa installs its own star box")
check(eu.vectors["crio.map:bodyPole"] and eu.vectors["CRJOVIAN.MAP:sunDirection"],"Io and Jupiter take Europa's sun and pole")
-- Titan: the haze ladder and roll take the weather slots, and the dome draws
-- Saturn itself, so it takes Saturn's TRN direction and hides the quad.
stars={Texture00="SATURN.MAP",Azimuth00="180",Elevation00="15"}
local saturn=Art.DetectShine({},"titan")
check(saturn and near(saturn.x,0) and near(saturn.y,math.sin(math.rad(15))) and near(saturn.z,math.cos(math.rad(15))),"Saturn at heading 180 stands at render +z")
frames={}
Art.UpdateSky(api,"titan",{sun=sun,night=0,clarity=.8,weather={storm=.4,bank=.7}})
last=frames[#frames]
check(#frames==1 and last.name=="CRSKYTI.MAP" and last.colours.specular.g==sun.x,"Titan dome takes the frame state")
check(last.colours.emissive.g==.8 and last.colours.emissive.b==.4 and last.colours.emissive.a==.7,"emissive carries the haze and the roll")
check(last.colours.ambient and near(last.colours.ambient.b,saturn.z) and last.colours.ambient.a==1,"ambient carries Saturn's direction")
Art.UpdateSky(api,"titan",{sun=sun,night=0,clarity=.8,weather={storm=.4,bank=.7}})
check(#frames==1,"an unchanged Titan frame is not rewritten")
Art.UpdateSky(api,"mars",{sun=sun,night=.2,clarity=1})
check(frames[#frames].colours.ambient==nil,"domes without a body leave ambient alone")
stars={}
Art.DetectShine({},"titan");Art.SkyFrameState["CRSKYTI.MAP"]=nil
Art.UpdateSky(api,"titan",{sun=sun,night=0,clarity=.8})
check(frames[#frames].colours.ambient.a==0,"a map without Saturn draws none")
hidden={}
api.SetSkyDome=function(material) return material=="CRSKYTI.MAP" end
check(Art.InstallSky(api,"titan") and hidden["SATURN.MAP"]=="cr06void.dds" and hidden["acloud2.map"]=="cr06void.dds" and hidden["STARS.MAP"]=="cr06void.dds","Titan dome hides the Saturn quad, the cloud sprites and the stars")
-- Saturn lights a Titan night: none by day, nearly full opposite the sun.
check(Art.Shine.titan.day==0,"the day haze hides Saturn's light")
stars={Texture00="saturn.map",Azimuth00="180",Elevation00="15"}
Art.DetectShine({},"titan")
Art.SetSkySun("titan",{azimuth=20,elevation=-25})
local ti=Art.NightLight("titan")
check(ti and ti.diffuse.r>Art.Shine.titan.light*0.95 and ti.diffuse.r>ti.diffuse.b and near(ti.direction.z,-saturn.z),"misn15's night sun leaves Saturn nearly full, lighting warm from Saturn")
Art.SetSkySun("titan",nil)
print("World art lighting: "..count.." checks passed")
