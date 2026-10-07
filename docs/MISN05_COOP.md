# Mission 05 offline and co-op

An Unexpected Connection shares `misn05.bzn` / `misn05.lua` between campaign
`MISSION4` and the strategy listing `CR: An Unexpected Connection Coop`.
Use matching CR, EXU and OpenShim builds. Host on team 1, with guests on
distinct teams 2–4; select an NSDF tank or scout and start together.
Late join/rejoin requires a restart. Host departure ends the mission.

## Mission ownership

Montana and the armory remain on team 1. Four native spawn buoys place the
players beside the authored start, and EXU suppresses extra starting recyclers.
CCA uses team 5, the 23 clearable mines use team 6, and the seven-tank friendly
ending fleet uses team 7. These reservations apply offline as well.

Only the campaign leader runs AI, spawns, orders, timers and victory/loss gates.
Either player can discover Lemnos. The host delivers starting resources to
each owning team, plus objectives, dialogue, markers, weather cues and results
through the existing ordered, acknowledged presentation protocol.
Object-camera snapshots wait for native replicas and permit local skipping.
The four-second discovery film, ten-second closing film and fifteen-second
commander reveal delay continue for the shared mission when a player skips.
The closing shot uses centimeter offsets for a view 25 m beside, 18 m above
and 85 m behind the lead tank.

Weather visuals run locally; the host selects the weather rung and set piece.
Online wind-push gravity is disabled. Recoil, shake and impact velocity writes
apply only to locally owned objects in multiplayer; offline physics remains.
Human deaths use the existing five-life service. Fallback rallies are the
Montana in phase 1 and Lemnos after discovery (see COOP_RESPAWN.md).
Native MultST consumes the team-start buoys, so they cannot serve as rallies.
The respawn adapter resolves object labels through `GetHandle` before reading
their positions; genuine path names retain `GetPosition(path)` behavior.

The authored deployment, randomized wave order, defense orders, reinforcement
waves, surviving-attacker victory gate and both failure debriefs remain.
Single-player save/load code and the inactive original-source ledger remain.

## Focused checks

```sh
lua5.1 Tools/Test-EarlyMissionFlow.lua
lua5.1 Tools/Test-Misn05Presentation.lua
lua5.1 Tools/Test-PhysicsImpactOwnership.lua
lua5.1 Tools/Test-CRCoop.lua
lua5.1 Tools/Test-CRCoopRally.lua
lua5.1 Tests/test_coop_respawn.lua
lua5.1 Tools/Test-CRMarsWeather.lua
python Tools/Test-Misn05CoopContract.py
python Tools/Test-EarlyMissionSourceAudit.py
python Tools/Validate-CampaignRepository.py
```

The Lua 5.1 flow suite passes 117 checks, the presentation adapter passes 15
four-peer camera/event checks, and the source audit passes 501 checks. The
adapter covers delayed replicas, packet loss/reordering, independent skips,
stale snapshots and a result held until preceding events are acknowledged.
These mocks do not qualify native wire serialization, physics or pathfinding.
Mission 02–04 complete-script regressions also pass (14,975 / 7,842 / 34,483
checks); their fixtures now load the current respawn dependency and keep the
EXU module state separate for each simulated peer.
The repository validator passes. `Test-SetupMissionShell.py` still fails its
unrelated setup-vs-misn02b serialization comparison at line 113; the original
HEAD test with the original misn05 BZN fails the same assertion.

## Live evidence (Windows GOG, 2026-10-07)

Two real clients use BZR-OpenShim-coopflow's private loopback server and a
generated `misn05-coop` content override. Scenarios use owner-local teleport,
healing, enemy removal and accelerated timers, so they verify mission flow
and replication rather than combat balance. The camera checks cancellation
after `CameraObject`, matching the authored order. The harness now honors
posted-key hold duration; the final skip check holds Space for 400 ms. Real
focused input is optional (`FocusedSkip=1`) and requires an unlocked desktop.

| Case | Evidence under `C:\BZRCoop\runs` | Result |
|---|---|---|
| Full win, guest skip, final camera/input adapter | `cr-misn05-win-20261007-161218` | 14 steps / 9 checks |
| Full win, host skip, final camera/input adapter | `cr-misn05-win-20261007-161522` | 14 steps / 9 checks |
| Natural films and final camera framing | `cr-misn05-win-Overridemisn05-coop-Skippernone-20261007-154157` | 13 steps / 9 checks |
| Lemnos destruction | `cr-misn05-lose-Overridemisn05-coop-Destroyedfactory-20261007-154157` | 4 steps / 9 checks |
| Montana destruction | `cr-misn05-lose-Overridemisn05-coop-Destroyedrecycler-20261007-154157` | 4 steps / 9 checks |
| Respawn, phase rally position, life exhaustion | `cr-misn05-coop-respawn-20261007-160725` | 9 steps / 6 checks |
| Host departure | `cr-misn05-host-leaves-Overridemisn05-coop-20261007-154157` | 8 steps / 7 checks |

All listed runs pass with no Lua or engine script errors. The guest and host
agree on the corrected Lemnos fallback (about 36 m from the factory). The
original respawn scenario only checked the word `rally`; log review exposed
placement at the map origin. The tightened scenario verifies real positions
on both clients and checks that both persistent rally labels exist.

The RDP session disconnected during later tests: audio-unavailable warnings
remain in the final win and respawn evidence. Earlier runs had audio available.
One retry exited in the lobby with a native audio-stack access violation before
mission load; another real-input retry could not take desktop focus. These
attempts are retained as failures in `suite-20261007-160215`.

Stock multiplayer destruction messages are still visible. Their separate
OpenShim/EXU suppression design remains unimplemented (`COOP_MESSAGE_SUPPRESSION.md`
in the harness repository); alliance locking does not suppress the kill feed.

Offline live save/reload, three/four-player live sessions, Steam and Wine/Proton
remain unverified. The shipping manager's Windows `-bless` output was reviewed:
only the four new lobby assets and required `CRCoopRespawn.lua` membership were
admitted, retaining all prior entries. No Workshop publication is part of this
change.
