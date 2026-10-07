# Co-op respawns and lives

Applies to the co-op missions that use `CRCoop` (`misn02b`, `misn03`, `misn04`, `misn05`).
Single player is unchanged: death ends the mission.

## Lives

Each player has `CRCoop.COOP_LIVES` (5) lives, counting the current one. Each
death costs one; a death with none left **fails the mission for everyone**. The
player who ran out tells the host (`Send` "L", repeated until the mission ends);
the host runs the mission's `onOutOfLives` option, which calls the mission's
`FailMission`.

CR counts lives itself. Native lives are set to 999 because at zero native
MultST calls `do_escape()` and drops that player out of the match, with no way
back in.

## Where a respawn lands

Native MultST respawns the player as a pilot near the team start location
(50 m up). `CRCoopRespawn` watches the local player and moves that new handle
(owned by the respawning client, so the move replicates) to the first of:

1. A living teammate whose handle has not changed for 8 s. That excludes a
   teammate who just respawned at the start, so two players who die together do
   not follow each other there.
2. The mission's rally point for the current phase, if it declared any:
   `CRCoop.Initialize({ rallyPoints = { [phase] = "path_or_label" } })`. The
   highest phase not above `CRCoop.GetMissionPhase()` is used. Mission 05
   declares Montana for phase 1 and Lemnos for phase 2; native MultST consumes
   the team-start buoys during initialization.
   Object labels resolve through `GetHandle`; `GetPosition(string)` alone reads
   a path and can silently return the map origin for a label.
3. The player's last safe position: sampled every 2 s while alive, settled and
   with no enemy craft within 200 m, and at least 15 s older than the death.
4. Otherwise the native drop point.

A respawn is the first new player handle after native lives drop
(`Net::KillPlayer` decrements them on the player's death). Ejects and hop-outs
cost no life and are left alone. The player sees `[CO-OP] Respawned near <name>.
Lives left: N.`

Native respawn pops every camera, so a player who respawns during a film leaves
that film.

## Tests

- `Tests/test_coop_respawn.lua` (`lua Tests/test_coop_respawn.lua`): detection,
  target choice and lives with engine mocks.
- Two real clients: BZR-OpenShim-coopflow scenario `coop-respawn` (misn03):
  respawn near the host 778 m from spawn, both players dying together, and the
  fifth death failing the mission on both clients.
