# Escape from Mars: CCA transport departure

The existing `misn0614.wav` report now has a short tracking shot of the CCA
rocket lifting out of its gantry. Its bright engine core, orange plume,
world-space smoke and expanding red pad dust render locally on every peer.
The original dialogue, objective order, flight-log recon target and deadlines
are retained.

## Presentation

- `cr06_rocket` is a neutral, invulnerable map fixture, present from map load.
  Nothing is spawned in view when the cue arrives. The existing `sblpad` stays
  intact, with its original identity and team, for the later recon objective.
- One second of ignition precedes the accelerating climb. The camera follows
  the same rocket for 11 seconds. The flight continues after the camera ends;
  at 20 seconds the rocket is more than 900 m above its starting position and
  the authority removes it through the existing acknowledged presentation stream.
- As with Mission 16's takeoff, an acknowledged event makes every peer move
  its own preplaced fixture. Static-building motion is not assumed to replicate
  like a vehicle's motion. Each peer also owns and cleans its particle systems.
- Dust stays at terrain height and its emission tapers as the rocket clears
  the pad. Smoke remains in world space and dissipates after emission stops.
  The four systems have a combined quota of 774 particles per peer.
- A player's skip releases only their own camera in co-op. Solo skip leaves
  the flight and dialogue running. Save/load retains the launch origin and age;
  a resumed ascent does not repeat the ignition dust. Loading a completed or
  skipped view does not reopen it.
- Missing fixtures in an old save skip the insert. Unavailable optional particle
  APIs log a specific failure and preserve the rocket motion. No fixture receives
  craft AI commands, damage or an added victory/failure condition.
- The existing CCA approach-film cancellation condition is now scoped to that
  film's own active flag, so a stray cancel cannot finish another shot's camera.

## Art and reconstruction

CCA rocket geometry and its four texture maps come from **Battlezone: Resurgence**
by GrizzlyOne95 and contributors. The author's [asset-pack description](https://steamcommunity.com/sharedfiles/filedetails/?id=3536800125)
permits use in other projects with appropriate credit. This adaptation extracts
the rocket submesh from the docked `sblpada` asset, keeps its 7,332 triangles,
UVs and normals, recentres it, and removes the pad and unused skeleton.
Resources are namespaced `cr06rok`; no stock or Resurgence asset is overwritten.
Original Battlezone design/art credit remains with its creators.

`Tools/Build-Misn06Rocket.py <Resurgence directory>` reproduces the extracted
mesh, native SDF/GEO and textures and prints source SHA-256 hashes.
`Tools/Add-Misn06Rocket.py` adds the fixture without rewriting authored blocks;
`Build-CoopMap.py --mission misn06` also calls this step automatically.
Resurgence's docked pad is rotated 180 degrees relative to the stock Redux pad,
so the fixture's placement explicitly compensates for that difference.

The takeoff arc, camera and particle definitions are CR-authored presentation.
They do not import Resurgence's launchpad replacement or reinforcement logic.

## Validation

Host checks: original mission scenarios, source parity, shared-map contract,
four-peer presentation relay, film lifecycle and VFX lifecycle. The new suites
are wired into `campaign-validation.yml`.

Native run `mars-rocket-3` passed 7 steps / 16 checks on two Windows/GOG clients:
the original VO starts the insert, the rocket rises on both peers, the four
particle systems exist, the camera releases, the pad and deadlines survive,
and the actor/particles clean up. Both clients exited with return code 0.
Screenshots confirm visible orange exhaust during ascent. They also revealed a
ridge obscuring ignition in the first camera position; the camera is now higher
and on the other side of the pad, pending a second visual check.
Steam and Proton/Wine remain unverified. No Workshop upload or release is part
of this prototype.

## Resume checkpoint — 18 October 2026

Branch: `agent/mars-rocket`, draft PR #228. Implementation and host tests are
complete; revised native framing and effects tuning are the next step.
Checkpoint `91d710d3` contains the initial implementation. The isolated manager-staged content
is `C:/BZRCoop/mars-launch-20261018/content`; the regular GOG mod is untouched.
Run OpenShim's `Run-BZRCoopMission.ps1` with `-Mission misn06`, this content,
`-Scenario <this checkout>/Tools/Test-Misn06LaunchLive.ps1`, and two clients.
The scenario advances only the original launch timer, verifies the actual radio
cue, preplaced rocket, camera and all four particle systems on both peers,
then waits for departure and cleanup. Inspect its screenshots before marking
the visual result verified. Preserve other active native test sessions.
