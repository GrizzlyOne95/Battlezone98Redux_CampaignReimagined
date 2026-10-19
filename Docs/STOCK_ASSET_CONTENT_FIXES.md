# Stock Asset and Campaign Content Fixes

This note tracks Battlezone 98 Redux issues from the historical community bug tracker that are better handled as **Campaign Reimagined asset/content corrections** than as OpenShim/EXU engine-roadmap items.

Source tracker: https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues

These entries are intentionally kept separate from the native engine roadmap. Before changing an asset, confirm that Campaign Reimagined does not already override/fix it and preserve stock visual/gameplay intent unless there is a deliberate CR redesign.

## Vehicle / Hardpoint / Hierarchy Fixes

### Issue #8 — CCA Golem reticle / cannon hardpoint mismatch
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/8

- Report: cannon hardpoints are parented in the VDF hierarchy such that they sway/move while the walker animates, causing aim to diverge from the reticle.
- Tracker notes that SBP already carried an asset-side fix.
- CR action: inspect the Golem VDF/hardpoint hierarchy, compare against the known SBP correction if available, and make the minimum hierarchy change needed to keep the cannon aim stable.

### Issue #42 — Turret cockpit rotation hierarchy
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/42

- Report: some turret cockpits inherit rotation from more of the hierarchy than intended.
- Historical workaround: add dummy bones or restructure the hierarchy.
- CR action: identify affected cockpit assets and correct the hierarchy locally where an asset-side correction is appropriate.
- Note: if later RE proves Redux's transform inheritance itself is wrong globally, prefer an engine fix and remove unnecessary asset workarounds.
- Status (CR, 2026-10-19): `svturr` needs an engine hook (not shipped); walkers fixed in the VDF; `avturr_C.*` renamed to lowercase for Proton/Wine.
  - Engine rules (GOG exe; decompile corpus): a cockpit bone whose name equals a VDF GEO takes that GEO's VDF-local orientation every frame (`FUN_00681a00`), relative to its *skeleton* parent; VDF position keys did not move the cockpit view (a +3 m `svw11hed` position sentinel showed nothing, a 40 degree rotation sentinel turned the view). The camera is the POV bone's derived transform plus the view pitch. Non-GEO bones (`*21*` shells, lights) keep their bind local.
  - `svturr` is broken only while deploying or deployed and aiming. Its deploy animation (sequence 0, frames 0-10) is unique among the turrets: `STU11bdb` goes from -90 to 0 degrees about X and `STU11tx1`/`STU21tx1` from +90 to 0, so undeployed they cancel. `bdb` is a parent of the yaw bone (`BDA < bdb < ty1 < tx1 < POV`). `avturr`, `bvturr` and ISDFC `ivturr` have no rotation keys above `ty1`, and `cvturr` folds only its legs, which is why their `POV < 21ty1 < ty1` helper works. Deployed, `TurretTank::Simulate` (`FUN_005f2a40`, state at +0x228) servos each `tx` part toward half the control pitch on top of the animated pose, and the cockpit applies that pitch with the opposite sign.
  - Measured camera pitch relative to the vehicle at control pitch +1/-1 (lcbench, Frida-driven aim, Lua `Deploy`; note that `BuildObject`ed turrets auto-deploy about 9 s after spawn): `avturr` +9 / -8 deployed (correct); stock and CR `svturr` +11 / -11 undeployed but -17 / +11..+19 deployed (inverted: view +11.5 minus the 28.6 degree barrel pitch).
  - No static skeleton fixes both states. A helper under `ty1` (as ivturr) is correct deployed and points the camera straight up undeployed (it inherits the -90 `bdb` fold); POV under `STU21tx1` behaves the same; a helper under `BDA` pitches correctly but does not yaw deployed (`BDA` is counter-rotated). CR keeps its previous `svturr_c` (camera equal to stock). Fix options: (A) an OpenShim hook after the cockpit bone update that cancels the `bdb` deploy rotation on a helper and fixes the cockpit `tx` pitch sign; (B) a CR `svturr.vdf` without the `bdb`/`tx1` fold, which changes the exterior deploy animation.
  - `avturr_c`/`bvturr_c`: already the ISDFC `ivturr_cockpit` pattern; unchanged. `cvturr` (in-mesh): unchanged.
  - Walkers: the walk bob comes from the VDF and is intended; the CR `svwalk_c`/`cvwalk_c` skeletons are unchanged. The fast twitch is single-key reversals in the stock walk sequence (frames 11-30 at 10 fps): shoulder, arm and knuckle tracks swing out and back within one key (about 0.1 s), and those bones skin the cockpit frame. `Assets/ModelFixes/svwalk.vdf`/`cvwalk.vdf` replace each such key inside the walk sequence with its neighbours' midpoint (18 keys per walker, toolkit `vdf_file` round trip byte-exact; deploy/idle sequences untouched). Live A/B (10.7 Hz captures, cockpit lamp centroid second difference): left mean 6.5 to 5.4 px, right 14.0 to 13.0 px. The capture rate cannot resolve a 0.1 s key, so this is supporting, not proof; check by eye in game.

### Issue #48 — Hardpoints parented to moving strafe geos
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/48

- Report: units such as the NSDF Scout/Bomber have hardpoints parented to moving strafe geos, throwing off aim.
- Historical resolution: reparent the hardpoints away from moving geos.
- CR action: audit affected VDFs and correct hardpoint parenting while preserving intended animation.

## Lighting / Material / Model Asset Fixes

### Issue #20 — Inconsistent/missing headlights
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/20

- Report: some units have mismatched headlight setup — lamp model without lamp bone, lamp bone without the intended model/light, or inconsistent combinations.
- CR action: define a consistent headlight convention and audit stock vehicles against it.
- Existing reference/workaround from the tracker: https://steamcommunity.com/sharedfiles/filedetails/?id=3127015460

### Issue #31 — Missing `bbcom2_n.dds`
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/31

- Report: a stock material references `bbcom2_n.dds`, but the texture is absent.
- CR action: determine whether the reference is erroneous or whether an appropriate normal map should be supplied; eliminate the missing-resource error without fabricating detail that does not match the source asset.

### Issue #36 — NSDF Hangar door animation
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/36

- Report: NSDF Hangar doors do not perform the intended opening animation during build/use.
- Tracker resolution note: fix the skeleton.
- CR action: inspect the model/skeleton/VDF animation relationship and repair the asset-side animation data.

### Issue #37 — NSDF Razor material too dim
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/37

- Report: the Razor's material configuration makes the unit substantially too dark/dim.
- Tracker resolution note: adjust the material file.
- CR action: compare against intended stock appearance and CR lighting profiles, then correct the material rather than compensating globally in the renderer.

## Audio / ODF Content Fixes

### Issue #29 — Incorrect/corrupted stock unit VO assignments
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/29

- Report: numerous stock ODFs reference incorrect or corrupted voice lines; example given is a Walker kill-confirmation playing "Sasquatch here!".
- CR action: perform an ODF VO audit by unit/class and correct clearly incorrect assignments.
- Prefer a source-backed mapping where possible instead of normalizing lines by guesswork.

## Mission / Campaign Content Fixes

### Issue #54 — TRO mission softlocks
https://github.com/BlackDragonN001/BZ98ReduxBugTracker/issues/54

- Reported affected missions: **Stranded** and **Hook Line and Sinker**.
- Tracker notes the second case may only occur when the save is using ASCII-save mode.
- CR action: reproduce each softlock in the current rewritten mission scripts, determine whether CR has already eliminated it, and add a mission-level regression test/failsafe where appropriate.
- If reproduction instead identifies a native save/load defect shared by unrelated missions, move the root cause back to the OpenShim engine backlog rather than masking it only in CR Lua.

## Audit Checklist

For each item:

1. Check whether Campaign Reimagined already overrides the affected ODF/VDF/material/model/mission.
2. Reproduce the stock defect where practical.
3. Compare against Battlezone 1.5/source material, SBP fixes, or other trustworthy references when available.
4. Prefer the smallest asset/content correction that restores intended behavior.
5. Avoid adding asset workarounds for bugs that are ultimately proven to be global Redux engine defects.
6. Record completed fixes in the Campaign Reimagined changelog and remove/mark the entry here once validated.
