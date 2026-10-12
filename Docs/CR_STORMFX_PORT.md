# CRStormFX port of the ISDF Chronicles weather stack

Source: ISDF Chronicles (ISDFC) at commit `0775645a1bcc7295fecdbac809f7e97cd1685759`
(`addon\ISDF Chronicles`, flat layout). All new names are `CR`/`crwx` prefixed so CR and ISDFC
can be loaded together without Ogre name collisions. Nothing here creates a Lua global and no
BZ API is called at require time.

## File mapping

| ISDFC | CR |
| --- | --- |
| `precip.lua` | `Scripts/CRPrecip.lua` |
| `isdfcsplash.lua` | `Scripts/CRSplash.lua` |
| `isdfclava.lua` | `Scripts/CRGroundFX.lua` |
| `effects.lua` (weather subset) | `Scripts/CRStormFX.lua` |
| `isdfc_precip.particle` (`ISDFC/*`) | `Materials/crwx_precip.particle.payload` (`CRWX/*`); listed in `CRParticleTemplates` `names` as `crwx_precip` |
| `isdfc_precip.material` (`ISDFC_FX/*`) | `Materials/crwx_precip.material` (`CRWX_FX/*`) |
| `isdfc_precip.program` | `Shaders/crwx_precip.program` (`CRWX_OgreParticle_*`; SM3 delegate `CR_Effect_vertexHLSL`) |
| `isdfc_ogre_particle-sm4.hlsl`, `-vertex.glsl` | `Shaders/crwx_ogre_particle-sm4.hlsl`, `crwx_ogre_particle-vertex.glsl` |
| `isdfc_fixedfunc.program` (2 of its programs) | `Shaders/crwx_fixedfunc.program` (`CRWX_FF_LitFlat2_vertex`, `CRWX_FF_ModAlphaBlend_NoFog_fragment`) |
| `isdfc_fixedfunc-sm4.hlsl` | `Shaders/crwx_fixedfunc-sm4.hlsl` |
| `isdfc_precip_{flake,mist,mote,streak}.png` | `Assets/Textures/crwx_precip_*.png` |
| `isdfc_splash_ripple.png`, `isdfc_fx_glow.png`, `isdfc_bootprint.png` | `Assets/Textures/crwx_splash_ripple.png`, `crwx_fx_glow.png`, `crwx_bootprint.png` |
| `wsplat.dds` | `Assets/Textures/crwx_wsplat.dds` (`Materials/wsplat.material` aliases it) |

## Public API

All modules degrade silently (return false/nil) when EXU is missing, is a stub (`isStub`), or lacks
particle support. Particle templates are loaded through `require("CRParticleTemplates").Ensure()`.

### CRStormFX (weather subset of effects.lua)
- `Update()` - per frame: flushes CRPrecip/CRSplash/CRGroundFX, steps the director if started, otherwise plays out hand-fired strikes and the flash once the environment is captured.
- `Shutdown()` - stops rain/acid/snow/dust, splash and strike particles, the rain loop, pending strikes and the director; restores the captured fog/ambient/sun once (no-op if nothing was written).
- `Rain(i)`, `AcidRain()`, `Lightning(perMinute, palette)`, `StrikeNow(cloudOnly, palette)`, `Atmosphere(fogScale, lightScale)`, `RainAndBolt("Light"|"Medium"|"Heavy")`.
- `StartDynamicWeather(saved, options)`, `UpdateDynamicWeather()`, `SetWeather(name, seconds)`, `GetWeather()`, `GetRainIntensity()`, `SeedRandom(n)` (tests).
- `Precip(kind, level)`, `Wind(x, z, speed)` - passthroughs to CRPrecip (and Wind also to CRSplash).
- `BaseEnvironment()` - the captured `{fog, amb, sun}` table or nil.
- The TRN lookup (FogEnd, VisibilityRange, world kind for the lightning palette) is lazy.

### CRPrecip
`Set(kind, level)` for `rain|acid|snow|dust` (true while particles draw it), `SetWind(x, z, speed)`, `Available()`.
Added: `Update()` (apply last frame's requests so unrequested kinds fade) and `Stop()` (destroy the systems).

### CRSplash
`Set(kind, level)` for `rain|acid|dust`, `SetWind(x, z, speed)`, `WetLevel()`, `Update()`.
Added: `Stop()` (destroy the systems).

### CRGroundFX
`Event(kind, pos, scale)` (`lava|toxic|stepdust|stepwet|strike|radiation|print00..15`), `SetColour(kind, r, g, b, a, key)`,
`Capacity(kind)`, `Print(pos, normal, heading, r, g, b, a, fade)`, `Bolt(x, ground, z, r, g, b)`, `BoltStroke()`, `Update()`.
Added: `Stop()` (destroy all systems).

## Dropped from effects.lua, and why

- Footprints/bootprints, `bootprint`, soil table: pilot gameplay cosmetics, not weather. (CRGroundFX still offers `Print`/`stepdust`/`stepwet`; the textures and templates ship.)
- Radiation, RandomEarthquakes, RandomAmbientTones, BubblingLava, BubblingAcid: separate hazards/ambience, not weather.
- Wetglass: out of scope; `wetglass` is a nil upvalue and the guarded calls remain.
- The load-time globals (`filename`, `odf`, `texture_type0_solidA0`, `world_variable`) and bare global functions; replaced by a lazy local TRN lookup and module fields.

## Asset decisions

Stock was checked against `BZ_ASSETS`, `BZ_ASSETS_CORE`, `StockODFFiles` and the contents of `bzone.zfs`/`bzone_en.zfs`;
CR against `Assets`, `ODF`, `Materials`, `Shaders`, `Scripts`. None of the leaves below exist in either (no collisions, no renames beyond the `crwx` set).
Stock sprite materials `grndchar.tga` and `lightflare.tga` (BZ2Render.material) are reused; the ODFs' `spark2.tga` and `smokeb2.tga` need the copied materials.

| Leaf | Decision |
| --- | --- |
| `xbolt{w,y}{1-4}.odf`, `xbsky{w,y}.odf`, `xbgnd{w,y}.odf`, `xbgnd{w,y}l.odf` | (c) copied to `ODF/` |
| `xpuddle`, `xrain`, `xraindr`, `xrainsp`, `xraina`, `xraindra`, `xrainspa` `.odf` | (c) copied to `ODF/` |
| `xlitbl{1,2,4}h.odf` | (c) copied to `ODF/` (light twins for CRWeather's bolt lights; not used by CRStormFX itself) |
| `erain01.wav`, `erain02.wav`, `thunder.wav`, `thund02.wav`, `xlitblt1.wav`, `xlitblt2.wav`, `xlitblt3.wav`, `atlas.wav` | (c) copied to `Assets/Sounds/` |
| `lbolt.material` ... `lbolt4.material`, `lbolt*.dds` | (c) copied (textures of the xbolt* sprites) |
| `spark2.material`, `spark2.dds`, `smokeb2.material`, `smoke2.dds` | (c) copied (xbgnd* sprite fallback) |
| `xrain.material`, `acidrain.material` (programs renamed `CRWX_FF_*`), `xrain.dds`, `xrainmask.dds`, `raintoxc.dds`, `raintoxc_mask.dds` | (c) copied (rain sheet fallback) |
| `xraindr.material`, `xrainsp.material`, `xraindr.png`, `xrainsp.png` | (c) copied (splash fallback) |
| `wsplat.material` | (c) copied but repointed at `crwx_wsplat.dds` so the texture ships once |
| `wsplat.dds` | not in CR or stock: shipped as `crwx_wsplat.dds` |
| `sprites.material` | not copied: CR already has it (provides `BZSprite/AlphaBlend`, `BZSprite/Additive`) |

Open point: the copied ODF and material names are the same as ISDFC's (identical content except `wsplat.material`,
`xrain.material`, `acidrain.material`). Loading both mods defines those materials twice.
