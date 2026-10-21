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
print("World art lighting: "..count.." checks passed")
