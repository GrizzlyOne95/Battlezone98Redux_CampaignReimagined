# Coop Diagnostics PDA page — 15 October 2026

Branch `agent/coop-diagnostics-20261015`, based on fresh main `e88dc1cb` after
the HUD defaults merged. No open CR PR overlapped these files at branch creation.
Mission 15 is untouched. This is source and native local acceptance, not a release.

## Player view

X opens Co-op; ] opens **Coop Diagnostics**, page 2/10 online. Solo retains its
eight pages and skips both co-op pages. Up/Down selects a human player for detail;
the overview always shows every human's name, co-op state and remote native
ping/loss. Selection has no gameplay action. M remains the stock scoreboard toggle.

Details show network id/team, host/local role, peer phase/protocol, elapsed time
since received co-op traffic and heartbeat, control message Tx/Rx, outstanding
action receipts, retries, acknowledged/expired actions, native kills/deaths and
native ping history count. Reads are local observations; different clients can
show different link measurements. Native snapshots are sampled at most once per
simulation second while the page is drawn. Native faults/missing rows clear the
cached data; unavailable metrics are labelled, not synthesized as healthy zeros.

The [EXU #111](https://github.com/GrizzlyOne95/ExtraUtilities/pull/111)
GetPlayerNetworkStats follow-up adds remote pingSamples (0-10). A zero
count displays waiting for samples. Local ping/loss/samples are n/a. Retained
samples do not prove the link is still active; the observer supplies freshness.
Native loss is the stock short-window indicator, not long-window UDP loss.
Older EXU without this count still provides its existing ping/loss; missing
native APIs degrade to unavailable. No runtime version-string test is required.

## State meaning

| State | Evidence |
| --- | --- |
| Syncing | No current heartbeat, or the peer reports admission incomplete. Local readiness uses the existing CR admission state. |
| Synced | Recent heartbeat, peer-reported admission, matching protocol and current campaign phase. This describes CR admission/phase, not equality of all simulated world objects. |
| Readiness unknown | Fresh legacy heartbeat lacks admission/phase metadata. |
| Phase differs / Protocol mismatch | Current peer heartbeat disagrees with local phase/protocol. |
| Heartbeat delayed | Heartbeat is at least 3 simulation seconds old, but other known-peer CR traffic is recent. |
| No recent traffic | No observed CR control/application traffic for at least 3 simulation seconds. |
| Traffic stalled | No observed CR control/application traffic for at least 10 simulation seconds. Native ping can still be healthy. |
| Player unavailable | No valid current player craft/pilot handle. |
| Restart required / Host left | Existing late-join or campaign leader departure state. |

The thresholds are explicit CR diagnostics rules, not native connection timeouts.
They measure mission simulation time (including its pause/speed behavior).
Fresh evidence recovers immediately. Initialize clears all observations; departed
ids are forgotten and removed from selection. A heartbeat lacking optional
metadata clears any old claim. The added fields ride the existing half-second
handle broadcast; older clients still consume its first handle argument. No new
diagnostic polling message or change to gameplay admission/reliable policy occurs.

Control counts cover CR H/Q/K/P/L sends/accepted receives; Tx counts attempts to
known human peers, not delivery. Action counters cover the existing J service's
receipts/retries, including duplicate receipts and timeout behavior. Neither is
an engine packet/byte/rate counter. Application traffic freshness admits only a
known-peer, matching-protocol envelope and matching current player handle.

## Native and regression evidence

Three real GOG DX11 clients use the configured loopback DedicatedServer
`50b6b14d8`, the previously qualified OpenShim startup-hash chain and a fresh EXU
sample-count DLL. The private stage contains the seven modified/new Lua runtime
files, confirmed byte-identical to this source, plus the prior DX11 source fixes.

`recovery1015-coop-diagnostics/recovery1015-coop-diagnostics-acceptance` passes
five steps / 22 checks: roster/alliances, every peer's admitted heartbeat/native
samples, physical X/]/Down navigation, withheld host CR messages producing quiet
then stalled labels while native ping history remains populated, and recovery
without reopening the PDA. Clean Lua/Ogre/subtitle checks and final survival pass
on all three clients. A second visible-capture pass gives receivers foreground
time because background D3D clients can retain their last presented image:
`recovery1015-coop-diagnostics/recovery1015-coop-diagnostics-visible` also passes
five steps / 22 checks; native screenshots show the stalled host row, populated
native ping/loss and elapsed receive/heartbeat ages, then fresh Synced rows.

Loss injection is explicitly a temporary outbound Lua-message filter, restored
in finally; it does not impair native transport or change native ping/loss.
The first fixture assigned Send only in the probe's scratch environment, so it
did not withhold real traffic and failed its precondition. It is retained as a
failed fixture attempt, not a game verdict. The corrected fixture modifies the
mission global temporarily and verifies that actual calls were withheld.
Player/objective healing is explicit test assistance, not story qualification.

Lua suites cover admission lifecycle, fresh/quiet/stalled/recovered traffic,
non-heartbeat/application freshness, false/legacy admission metadata, phase and
protocol mismatch, invalid handles, departures/reused ids, native refresh errors,
missing measurements, read-only counters and four-player view data. Standalone
fixtures that load the real registry explicitly include the Scripts/ module
search path, and closed module maps include the real diagnostics factory.
Existing mission 02b-14 co-op suites and affected offline/presentation suites pass.
The shipping lock adds only CRCoopDiagnostics.lua (2,538 to 2,539 entries); existing membership
and order are preserved. Windows Steam, two-PC/WAN, Proton and Wine remain
unqualified; Lua and native optional-feature behavior remain store-neutral.

## Additional useful engine hooks

OpenShim already owns native reliable-send backlog/retry patch sites, socket
send/receive/completion observation, routing configuration and receive/reorder
research. A future bounded read-only EXU/OpenShim bridge could add:

- Reliable queue depth/bytes, age of the oldest unacknowledged fragment and
  native retransmission/ack counters, qualified per peer.
- Actual completed packet/byte rates and last transport receive time, with
  overlapped Winsock completion accounted for so submissions are not double-counted.
- Receive sequence-gap/rejection/reorder/duplicate counters and route state
  (direct/relay), separately from the matchmaking server selection.
- Native ping sample timestamps/jitter once the released-build units, clock,
  sampling window and player lifetime are established.

These are useful extension points found in current public code, not new values
exposed by this PR. Mapping transport endpoints/relay peers to player ids and
resetting per-session counters must be established before displaying them.
Diagnostics should copy thread-safe snapshots on the game thread, fail closed
on unsupported identities, and never enable verbose tracing, retune timers,
change routes or infer world-state parity just to populate the PDA.
