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
