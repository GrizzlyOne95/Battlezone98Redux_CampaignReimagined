# Olympian and Fury arc mines

Owner amendment, 16-17 October 2026: distinguish the ancient Mars mine from the
later Fury version in appearance, armament and damage. The stock inspection
text `boltmine.inf` explicitly says the Fury mine delivers much more damage
than the Olympian version. The exact ratio and new visual treatment below are
CR design choices, not invented stock lore.

| | Olympian | Fury |
| --- | --- | --- |
| ODF/model | `cromine` | `crfmine` |
| Hull | Aged golden bronze, sweeping engraved seams, amber energy apertures | Dark ribbed biomechanical metal, cyan energy apertures |
| Weapon | Olympian Sun Arc (`cromarc` / `crom0`) | Fury Storm Arc (`crfmarc` / `crfm0`) |
| Discharge | Narrow amber filament, restrained movement | Two thicker cyan strands, short jagged segments and wider forks |
| Native beam damage coefficient | 40 | 100 (stock Fury strength) |
| Scan / weapon range | 100 m / 100 m | 100 m / 100 m |
| Mine health / scrap value | 1000 / 0 | 1000 / 0 |

Both remain clearable, persistent defensive mines with no ammo exhaustion. The
Fury version's coefficient is 2.5 times the Olympian version. This is a beam
coefficient, not a claim of 100 damage per second; native firing timing determines
actual continuous damage.

The fresh diffuse atlases use the stock mine's UV layout. Lenmos/`oblema` supplied
Olympian art direction; the stock Fury models supplied Fury art direction. The
original low-detail mine diffuse is a layout guide, not the new painted surface.
Each variant also has a fresh emission atlas; a newly generated neutral filament
is independently colored/shaped by the two native render definitions. The builder
performs DDS conversion only and copies the stock mesh/SDF/skeleton, changing only
the Ogre resource links. Geometry, collision, UVs, bounds and skeleton stay stock.
Source PNGs, prompts and stock hashes are under `References/BoltMines`.

## Mission selection

- Mission 05: all 23 scripted Mars volcano mines use `cromine`, preserving the
  original positions, hostile team, detection radius and clearance behavior.
- Mission 15: all forty mines in the Tartarus response use `crfmine`.
- Mission 16: all six authored mines are swapped in the BZN to `crfmine`; their
  original labels and placement stay intact. The scene builder makes the same
  substitution when rebuilding from the preserved amended map.
- Mission 17: the marked roster adapter maps both `boltmine` and `boltmine2` to
  `crfmine`, without advancing its fighter counter. Both 53-mine branches keep
  their original trigger, positions, clear/destroy handles and source order.
- Mission 14 and 18 have no authored stock arc mines. The shared later-mission
  adapter will select the Fury variant if either mine ODF is requested later.

No global override of stock `boltmine`/`gmbolt`/`mbolt` is shipped. Human mine
dispensers and unrelated maps therefore keep their existing behavior.

## Validation

`Tools/Test-BoltMines.py` checks model preservation, the independent weapon and
texture chains, damage/range, BZN swaps and shipping admission. Mission 05's
contract/presentation checks and Mission 15/16/17 regression suites cover the
integration. `Test-BoltMinesLive.ps1` is a private native fixture: it uses an
unarmed stationary tank as the target, samples each mine's damage over simulation
time, captures the hull/discharge, then checks replicated destruction. Unit AI
setters are applied only to the known tank, never to either mine.

Native evidence and screenshots are added after the fixture completes. Full
mission combat balance, Steam and Proton/Wine remain unverified prototype lanes.
