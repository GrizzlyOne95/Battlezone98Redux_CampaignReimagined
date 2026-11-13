-- Execute the real Environment sensor service with real planet severity
-- getters. Directors remain render-only; missions bind their activity here.
local checks=0
local function check(ok,why) assert(ok,why); checks=checks+1 end
local function near(a,b) return math.abs(a-b)<0.00001 end
local function peer(network, owner)
    local p={time=0,writes={},sensors={},periodWrites=0}
    for h=1,3 do p.sensors[h]={range=500,period=2,jam=10} end
    local e=setmetatable({}, {__index=_G});e._G=e
    e.print=function() end
    e.GetTime=function() return p.time end
    e.IsValid=function(h) return p.sensors[h]~=nil end
    e.IsCraft=e.IsValid
    e.IsNetGame=function() return network end
    e.IsLocal=function(h) return h==owner end
    e.AllCraft=function() local h=0;return function() h=h+1;if h<=3 then return h end end end
    e.SetVector=function(x,y,z) return {x=x,y=y,z=z} end
    e.GetMapTRNFilename=function() return 'test.trn' end
    e.OpenODF=function() return {} end
    e.GetODFInt=function(_,_,_,d) return d end
    e.GetODFFloat=e.GetODFInt; e.GetODFString=e.GetODFInt
    local exu={GetRadarRange=function(h) return p.sensors[h].range end,
        GetRadarPeriod=function(h) return p.sensors[h].period end,
        GetVelocJam=function(h) return p.sensors[h].jam end}
    local fields={SetRadarRange='range',SetRadarPeriod='period',SetVelocJam='jam'}
    for name,field in pairs(fields) do
        local n,k=name,field
        exu[n]=function(h,value)
            check(not network or h==owner,'a peer changed remote craft sensors')
            p.writes[h]=true;p.sensors[h][k]=value
            if n=='SetRadarPeriod' then p.periodWrites=p.periodWrites+1 end
        end
    end
    local modules={exu=exu,RuntimeEnhancements={Initialize=function() end,Update=function() end}}
    e.require=function(name)
        if not modules[name] then modules[name]=setfenv(assert(loadfile('Scripts/'..name..'.lua')),e)() end
        return modules[name]
    end
    p.E=e.require('Environment'); p.E.EnableSunLighting=false; p.E.EnableVisualRuntime=false
    p.E.Init({lightingMode='subtle'})
    p.load=e.require
    function p:tick() self.time=self.time+1.1;self.E.Update(0.1) end
    return p
end

for _,row in ipairs({{'Io','CRIoWeather',5},{'Europa','CREuropaWeather',5},{'Titan','CRTitanWeather',4}}) do
    local p=peer(false,1);local d=p.load(row[2])
    d.Initialized=true;d.Enabled=true;d.LevelValue=1
    p.E.BindWeatherSensors(row[1],d)
    p:tick();check(next(p.writes)==nil,row[1]..' clear starts at native sensors')
    d.LevelValue=row[3];p:tick()
    check(near(p.E.GameplayScales.radarRange,0.55),row[1]..' maximum weather uses common range scale')
    for h=1,3 do
        check(near(p.sensors[h].range,275) and near(p.sensors[h].jam,14),row[1]..' affects player and AI equally')
        check(near(p.sensors[h].period,2),row[1]..' leaves radar sweep unchanged')
    end
    check(p.periodWrites==0,row[1]..' does not repeatedly restart the radar sweep')
    -- Rebinding after Load must replace the modifier, not multiply it twice.
    p.E.BindWeatherSensors(row[1],d);p:tick()
    check(near(p.sensors[1].range,275),row[1]..' binding and polling do not compound baselines')
    d.LevelValue=(row[3]+1)/2;p:tick()
    check(near(p.sensors[1].range,387.5),row[1]..' intermediate severity interpolates smoothly')
    d.Enabled=false;p:tick()
    check(near(p.sensors[1].range,500) and near(p.sensors[1].jam,10),row[1]..' disabled weather restores stock sensors')
    d.Enabled=true;d.LevelValue=row[3];p:tick();d.Initialized=false;p:tick()
    check(near(p.sensors[1].range,500),row[1]..' shutdown restores stock sensors')
    check(p.E.OriginalRadarRanges[1]==nil and p.E.OriginalVelocJams[1]==nil,row[1]..' releases captured baselines')
    d.Initialized=true;d.Disabled=true;p:tick()
    check(near(p.sensors[1].range,500),row[1]..' fault-disabled director contributes no penalty')
end

local p=peer(false,1);local moon=p.load('CRMoonWeather')
moon.Initialized=true;moon.Enabled=true;moon.GlowLevel=0;moon.DensityValue=1
p.E.BindWeatherSensors('Moon',moon);p:tick()
check(next(p.writes)==nil,'Moon has no penalty at quiet dust/glow')
moon.GlowLevel=1;p:tick()
check(near(p.sensors[1].range,275),'Moon active dust/glow uses shared policy')
moon.Quality=0;p:tick()
check(near(p.sensors[1].range,275),'graphics quality cannot bypass Moon sensor effects')
moon.DensityValue=0;p:tick()
check(near(p.sensors[1].range,500),'no Moon dust restores sensors')
moon.GlowLevel=0;moon.DensityValue=1;p:tick()
check(p.E.NightBlend==0 and near(p.sensors[1].range,500),'subtle sun drift alone adds no sensor penalty')

-- Each peer applies the same weather policy only to the simulation it owns.
for owner=1,3 do
    local p=peer(true,owner);local d=p.load('CRTitanWeather')
    d.Initialized=true;d.Enabled=true;d.LevelValue=4
    p.E.BindWeatherSensors('Titan',d);p:tick()
    check(near(p.sensors[owner].range,275),'local human/AI owner receives Titan weather penalty')
    for h=1,3 do if h~=owner then check(near(p.sensors[h].range,500),'remote baseline untouched') end end
end

-- Existing full night remains a separate, composable modifier. Storm severity
-- must not become a second native writer or erase the night coefficient.
p=peer(false,1);local d=p.load('CREuropaWeather');d.Initialized=true;d.Enabled=true;d.LevelValue=5
p.E.BindWeatherSensors('Europa',d);p.E.LightingMode='cycle';p.time=700;p.E.Update(0.1)
check(near(p.sensors[1].range,500*0.55*0.70),'weather and actual night compose from original baseline')
check(near(p.sensors[1].period,4),'actual night retains its existing sweep period effect')
p.E.LightingMode='subtle';p:tick()
check(near(p.sensors[1].period,2),'ending night restores sweep even while weather continues')
local writes=p.periodWrites;p:tick()
check(p.periodWrites==writes,'restored sweep is no longer rewritten under weather')
d.LevelValue=1;p:tick()
check(near(p.sensors[1].range,500) and near(p.sensors[1].jam,10),'ending all conditions restores native values')
print('Shared weather sensors passed: '..checks..' checks (real planet getters, ownership, restore, composition).')
