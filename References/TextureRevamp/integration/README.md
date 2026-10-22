# Existing faction ODF integration

Owner authorization: add the reviewed faction art to CR and route every existing
faction pickup to its proper model (`spblst` → `spcann`, `spcamr`, `sbstor`, etc.).
No game launch, installed deployment or Workshop publication accompanies this.

`manifest.json` maps 361 ODFs and 32 canonical model aliases. Prefixes a/b/s/c
mean NSDF/Black Dog/CCA/CRA. Each faction has nav, ammo, repair, cannon, rocket,
mortar, special and storage resources. Mesh aliases use the shared serializer;
only the skeleton resource name changes relative to the reviewed `cr*` model.
Native VDF/SDF and skeleton bytes are copied exactly; material/atlas resources
remain shared, with no extra texture maps. There are three new placeable ODFs:
`bpcamr`, `sbstor` and `cbstor`.

`original/` contains exact pre-integration ODF text (or the reviewed template
for a new ODF). Every setting other than `baseName` is preserved, including
500/425 health on original NSDF/Black Dog storage, CCA ammo 700, and faction
weapon payloads. The builder refuses unrelated ODF edits, rather than overwriting
them. `build.json` records every current runtime output hash.

Rebuild order:

```text
python Tools/Build-FactionStorage.py
python Tools/Build-FactionNavPickups.py
python Tools/Build-FactionPickupIntegration.py
python Tools/Test-FactionNavPickups.py
python Tools/Test-FactionPickupIntegration.py
```

The integration builder must run last because the art builder first regenerates
the source-preserving namespaced ODF variants. `--capture` is a one-time baseline
operation and deliberately refuses an existing manifest. Shipping admits only
the 96 new alias resources and three new ODFs, preserving earlier members/order.
Tests establish source and resource contracts, not native loading, spin,
collection/rejection or multiplayer/platform behavior; those remain unrun.
