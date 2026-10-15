# Co-op DX11 recovery, 15 October 2026

This work is based on CR `origin/main` at `e6c591fb` on
`agent/coop-validation-20261015`. No open CR PR overlapped these files when the
branch was created. Mission 15 and Workshop publication are outside this change.

## Confirmed rendering defects and repair

`CR_UI` selected `CR_UI_vertexHLSL4`, which requires a COLOR0 input. Ogre
Panel/BorderPanel geometry supplies POSITION0 and TEXCOORD0. Live DX11 inspection
confirmed the mismatch. The material now selects the existing dedicated panel
vertex/tint programs in a first SM4 technique. The previous technique remains
available for older rendering backends.

Standalone subtitles can run before or without PersistentConfig, so its palette
border material can be nil. Ogre queues the border even then and selects
shaderless BaseWhiteNoLighting. ScriptSubtitles now binds CR_UI as an explicit
fallback on construction and show. This fixes the source of the exceptions;
there is no exception suppression or required DX9 workaround.

The panel regression reflects the program actually selected by the material and
checks its compiled input signature. Its negative fixture selects the old,
compilable COLOR0 program and must be rejected. The Lua regression checks the
explicit border fallback without PersistentConfig. CI runs these and the
current communications, assistance and PDA helper suites.

## Validation and provenance

- Material-selected panel reflection and negative regression pass.
- 232 shader compile cases and 17 validator mutation fixtures pass.
- Lua communications 744, assistance 54, PDA/HUD 43, subtitle replacement 10
  checks pass; CRCoop suite passes.
- Campaign repository invariants pass (2,822 files).
- Real native local server, two GOG clients, DX11 Redux mission 11:
  `recovery1015-dx11-subtitle-fix` passes four steps / 17 checks with no Lua,
  Ogre rendering, unresolved-label or device-recreation errors.

Private evidence lives under `C:\BZRCoop\runs`. The local server is the existing
DedicatedServer checkout `50b6b14d8`, bound to loopback. The native OpenShim chain
is startup-hash build `a15765d27` (OpenShim #479), with fresh EXU main `043c2434d`.
OpenShim harness recovery is tracked in draft PR #480. Source files and binaries
are staged only in disposable test clients; the real install and Workshop cache
are unchanged. A final private stage manifest records source overrides.

One tracing experiment crashed inside frida_agent and is excluded from runtime
acceptance. The successful mission 11 control had no instrumentation attached.
Earlier responsive-Lua PASS labels do not establish healthy rendering; the
recovered OpenShim runner now fails on caught renderer exceptions as well.

## Acceptance boundaries

Live assistance and later mission controls are recorded below as they complete.
Rescue acceptance is the craft reaching the remote pilot and its AI pilot
hopping out. Boarding uses the stock walk-into-empty-craft transition; H is
hop out only. No boarding key or forced ownership change belongs in that check.

These controls do not qualify full story completion, remote two-PC play, Steam
delivery, or Proton/Wine. Later mission scripts do not all load PersistentConfig;
shared communications availability does not establish PDA integration there.

## Native assistance checkpoint

`recovery1015-assist-dx11-boarding/recovery1015-assist-dx11-services`
passes eight steps / 14 checks: local terrain markers, expiry preserving a
pre-existing NPC objective, guest help/host reply/cancel, same-object adoption,
guest movement orders, recall, and rescue arrival. A subsequent native probe
confirmed the rescue craft at 28.04 m with IsAliveAndPilot false and command NONE.
No player boarding key was used. Story-objective and player healing are explicit
test assists; the scenario does not establish unassisted story completion.

Physical X passed on both clients. Aiming at open ground with the native mouse
made physical J send a terrain ping to the guest. A failed V-while-closed check
then exposed an actual input-gate regression: the network poller allowed only J
through while closed and discarded V/Z callbacks as already polled. The poller
now queues all three quick actions independently of PDA visibility. Navigation
remains gated, and presses during text entry remain suppressed without replay.
The real polling block passes 24 regression checks covering closed/open edges,
chat exit, and the offline callback boundary. Fresh-client acceptance follows.

## Fresh three-client and physical-input acceptance

`recovery1015-assist-three-final` passes nine steps / 22 checks with all three
clients alive through final validation. The third client observes the original
transferred unit change to team 2 while remaining nonlocal; the recipient owns
that same handle and moves it. Rescue explicitly checks a piloted RESCUE command,
arrival within 35 m, and the craft becoming unpiloted. Marker preservation,
help/reply/cancel and owner-executed recall also pass. Archived native network
health passes on all three clients with no sustained zero-expected rejection
pattern; this does not measure zero packet loss.

`recovery1015-assist-three-final/recovery1015-assist-physical-final`
passes five steps / 22 checks: native physical X on both primary peers; native
terrain-reticle J delivered remotely; V with the PDA closed; Backspace cancelling
the selected help row; stock chat suppressing X/J/V/Z/Backspace without replay.
The long session reports audio-pool warnings, so this is input acceptance, not
voice-over/film timing qualification. No Lua, Ogre rendering or label-resolution
errors occur. Foreground watchdog suppression is explicit for intentional manual
aiming; windowed rendering and graceful stop remain enabled.

The full physical Z aim-to-transfer path remains unqualified: experimental
recipient placement did not establish the required native reticle hit, so no
transfer failure or pass is inferred. That experiment is retained privately and
labelled as an experiment, not shipped as a validated tool. The service adoption
path and closed-PDA Z polling are covered independently by the passing checks.

CR #214 campaign and DX11 shader CI pass at `2e7d836c`; it merged upstream during
validation. The HUD follow-up is [CR #215](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/pull/215),
branch `agent/coop-hud-defaults-20261015`, based on fresh main `33603d19`.

## Later DX11 controls

`recovery1015-dx11-enhanced-misn12`,
`recovery1015-dx11-enhanced-misn13-scroll` and
`recovery1015-dx11-enhanced-misn14-scroll` each pass four steps / 18 checks with
two DX11 Enhanced clients, 45 seconds of observation, parity, clean Lua/Ogre/
device logs and final client survival. These are startup/render controls, not
full story or win/loss qualification. Mission 15 was neither edited nor launched.

## Co-op HUD defaults and native stats

CRCoop applies SetShowScoreboard(false) and the new EXU
SetShowKillMessages(false) once after a local network player is ready. It retries
late EXU availability, leaves solo unchanged, and does not override a subsequent
M toggle. Initialize resets the defaults for the next mission. Lua regression
checks cover solo, late loading, user toggles and restart; repository invariants
pass for 2,826 files.

EXU [draft #110](https://github.com/GrizzlyOne95/ExtraUtilities/pull/110),
workstream `agent/coop-hud-runtime-20261015`, based on EXU main `ba7433d`,
provides the guarded presentation switch and GetPlayerNetworkStats(netId).
The latter copies the native scoreboard's id/name/team, kills/deaths/lives and
remote pingMs/lossPercent without displaying or updating it. Local ping/loss are
absent; lives is the native counter, distinct from CR's respawn-service budget.
No replacement stats overlay is enabled by default.

The uninstrumented `recovery1015-coop-hud-qualified` native two-client run passes
seven steps / 15 checks: default-off state on both peers; stats/registry parity;
physical M on/off that survives campaign updates; reversible notice switch; and
a controlled guest death advancing deaths 0 to 1 and native lives 999 to 998
on both peers while kills remain 0 and notices stay hidden. All clients survive
final validation with clean Lua/Ogre/subtitle/audio checks. The fixture explicitly
heals players and host objectives, so it does not qualify story difficulty.
An earlier presentation-only trace confirms ordinary mission text still displays
when stock notices are suppressed and ship-destruction text returns when enabled.
The final acceptance run uses a fresh build from this EXU branch, replacing the
earlier EXU main DLL in the disposable stage. Private final hashes identify it.
Clients and the private loopback server were stopped gracefully. This workstream
performed no real-install deployment, merge, release or Workshop publication.
