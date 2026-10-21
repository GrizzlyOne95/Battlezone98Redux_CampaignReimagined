# Mission 18 storm forest

Owner request, 2026-10-21: add trees to the final NSDF mission, like Mission 17,
without obstructing routes/objectives. Wind should move their branches; nearby
lightning should destroy them and the tornado should uproot and destroy them.

## Placement

`Build-Misn18Trees.py` generates 978 deterministic sites on grass/forest tiles,
using the existing credited `c17frst1`–`c17frst4` firs. No new tree art or ODFs,
no terrain edits and no changes to the faithful mission body. It uses the shared
toolbox BZN/HG2/MAT readers and the current CR terrain, paths and water mask.

Tree centres stay outside:

- All 24 storm safety circles plus 20 m, including the base, transport,
  extraction area, wave spawns and ambush column.
- Every authored object by 40 m and every authored path/camera by 50 m.
- Connected main/alternate player approaches and return corridors, and the
  explicit spawn-to-transport Goto lanes, by 50 m on each side.
- Baked water by 18 m; map edges by at least 32 m; slopes above 0.6 rise/run.

The placement checker repeats generation from source and validates these
exclusions. These are geometric checks; driving the approaches and reviewing
the forest density in the game remain pending.

## Runtime and weather

`CRStorm18Trees` streams authority-owned, team-zero solid plants around **all**
human players. It services at 10 Hz, visits at most 128 site records and builds
at most two trees/removes at most four distant trees per slice. A global cap of
256 live objects bounds simulation cost. Trees build in the 280–460 m ring,
outside the 250 m visibility range; unload beyond 560 m. Ogre rendering distance
is 300 m, applied directly after creation and through the mission AddObject hook.
The authority makes one object recovery scan after Start/Load; combat uses the
site grid and cached handles, with no recurring whole-world scan or label polling.

The existing branch and shadow-caster wind materials register with CRFoliageWind
and are returned to calm by the director's existing Stop lifecycle.

Ground bolt events now include a leader-selected world point near a human.
Every peer draws that same channel; dry flashes carry no point. Only the
authority's first ground stroke destroys fir sites within 24 m. It does not
apply area damage to craft, objectives or any other object. No extra tree or
explosion broadcast is added. Cosmetic grass removal remains client-local.

The authority samples the replicated tornado at most every 0.25 s once it has
grown for 5 s. Within 45 m, live trees lift 18 m, tip and turn over 1.2 s, then
receive lethal native damage. At most eight trees animate at once, on the 10 Hz
service; additional affected trees die immediately. This is a short scripted
uproot of the actual plant, not a new debris/physics simulation. The tornado's
existing craft ownership and extraction safety rules remain intact; the forest
damage path only ever touches its own tree registry, including during extraction.

Weather lookups use 64 m cells and stop at 64 candidate sites. Generated data
has at most four sites per cell, so a 45 m funnel query fits entirely in budget.
Combat or weather deaths persist in the authority's storm save. Unbuilt sites
can be marked dead by weather, and streaming unloads do not count as deaths.
An uproot saved mid-animation resumes and finishes after load. Existing plant
ODFs/native plant support provide ordinary weapon damage and their death puff.

## Validation

- `Build-Misn18Trees.py --check`: 978 generated sites, all exclusions pass.
- `Test-CRStorm18Trees.lua`: 1,451 checks; streamer, per-slice/global caps, ownership, spatial
  weather budget, lightning idempotence, lifted/tipped transforms, mid-uproot
  load, combat deaths and permanently removed unstreamed sites.
- `Test-CRStorm18.lua`: 2,361 checks; shared ground bolt coordinates across different cameras,
  authority-only first-stroke tree removal, wind/caster registration, existing
  storm lifecycle, tornado and extraction safety behavior.
- Faithful Mission 18 suite (163 checks), four-peer co-op suite (3,008 checks),
  source parity, co-op contract and repository invariants passed.
- New scripts are in the shipping lock and checks are in CI. The general bless
  refused to remove 50 absent generated OpenShim UI files, so only the two new
  script memberships were inserted in place, per knowledge-base section 3.8;
  all existing shipping entries were preserved.

**Live testing pending by owner instruction.** Actual tree rendering/density,
collision/path clearance, native building transform animation, replicated plant
death and save/load in game, weather presentation and FPS/hitching have not been
verified. The isolated flora fixture is also pending; see `LOCAL_FLORA_DAMAGE.md`.
No installed mission, release DLL or Workshop content was changed.
