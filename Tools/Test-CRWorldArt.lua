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
check(Art.InstallSky(api,"moon") and #boxes==2,"star box can be reinstalled after a cinematic")
api.SetSkyBox,api.SetMaterialTexture,api.GetCameraClipDistances=nil,nil,nil
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
Art.UpdateSky(api,"venus",{sun=sun,night=0,clarity=1})
check(frames[#frames].name=="CRSKYVE.MAP" and frames[#frames].colours.specular.g==0,"other domes keep the plain calibration")
hidden={}
api.SetMaterialTexture=function(material,texture) hidden[material]=texture;return true end
check(Art.InstallSky(api,"mars") and hidden["ACLOUD2.MAP"]=="cr06void.dds" and hidden["acloud.map"]=="cr06void.dds","Mars dome hides the stock cloud sprites")
local n=#frames
Art.UpdateSky(api,"mars",{sun=sun,night=.5,clarity=1})
check(#frames==n+1,"reinstalling the dome rewrites the frame state")
hidden={}
Art.HideSkySprites(api,"venus");check(next(hidden)==nil,"other domes keep the stock clouds")
print("World art lighting: "..count.." checks passed")
