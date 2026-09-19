# Campaign Reimagined -> OpenShim renderer/material migration

## Purpose

Campaign Reimagined currently carries both campaign artwork and a significant stock-material redirect layer used to make stock Battlezone material names inherit CR base materials and therefore execute OpenShim's `OSE_*` enhanced shader programs.

That arrangement works, but it leaves Campaign Reimagined acting as the activation layer for renderer behavior that should be available to stock Battlezone content through OpenShim itself.

This document records the migration plan so CR can become a clean consumer of OpenShim Enhanced rather than the de facto owner of stock enhanced material routing.

## Target ownership boundary

OpenShim owns reusable rendering infrastructure and stock compatibility/adaptation.

Campaign Reimagined owns campaign-specific art and presentation.

The test for each CR material is:

> If the material would still be useful after removing every CR-specific texture/art asset, because it primarily routes a stock material name through Enhanced rendering, migrate the generic/stock-compatible responsibility to OpenShim.

If the material selects CR replacement art or implements intentional CR-only presentation, keep it in CR.

## Current pattern

Many CR asset materials follow this shape:

```text
import * from "CR_BZBase.material"

material <stock-ish name> : CR_BZBase
{
    set_texture_alias DiffuseMap  ...
    set_texture_alias NormalMap   ...
    set_texture_alias SpecularMap ...
    set_texture_alias EmissiveMap ...
}
```

The reusable rendering contract lives in the base material and in OpenShim's `OSE_*` programs. The leaf material may contain a mixture of:

1. stock name compatibility;
2. stock texture selection;
3. CR replacement texture selection;
4. campaign-specific tuning.

Those concerns need to be separated rather than moving entire files blindly.

## Files/directories to audit first

### Generic renderer candidates

- `Materials/CR_BZBase.material`
- `Materials/CR_BZTerrainBase.material`
- `Materials/CR_DepthShadowmap.material`
- `Shaders/CR_DepthShadowmap-sm4.hlsl`
- `Shaders/CR_DepthShadowmap.hlsl`
- `Shaders/CR_DepthShadowmap*.glsl`
- `Shaders/CR_effect-sm4.hlsl`
- `Shaders/CR_effect-fragment.glsl`
- `Shaders/CR_effect-vertex.glsl`

These should be compared against OpenShim's existing `resources/renderer/enhanced/` resources before anything is copied. Prefer consolidation into the existing OpenShim implementation over creating another duplicate.

### Stock-derived material candidates

Audit the rest of `Materials/` for files that are copies or derivatives of stock materials whose primary functional change is inheritance from `CR_BZBase`, `CR_BZTerrainBase`, or another CR renderer base.

Do not classify solely by filename. Inspect the texture aliases and pass changes.

### CR-specific materials expected to remain

Examples of content that should remain in CR include:

- materials selecting CR-specific vehicle/building D/N/S/E textures;
- `CR_reactive.material` and future CR reactive damage artwork;
- CR weather particle/skydome materials and their intended textures;
- BZ2/upscaled/reauthored effect artwork intentionally selected by CR;
- planet/mission-specific visual presentation;
- any material whose behavior is deliberately unique to CR rather than required for generic Enhanced rendering.

## Required migration behavior

The end state should allow this:

```text
stock Redux content
    -> stock material name resolves
    -> OpenShim/OpenShimAssets supplies generic Enhanced compatibility/adaptation
    -> OpenShim shader suite renders it
```

with CR absent.

When CR is installed:

```text
stock name / CR material override
    -> CR selects richer CR textures or presentation
    -> material inherits/uses stable OpenShim renderer contract
    -> same OpenShim shader suite renders it
```

CR should no longer need its own copy of generic rendering infrastructure simply to reach OpenShim shaders.

## Migration phases

### Phase 1 - inventory and classification

Create a manifest/table for every relevant file in `Shaders/` and `Materials/` with one of these classifications:

- `OPENSHIM_GENERIC`: reusable shader/program/base material implementation;
- `OPENSHIM_STOCK_COMPAT`: stock-derived redirect/adaptation whose purpose is generic Enhanced rendering;
- `MIXED_SPLIT_REQUIRED`: combines stock compatibility with CR-specific art/tuning and must be split;
- `CR_CONTENT`: campaign-specific art/presentation and remains in CR;
- `LEGACY/UNUSED`: candidate for removal after verification.

For mixed files, record exactly which portions belong on each side.

### Phase 2 - stable OpenShim bases

Once the companion OpenShim work provides generic bases, update CR leaf materials to consume those names instead of `CR_BZBase` / `CR_BZTerrainBase` where appropriate.

Example target shape:

```text
import * from "openshim_base.material"

material cvtnk : OpenShim/BZBase
{
    set_texture_alias DiffuseMap  cvtnk_D.dds
    set_texture_alias NormalMap   cvtnk_N.dds
    set_texture_alias SpecularMap cvtnk_S.dds
    set_texture_alias EmissiveMap cvtnk_E.dds
}
```

The exact OpenShim material names are to be decided by the OpenShim implementation. CR should not invent a second parallel namespace.

### Phase 3 - move stock redirects

For each stock-derived material whose purpose is generic Enhanced activation:

1. prove the equivalent material exists in the OpenShim stock compatibility layer;
2. test the relevant stock mission/model/terrain without CR;
3. remove the CR copy only after visual and behavior parity is confirmed;
4. verify CR still overrides it correctly when CR-specific artwork is present.

Do not bulk-delete stock-derived CR materials before OpenShim provides equivalent coverage.

### Phase 4 - shrink CR to campaign content

After migration, `CampaignReimagined/Materials` should primarily describe CR artwork/presentation rather than reproduce the stock material catalog.

Likewise `CampaignReimagined/Shaders` should contain only shaders that are genuinely CR-specific. Generic renderer shaders should have one source of truth in OpenShim.

## Resource precedence requirement

The intended dependency direction is:

```text
Stock Redux
    -> OpenShim Enhanced + stock compatibility
        -> Campaign Reimagined optional overrides
```

Never make OpenShim depend on CR.

CR may require a documented minimum OpenShim/OpenShimAssets version after the migration.

Any load-order/resource-group behavior needed for CR to override OpenShim stock-compatible definitions should be documented and tested explicitly rather than assumed.

## Representative qualification set

Before migrating hundreds of materials, qualify a small cross-section:

- one stock vehicle/entity material;
- one stock building/prop material;
- one terrain material;
- one additive/alpha effect material;
- one material using CR D/N/S/E replacements;
- one special material that should *not* be auto-upgraded (UI/overlay/cockpit/etc.).

For each case compare:

1. stock Redux, no OpenShim Enhanced;
2. stock Redux + OpenShim Enhanced, no CR;
3. CR + OpenShim Enhanced.

The second case is the critical new requirement.

## Preserve CR art ownership

Migration must not accidentally move CR artwork into OpenShim just because the material using it originated from a stock definition.

A mixed material can be split conceptually as:

```text
OpenShim stock compatibility
    material identity + generic renderer contract + safe fallbacks

CR override
    CR diffuse/normal/specular/emissive maps + CR tuning
```

That keeps OpenShim generally useful while CR remains free to be visually opinionated.

## Runtime material enhancement follow-up

The first migration may still use an OpenShim-owned stock compatibility material pack because the technique is already proven by CR.

Long-term, OpenShim should investigate upgrading qualifying Ogre materials at runtime so a large copied stock catalog is unnecessary. CR should not block on that research.

If runtime adaptation eventually replaces a stock compatibility file, CR should continue to work against the same conceptual OpenShim material contract without needing another wholesale rewrite.

## Coordination

Companion OpenShim design work defines the renderer ownership boundary and stock compatibility/runtime-adaptation plan.

Also coordinate with OpenShim PR #191, which already establishes OpenShim ownership of reusable scene depth, AO, haze, soft-particle depth support, and renderer lifecycle. Material/shader ownership should follow the same boundary.

## Acceptance criteria

This migration is complete when:

- stock Redux can use representative Enhanced rendering paths without Campaign Reimagined installed;
- CR no longer owns generic shader/base-material infrastructure solely to activate OpenShim rendering;
- CR's remaining materials are predominantly campaign-specific art/presentation definitions;
- CR replacement D/N/S/E assets continue to render correctly through OpenShim;
- stock and Workshop compatibility are not degraded by broad unintended overrides;
- disabling Enhanced/using Classic remains compatible with expected stock behavior;
- generic shader/material implementations have a single authoritative source rather than divergent CR/OpenShim copies.

## Non-goal for this planning PR

This PR does not yet move or delete shaders/materials. It records the audit and migration contract. Implementation should proceed incrementally from a representative material set after the OpenShim-side generic bases/compatibility mechanism are defined.