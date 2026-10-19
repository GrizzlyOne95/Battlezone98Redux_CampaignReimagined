# Original CCA painted-steel texture source

`cca_painted_steel.png` is an original paint/material tile generated with the
built-in imagegen tool on 2026-10-19. It is projected in Blender object space and
baked into each ship's UV diffuse, tangent-normal and specular atlases. It is not
a UV layout, a replacement for geometry, or a copied stock texture.

Visual references, inspected from the local Redux install: `svapc_D.dds`,
`svrecy_D.dds`, `svtank_D.dds` and `sblpad_D.dds`. Their characteristic warm ivory,
charcoal lower armour, worn red faction markings, amber lamps, safety chevrons,
steel louvres and chipped paint guide the modelling and material pass. The
original stock images stay in the install; they are not committed here.

Generation prompt (built-in tool; first three references attached for style):

> Use case: stylized-concept. Asset type: production game texture, seamless
> square painted-metal material swatch for Blender to project and bake onto
> Battlezone 98 Redux CCA capital ships. The three input images are STYLE
> REFERENCES ONLY: stock CCA APC, Recycler and launch pad diffuse atlases.
> Generate an ORIGINAL SINGLE continuous 2048x2048 square material tile, NOT a
> UV atlas and NOT a vehicle render. It must match their tactile painted steel
> character: desaturated medium warm gray military paint, slight chalky aging,
> fine irregular chips exposing darker gunmetal primer, shallow scuffs, tiny
> pinprick pits, sparse faint lubricant streaking. Grunge must be fine restrained
> detail, not a giant camouflage pattern or crusty corrosion. Flat orthographic
> albedo surface, diffuse neutral illumination with NO cast shadows, NO
> highlights, NO baked lighting. Make both pairs of opposite edges seamlessly
> tileable. No big panel boundaries, no bolts, no vents, no decals, no text, no
> stars, no logos, no borders: those will be authored on the actual models. Keep
> overall contrast modest so panel colours remain readable and can be tinted
> red, ivory and charcoal. It should look hand finished like the reference game
> textures, not clean plastic and not photoreal rock. Only the material tile
> fills the image edge to edge.

The generated tile is 1254 x 1254 pixels. Requested dimensions are not treated as
proof of the actual tool output size. Source SHA-256:
`f6ac13a3e6899f13250d6d45e9388b185094ddd0174a39f147cd0fc422e3f95d`.
No seamlessness claim is verified by that prompt alone; Blender box projection
and small-scale tiling are visually inspected on the authored hulls.

CCA stars, ring insignia, stencilled numbers/CCCP, warning strips, hull panels,
conduits and radiators are separately authored geometry fitted to each hull.
`Tools/CCA-ReduxDetail.py` keeps those editable and deterministically rebuilds
the placement, paint shader and normal/specular bakes. The three concept
silhouettes, pivots and recorded scale remain the design constraints.
