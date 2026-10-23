# CRA cockpit connection review

This offline checkpoint covers the owner's approved next two steps: correct
`cvfigh` wing/gun placement, then fully revamp `cvhtnk`. It does not implement
the rest of the proposed candidate queue or deploy anything.

- `References/CVFighterCockpit/README.md`: follow-up design/limits; existing
  cockpit art and original review images retained. New views compare against
  that accepted prototype, not against the original stock cage.
- `References/CVHeavyCockpit/README.md`: actual POV, new armored interior,
  source bow sections, complete gun-pod drivers and build/qualification limits.
- `review/`: before/after, exported one-sided forward/down/console/side views,
  side-down, roof/rear/floor, low-light optics, camera contracts and heavy checks.

The local review gallery is `http://127.0.0.1:8767/cra-connections/index.html`
while the existing maintainer review server runs. Original third-person POV
locators and cutaways are copied there as diagnostic references only.
Images use 64-degree vertical FOV, 16:9 and each unchanged actual eye. Both
appear in the same render pipeline, with the same lighting/material handling.

Validation: fighter 63 checks, heavy tank 106, synthetic section geometry 15;
combat-five regression 497, main tanks 277, Red Devil 55. Repeat builds leave
runtime resources and receipts byte-identical; repository invariants pass.
All new tests are wired into CI. New texture count: zero.

Branch `agent/cra-cockpit-connections` stacks on `agent/walker-cockpits` / #316
at `b3f5f310`, retaining the accepted work. Native visibility of `*11*` batches,
motion/recoil, projectile/flash appearance, HUD/weather/damage, performance and
all GOG/Steam/Proton/Wine runtime lanes remain unverified. No native loading,
firing synchronization or gameplay claim should be inferred from these renders.
