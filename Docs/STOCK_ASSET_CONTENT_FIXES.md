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
