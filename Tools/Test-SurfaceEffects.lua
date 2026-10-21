-- Lua 5.1 host regression: bounded scheduling, callback chaining and ownership.
local E, objects, uniforms, clones = {}, {}, {}, {}
local calls, wet, view, previousHits = 0, 0, 1, 0
local rejectShared,sharedCalls=false,0
for h=1,100 do objects[h]={material="metal",health=1,class="tank",powered=true} end
objects[2].class="turret"
package.loaded.exu=E
package.loaded.CRWeather={GetSurfaceWetness=function() return wet end}
function IsValid(h) return objects[h]~=nil end
function GetPlayerHandle() return 1 end
function IsCraft() return true end
function GetClassLabel(h) return objects[h].class end
function GetHealth(h) return objects[h].health end
function GetDistance() return 10 end
function SetVector(x,y,z) return {x=x,y=y,z=z} end
function AllObjects() error("Unexpected world scan") end
local function obj(t) return objects[type(t)=="table" and t.handle or t] end
function E.GetSubEntityCount() calls=calls+1;return 1 end
function E.GetSubEntityMaterial(t) calls=calls+1; return type(t)=="table" and (obj(t).cockpit or "panel") or obj(t).material end
function E.SetSubEntityMaterial(t,_,name) if type(t)=="table" then obj(t).cockpit=name else obj(t).material=name end return true end
E.SetSurfaceMaterial=E.SetSubEntityMaterial
function E.CloneSurfaceMaterial(source,name) clones[name]=source;return true end
function E.ReleaseSurfaceMaterial(name) clones[name]=nil;return true end
function E.SetSurfaceTexture(name,alias,texture) uniforms[name..alias]=texture;return 1 end
function E.SetMaterialShaderVector(name,key,...) calls=calls+1;if name=="metal" then sharedCalls=sharedCalls+1;if rejectShared then return 0 end end;uniforms[name..key]={...};return 1 end
function E.EntityLocalPoint(_,p) return p end
function E.GetWeaponMuzzlePosition(_,slot) calls=calls+1; if slot==0 then return SetVector(0,0,0) end end
function E.IsGunTowerPowered(h) return objects[h].powered end
function E.GetCameraView() return view end
function E.GetSatState() return 0 end
function E.SetReactiveChunksEnabled(v) E.chunks=v end
E.BulletHit=function() previousHits=previousHits+1 end
local S=assert(loadfile("Scripts/CRSurfaceEffects.lua"))()
for h=1,100 do S.Register(h) end
local function ticks(n) for _=1,n do S.Update(0.05) end end
ticks(40)
assert(E.chunks and S.cockpit,"controller/cockpit activation")
objects[1].health=.25;ticks(30)
assert(S.cockpit.damage>.7,"cockpit tracks hull")
objects[1].health=1;ticks(40)
assert(S.cockpit.damage<.001,"repair recovers cockpit")
local p=SetVector(0,0,0)
calls=0
for _=1,1000 do E.BulletHit("bullet",3,1,p);E.BulletInit("bullet",1,p) end
assert(calls==0 and previousHits==1000,"callbacks must only queue and chain")
assert(#S.hits==64 and #S.shots==64,"event caps")
S.Update(.001);assert(calls==0,"no material work between ticks")
ticks(1)
assert(#S.hits==62 and #S.shots==62,"bounded event drain")
assert(#S.records[1].marks==2 and next(S.records[1].heat),"localized hit/heat")
ticks(8)
assert(S.records[1].heat[0].display>0,"smooth heat accumulates")
assert(#S.records[1].slots>0,"a permanent tower must not starve a later combat material binding")
ticks(400)
assert(not next(S.records[1].heat) and #S.records[1].marks==0,"heat and marks retire")
objects[2].powered=false;ticks(40)
assert(string.find(objects[2].material,"_off",1,true),"tower power-off variant")
assert(uniforms[objects[2].material.."EmissiveMap"]=="black.png","glow also disabled")
objects[2].powered=true;ticks(40)
assert(not string.find(objects[2].material,"_off",1,true),"power recovery")
wet=1;ticks(200);assert(S.Wetness>.97,"rain wets gradually")
wet=0;ticks(1000);assert(S.Wetness<.01,"drying")
-- A missing/late-compiled shared shader must not be cached as a successful
-- wet update, and retries must back off instead of walking its passes at 20Hz.
rejectShared=true;S.materials.metal.wet=nil;sharedCalls=0;ticks(20)
assert(S.materials.metal.wet==nil and sharedCalls==1,"unsupported shared shader backs off")
rejectShared=false;ticks(60)
assert(S.materials.metal.wet~=nil,"late shared shader recovers")
-- External material owner wins even during teardown.
objects[2].material="external_team_material"
S.Shutdown()
assert(objects[2].material=="external_team_material","restore only own binding")
assert(not next(clones) and not E.chunks,"release all owned resources")
assert(E.BulletHit~=S.hitWrapper,"restore callbacks")
-- Old runtimes: complete no-op, including registration and callbacks.
E.CloneSurfaceMaterial=nil;S.Register(1);S.Update(.1)
assert(not S.records[1] and not S.started,"unsupported runtime fails closed")
print("SurfaceEffects: scheduling, damage, repair, heat, rain, power, ownership PASS")
