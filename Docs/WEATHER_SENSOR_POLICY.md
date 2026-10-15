# Shared weather sensor policy

Owner decision, 15 October 2026: every weather-enabled campaign mission should
have sensor effects, including Titan. This supersedes the visual-only mission
exceptions recorded in the earlier atmosphere audit. The visual planet directors
can still be used alone without gameplay effects; campaign missions explicitly
connect their weather activity to Environment's sensor service.

## Mission policy

| Missions | Weather sensor input | Lighting/night policy |
| --- | --- | --- |
| Moon 02b/03 | Synced dust/glow activity times smoothed dust density (capped at 1) | Existing subtle sun variation; no artificial full night penalty. |
| Mars 04/05/06 | Existing Plains/Volcano radar-range and velocity-jam ladder | Existing full day/night sensor coefficients, now also enabled on 06. |
| Venus 07–09 | Existing storm ladder plus local lightning scramble | Existing subtle lighting, no full night penalty. |
| Io 10/11 | Normalized director severity | Existing full night coefficients. |
| Europa 12/13 | Normalized director severity | Existing full night coefficients. This now affects craft sensors during the stealth mission too. |
| Titan 14 | Normalized four-rung director severity | Environment with captured native baseline; Titan remains daylight-locked. |

Clear/bottom-rung conditions give radar range x1 and velocity jamming x1.
For the newly bound Moon/Io/Europa/Titan sources, normalized activity 0..1
linearly selects range x1..0.55 and jamming x1..1.40. Half activity therefore
gives x0.775 range and x1.20 jamming. Moon quality settings and camera-local
particle counts never enter the sensor calculation. Quiet Moon dust/glow has
no penalty; an active dust/glow period can degrade sensors.

Mars and Venus retain their existing tuned curves and Venus lightning behavior;
they already contribute through RegisterGameplayModifier. They do not bind an
additional weather modifier, so the penalty is not applied twice. Mars 06
enables the same existing sensor ladder as 04/05 and removes its night-gameplay
opt-out. Its wind push stays off: this decision concerns sensors, not handling.

Actual night still composes with weather through Environment's existing night
coefficients (range x0.70, sweep period x2, jamming x1.50 at full night). Subtle
daylight variation has nightBlend=0, so moving the sun slightly never creates a
night sensor penalty. Titan's existing daylight lock likewise remains active.

## Ownership and restoration

Environment is the only sensor writer. Missions use
`Environment.BindWeatherSensors(name, director)` for the newly covered planets;
the provider reads GetSeverity (or Moon GetGlow and DensityValue), contributes
scales and never changes native state itself. Rebinding after load replaces the
named modifier, rather than multiplying another copy into the frame.

The service samples at simulation-time intervals and uses the existing batched
craft pass. Player and AI craft receive the same policy. In co-op each peer only
changes locally owned craft; replicas are skipped. Host-controlled/seeded weather
already supplies the director state on each peer. No local graphics option is
allowed to affect the sensor severity.

Original sensor values are captured once and restoration always uses those
values, so repeated updates cannot compound degradation. Clear conditions,
disabled/shutdown directors and fault-disabled Titan directors return identity
scales and restore the captured values. Weather only changes range and velocity
jamming; it does not rewrite the radar sweep period. Ending actual night restores
the sweep once even if weather continues, avoiding a repeated sweep restart.

Titan 14 now initializes Environment before CRTitanWeather, captures the native
fog/light/sun baseline, and updates Environment after the director on every peer.
CRWeather therefore contributes through the same single-writer lane as the other
campaign missions. No additional sky, fog layer, particles or night cycle is
introduced. Native baseline capture and the existing Titan presets remain the
visual inputs. Existing save/load invalidation and weather state reconstruction
continue to apply.

Missions with no weather integration (later faithful ports, Soviet/Black Dog
scripts and the setup utility) are not silently given a director by this policy.
The policy covers every currently weather-enabled mission, 02b through 14.

## Validation and remaining checks

Tools/Test-WeatherSensors.lua executes the real Environment with the real planet
severity/glow getters. It checks clear/half/full severity, player and AI ownership,
co-op replica isolation, quality independence, disabled/shutdown/fault recovery,
noncompounding baselines, night composition and sweep restoration. The existing
Mars/Venus director suites protect their tuned behavior. Mission fixtures assert
Moon/Titan bindings and Mars 06 settings; source parity and Lua 5.1 checks remain.
The new regression runs in campaign CI.

These are host-side tests. Native radar behavior, Titan visual equivalence after
joining Environment, and balance/detection on Europa 12 require a live playtest.
This intentionally changes gameplay visibility/detection; it does not alter
mission stealth objectives, team/perceived-team logic, damage, or timers.
