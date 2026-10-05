# Mission 02B offline and co-op

Red Arrival uses the same `misn02b.bzn` / `misn02b.lua` in the campaign
(`MISSION1`) and multiplayer strategy (**CR: Red Arrival Coop**). The map uses
`MultSTMission` with four native spawn buoys at the original player start.
Use matching CR/EXU builds on all peers; select tank or scout in the lobby.

Host on team 1; guests select distinct teams 2–4. Start with everyone present.
Enemies use team 6, and authored friendly defenses use team 7. Team 1 retains
production and scavenger control. Every connected human must enter a vehicle
to complete the opening objective. Native strategy respawns use 999 lives;
online human death does not fail the convoy. Offline retains player-death loss.
The authored scavenger, base and recycler failure checks and rescue/debrief
remain. A camera skip releases only that player's camera online.

Only the original team-1 host runs mission progression, waves and AI. AI world
observation includes replicas, but behavior registration excludes remote and
human craft. Clients run local presentation/input updates. Local team owners
apply starting resources. HUD, audio, markers, names, cleanup and results use
ordered `E` events / cumulative `A` acknowledgements; `C` camera snapshots have
serials and cinematic generations. Missing dynamic handles wait up to five
seconds before a stale marker drops. Terminal events wait for prior event ACKs.
EXU disables the native extra recycler before Init. Offline autosave/save/load
and original cinematic skip behavior remain.

Guest departure releases readiness. Host departure ends the mission;
host migration does not transfer campaign authority. Late join/rejoin pauses
progression and requires restarting with all players present.

## Validation and limits

Run `python Tools/Test-Misn02bCoopContract.py`,
`lua5.1 Tools/Test-Misn02bCoop.lua`, and
`lua5.1 Tools/Test-BZRPeerTransport.lua`.
The complete mission runs in four isolated Lua 5.1 environments with the real
CRCoop registry, separate object replicas and delayed dynamic creation. Both
unreliable delivery and reliable delivery with initial loss/reordering exercise
the same victory path. Additional cases cover loss, offline load/death,
camera skips, respawn, departure, migration and late join.

The transport model follows the current GOG BZRNet envelope and sequence/ACK
behavior documented in OpenShim's
[paired-client capture](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/main/reverse_engineering/bzrnet_protocol_capture_20260321.md).
Reliable packets wait across a gap; duplicates cannot dispatch twice. The
model selects reliability explicitly because the exact Redux Lua `Send`
binding has not been traced. Timing is a configurable scenario assumption;
Lua wire serialization, physics, native object replication and EXU hooks are
not emulated. Passing these tests does not qualify live multiplayer.

Before release, run two real clients to check map discovery/loading, native
spawn ownership, extra-recycler suppression, guest camera/HUD, object replication,
respawn and terminal debrief. Nucleus Co-op can provide the two processes on
one Windows machine if its handler preserves this CR/EXU/OpenShim configuration.
Record whether it uses the stock BZRNet route or a replacement transport.

PowerShell is unavailable in the implementation environment. The shipping lock
was extended with only INI/BMP/DES/VXT members and checked statically; run the
normal `Manage-CampaignFiles.ps1 -bless` review and deployment on Windows before
native testing. No deployment or Workshop publication was performed here.
