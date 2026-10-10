# Co-op admission before Initialize - 2026-10-09

The host can receive a guest's `Q` handshake before mission `Start()` calls
`CRCoop.Initialize()`. Previously the host immediately marked that guest ready
and sent `K`. Initialize then cleared its ready flag and handle; the guest had
already accepted `K`, so it stopped retrying Q. The host waited indefinitely
for a handshake it had already acknowledged.

The private four-client GOG run `retry-battle-t1000x2500-i1-p1-20261009-183000`
captures that order directly on host c0:

| Time CDT | Event |
|---|---|
| 18:32:14.676491 | Guest c2's Q forwarded to host |
| 18:32:14.676997 | Host Receive after Q: player 3 ready=true, valid incoming handle |
| 18:32:14.677497..14.677999 | Initialize clears player 3 ready and handle |
| 18:32:14.677299 | Host K forwarded to c2 |
| 18:32:14.693533 | Guest c2 consumes K and subsequently stops Q retries |

The later Q requests from c1/c3 complete; c2 sends no second Q. Host readiness
never completes, and the run stops INCOMPLETE before impairment or battle.
Stock timers were verified on all four clients. No native crash occurred.
Independent capture audit: 40,729 decisions/submitted outcomes on twelve links,
zero missing outcomes/correlation errors/source-send mismatches, four clean
untruncated native captures with zero dropped events and full binary retention.
The causal Q/K copies have source send, socket submission and target receive
evidence. Forty-eight other RX deficits remain recorded (39 after final P2P
receive, nine earlier); a clean capture does not prove every event was recorded.
No relay loss caused the observed admission state reset. Payloads, identifiers,
exact raw records and dumps remain private outside Git.

`Scripts/CRCoop.lua` now consumes early Q/K/P messages without admitting state
or sending an acknowledgement. Update/session readiness waits for initialization
to finish. Existing guest retries request a fresh handshake after initialization.
Initialize still clears prior mission readiness, phase and remote handles;
post-initialization messages, protocol version checks and leader authority keep
their existing behavior. No new wire message or timer setting is introduced.

`Tools/Test-CRCoopAdmission.lua` reproduces the early acknowledgement failure on
the original source and passes on the fix. It also checks early K/P, guest retry
and acknowledgement cessation, reinitialization, wrong version/non-leader ack
and single-player readiness. Existing CRCoop tests pass. Complete-script Lua
5.1 tests pass for misn02b (11,994 checks), misn03 (6,251) and misn04 (27,722).

Live validation is in progress with four internal clients and the passive
admission trace. The test applies exactly this admission-only source diff to
the immutable respawn-enabled release test baseline, preserving its existing
respawn features. The canonical source and release variant differ outside the
changed admission blocks; both variants pass the same lifecycle and registry
tests. This is a private test override, not a Workshop or installed-campaign
publication. GOG integration, Steam, Proton/Wine and longer-session outcomes
must be reported separately.
