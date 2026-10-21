# Accepted CR world art — 2026-10-21

The owner accepted the nine-world terrain, lighting and sky work on 2026-10-21.
This integration retains CR PRs #273–277 and the matching OpenShim #537 controls.
The final world candidate supersedes earlier Moon dust/rock trials; those recipes
and their documented validation history remain available.

## Canonical art

- All nine reviewed HD packs: Moon, Mars, Venus, Io, Europa, Titan, Ganymede,
  Achilles and Elysium. The 604 diffuse/normal/specular/emissive resources are
  copied byte-for-byte from the reviewed bundles.
- Moon uses the accepted Poly Haven regolith, varied authored craters,
  signed R32 height and 2048px height-derived detail. Relief remains 0.625 m.
- The Moon material selects the accepted detail texture. Original atlas and
  detail files remain available. Off Enhanced, native atlas terrain still works;
  the material's new fine detail also applies to that fallback.
- World lighting and five atmospheric sky materials preserve established
  palettes and original sky art while smoothing terrain/fog/horizon joins.
- Per-world depth, detail and masked-surface authoring controls remain editable.

`Tools/TerrainHD/accepted_world_art.json` pins all 606 promoted runtime DDS
hashes. Each world's `authoring.json` rebuilds losslessly from canonical DDS;
`pack_validation.json` records current pack hashes. Earlier
`normal_validation.json` files retain their original source-basis evidence and
are historical, rather than audits of replacement art. Moon's source URLs,
CC0 license, credits and source hashes remain in `Moon/polyhaven.json` and
`Docs/MOON_POLYHAVEN_TRIAL.md`. Other worlds retain their existing source
provenance plus palette/morphology adjustments and reference hashes.

The exact reviewed local set is
`Campaign-Reimagined-world-surface-lighting/Local/WorldArt/Revision01`.
Import another explicitly accepted set with `Tools/Promote-WorldArt.py
--candidate-root <set>` and the pinned Toolbox library, review all diffs, then
run `Manage-CampaignFiles.ps1 -bless`. Import validates all nine bundles before
writing and preserves CR's runtime tuning. PNG masters, downloaded sources,
screenshots and runtime output stay outside Git. Import does not deploy or publish.

## Validation and scope

The nine-world GOG image review and Enhanced/Redux/Enhanced restoration evidence
are recorded in `Docs/TERRAIN_WORLD_ART_PASS.md`. Integration additionally checks
lossless nine-pack rebuilds, accepted hashes and shipping membership, Moon
material/crater/normal tests, art controls, lighting/sky ownership, atmosphere
integration, Mission 17 and shader references. The matching native dependency
builds as Release Win32 and runs Windows/Linux engine-independent tests.

Owner art acceptance is complete. Full campaign lifecycles, multiplayer and
Steam/Proton/Wine runtime qualification remain separate. This is source/shipping
promotion, not a Workshop upload or tagged native release.

## Integration receipt

- Integration PR: CR #278, preserving every commit from #273–277; native
  dependency: OpenShim #537, refreshed onto current main before validation.
- All nine lossless pack rebuilds and all 606 accepted hashes pass, along with
  the nine targeted Python suites, repository invariants (4,269 files), owned
  program references and 232 CR DX11 shader compilations.
- Lighting/sky ownership: 48 checks; atmosphere integration: 93; Mission 17:
  272. Native Release Win32 build, all 136 Windows tests, all 111 Linux host
  tests, 210 Enhanced HLSL compilations and load-chain/package checks pass.
- Fresh canonical-DDS Moon rebuild, GOG/DX11 PID 41336:
  `Local/TerrainHD/run-20261021-075321`. Inspected capture retains fine regolith
  and varied bowls/rims. All 19,445 height scopes, 144 streams/bounds, 82 passes
  and 184 staged files restore. Private RAM 367.8 MiB; peak 503.4 MiB.
- Fresh canonical-DDS Elysium rebuild, GOG/DX11 PID 41976:
  `Local/TerrainHD/run-20261021-075500`. Inspected capture retains gray ground,
  original purple sky and a smooth fog horizon. All 222 staged files restore.
  Private RAM 484.0 MiB; peak 663.0 MiB. Both trials retain a largest free
  address-space block near 2,045 MiB; these are short observations, not a
  long-session memory qualification.
- Native bundle refreshed through the manager: OpenShim integration code
  `1524f0a9a` (plus Roadmap-only acceptance commit), EXU main `aad6e2b` and bzfile
  main `44f012e`. Matching binaries, symbols, configuration and manifest are
  refreshed together. Shipping membership adds the two Moon resources and
  seven current native UI/renderer payloads, with no removals.
