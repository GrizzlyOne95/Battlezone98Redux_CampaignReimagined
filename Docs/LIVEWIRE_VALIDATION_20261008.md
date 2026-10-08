# Operation Livewire native validation, 8 October 2026

The destruction crash is a mission setup bug. `Ensure("break_look")` applied
`SetIndependence` to every fixture in the destruction group, including the
`sxanchor` camera pod. Its ODF selects `PowerUpProcess`, which has a 24-byte
allocation. The stock independence setter writes a DWORD at byte offset 24,
outside that allocation. Lua `pcall` does not protect against this native write.

A debugger hardware watchpoint caught that exact write during chapter setup,
with a stock Lua setter on the call stack. The damaged allocation had the
`PowerUpProcess` vtable and its first heap tail DWORD changed from the debug
guard pattern to zero. The earlier dump detected corruption later while Ogre
freed a destroyed object's skeleton; that was the detection site.

`holdPosition` is now explicitly enabled for the ten destruction craft.
The camera pod and static buildings receive no independence or stop command.
The host regression counts unsafe calls even if a caller wraps them in `pcall`,
and checks that all ten craft still hold their marks.

## Native evidence

The Windows test client is an isolated GOG 2.2.301 copy with an offline Steam API
adapter, running DX11, the Enhanced profile and chunk meshes at 560 x 315.
The original installed OpenShim DLL was retained for the successful runs:

`08CF8C197E5092F1D6943F1F057F34728FEEDBB27FDC5237116796DEA19DC5BB`

An experimental renderer input-probe change did not fix the crash and was
discarded. No renderer change is needed for the demonstrated mission fix.

- Original mission + Enhanced: reproducible native heap corruption.
- Original mission + Redux: destruction completed; that changed heap layout
  did not establish that the mission was safe.
- Fixed mission + original Enhanced renderer: all thirteen destruction cues,
  chapter completion and normal shutdown.
- Fixed mission + original Enhanced renderer: complete nine-chapter tour,
  cleanup PASS and `Exiting Game With Return Code 0`.
- Lua 5.1 host regression: 111 checks passed.
- Map/dependency validator: 365 checks passed.

Local debugger logs, dumps, runtime logs and screenshots are in the GOG game's
`logs/livewire_validation_20261008` directory and the isolated client's parent
directory. Dumps remain local and are not repository or publication artifacts.

## Trailer presentation

Captions wrap within the safe frame and use a larger font. The AI shots now
follow the actual tanks with object-relative cameras; rear and front views were
inspected in the native tour. The materials shot was checked separately
with several camera and lighting experiments; those experiments were discarded.
The original material camera remains. Tint and emissive pulse have not yet been
shown convincingly in the native capture.

The current tour lasts 400 simulation seconds (6:40): arrival 25, materials 40,
environment 55, AI 60, destruction 45, filters 55, control 45, cockpit 45,
handover 30. Menus pause the film clock and suppress the custom overlay.

This is a successful crash regression and sequence test, not final trailer
acceptance. Remaining checks are:

- Capture-resolution framing and HUD layout at 1920 x 1080. The 560 x 315
  desktop test crowds the stock cockpit, especially with enlarged radar.
- Audible unit radio, music and transitions; playback API readbacks alone
  establish neither audibility nor a usable recording mix.
- Direct observation of shield/magnet behavior and the protected/triggered mine
  crossings. Readbacks and a completed tour do not certify all filter physics.
- Real Hunt-button interception, native options, and replay/cancel interaction.

Steam, Proton and Wine were not qualified. No Workshop upload or release was
performed. Shipping-lock regeneration also admitted unrelated stock scripts and
test files, so that generated lock change was discarded rather than bundled
with this mission fix.

## Investigation record and limits

### Renderer attribution

The original corruption dump (`C:/BZRCoop/sx/heap_crash.dmp`) caught a damaged
heap header during Ogre BoneNode child-map/skeleton/entity cleanup after a tank
was destroyed. It did not prove that the renderer made the damaging write.
`C:/BZRCoop/sx/powerup-write.dmp` and the corresponding hardware-watchpoint log
caught the earlier stock Lua independence setter writing outside the camera
pod's AI allocation. This establishes the mission error independently of the
later Ogre stack. Dumps remain local.

Controlled experiments with the original unsafe script:

- Enhanced reproduced the crash; Redux completed thirteen kills. A different
  heap layout can hide the same invalid write, so Redux completion alone was
  insufficient evidence for a renderer regression or a safe mission.
- Disabling only EnhancedLightSelectionV2 still crashed.
- Disabling only ChunkMeshes still crashed.
- DX9 attempts at 560 x 315, 640 x 480 and the portrait desktop mode all failed
  startup with `Can't find requested video mode`. No DX9 gameplay comparison
  was established.
- Skipping a renderer input probe in debugger memory allowed destruction but
  still found heap corruption on exit. A compiled input-probe whitelist
  candidate also crashed. Both approaches were discarded; suppression of one
  detection site is not a heap fix.
- Guarded access violations during render-operation inspection were observed.
  They were handled exceptions, not the demonstrated original corrupting write.

The OpenShim source experiment was restored, and its Release build was rebuilt
from the restored source successfully. The isolated client's DLL, renderer
resources and native loader chain were restored to the original installed set
before the successful destruction and full-tour regressions. The actual GOG
installation's renderer was unchanged. No EXU or bzfile binary was deployed.

Successful native evidence is archived under
`logs/livewire_validation_20261008/chunks_fixed_original` and
`logs/livewire_validation_20261008/full_fixed_original`. The latter recorded
normal return code 0 at 09:48:49.941. Debugger runs that altered corrupted heap
state to let a fatal failure propagate are diagnostic runs, not clean-shutdown
qualification. Always include unmodified normal shutdown in acceptance.

### Material and capture experiments

Native material property readbacks passed, but the displayed scout hull stayed
dark and a clear tint/pulse change was not established. Trials included stronger
pulse amplitude, explicit Enhanced lighting, higher neutral ambient light, and
object-relative cameras on both sides of the subject. One camera crossed a
cliff; a closer camera avoided the cliff but lost the stock comparison craft.
None provided acceptable visual proof, so material/camera/lighting trial changes
were restored. API success alone is not feature visibility. The installed EXU
binary differs from the current repository build; no newer binary was silently
substituted to make a test pass.

The available remote desktop was 600 x 1284 portrait. A small 560 x 315 window
provided usable 16:9 inspection, while a requested 1920 x 1080 window was clamped
by the desktop. Host overlay layout checks at 720p, 1080p and 4K establish text
bounds only, not native framing at those resolutions. The custom overlay now
wraps words and places rows after their actual wrapped height. The stock cockpit
and large radar still crowd the small native view. Audio playback readback,
sequence completion and HUD visibility are separate acceptance claims.

The game can pause loading or simulation when unfocused. Activate the game
before timed visual checks, and inspect the actual screenshot contents before
naming evidence. Occluded-window captures that contained the Codex sidebar were
removed and are not valid game evidence. Some older screenshot filenames were
based on wall-clock estimates and do not match their visible chapter; identify
those by image contents, not filename.

### Harness and packaging discipline

Use OpenShim `reverse_engineering/BZRHarness.ps1`, its shared launch mutex,
windowed configuration and `Stop-BZRGame -NoForce`. The test harness copies the
fourteen demo files into an isolated physical mod directory, temporarily selects
a chapter/start delay, and restores renderer configuration in `finally`. Restore
canonical mission files after the test so those launch-only edits do not leak
into the demo. Do not manipulate native UI through PowerShell automation or
force-kill a game to claim successful cleanup. Live cdb sessions require an
interactive terminal; detaching (`qd`) and ending an already exited debuggee
(`q`) are different operations. Do not dump process environment variables into
investigation logs.

The source checkout is the canonical CR repository; the runnable test copy is
`C:/BZRCoop/sx/Battlezone 98 Redux`. No secondary CR checkout was created. The
normal GOG development mod did not already contain this demo, so this validation
did not constitute a root-install deployment or Workshop qualification.
Shipping-lock regeneration proposed 70 additions: fourteen demo files and 56
unrelated stock/test files. The entire generated lock change was discarded.
Future release staging must use the file manager and review its exact membership.

### Durable prevention

`Docs/BZR_LUA_AGENT_REFERENCE.md` now includes the non-unit independence hazard
in its front-page agent rules and high-priority bugs. Existing camera-stack,
CRLF BZN, camera movement, geometry-table and demo content findings were retained
while synchronizing the four previously divergent copies. Its normalized SHA-256
pin was updated in CR, OpenShim, EXU and bzfile. Before this work, CR's committed
reference already differed from its committed pin; the mismatch was not caused
by this mission fix. The synchronized guidance fixes that stale baseline too.
CR `AGENTS.md` requires this report for Livewire/cinematic fixture setup.

`Tools/Test-SXShowcase.lua` fails on any non-craft independence call even if a
caller catches the mock error with `pcall`; it also requires all ten intended
craft to hold position. Keep both checks: dropping all AI commands would hide
the crash while losing the exhibit's staging behavior. Continue native feature
and presentation testing before calling the demo ready for a YouTube trailer.

## Final checkpoint checks

After discarding the presentation experiments and synchronizing the guidance:

- Lua 5.1 showcase regression: 111 checks passed.
- Showcase asset/schema/dependency validator: 365 checks passed.
- CR repository validator: 4004 files checked; invariants passed. Its existing
  external `CRCoopRespawn` require warning remains non-fatal.
- Both shared documents are byte-identical in all four current checkouts;
  normalized pins match. OpenShim's CMake shared-document check passed. The same
  check against bzfile's documents passed and its shell script parsed.
- EXU's validator passed the shared-document, API/version parity, address census,
  hardening-marker and patch-preimage checks. Its overall run failed on the
  existing `src/Ogre/OgreNativeFontBridge.cpp:827` exception-handler policy
  violation (`__except must use Seh::Filter`). That file matches its committed
  HEAD and was not changed here. This is a separate backlog item, not a mission
  crash regression or a clean EXU qualification.

No public push, PR, release, Workshop upload or Steam qualification is included
in this checkpoint. Repositories retain unrelated untracked files untouched.
