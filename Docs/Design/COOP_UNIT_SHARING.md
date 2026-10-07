# Co-op unit sharing and pilot rescue

Design prepared 2026-10-07 for OpenShim / EXU / Campaign Reimagined.

**Recommendation:** integrate sharing and rescue into a keyboard-operated **Co-op page in the existing Battlezone PDA**, backed by a host-coordinated, owner-executed transaction service. Make Co-op the opening page while campaign co-op is active. Transfer the existing unit through Redux's distributed-object ownership machinery, then explicitly synchronize the team-related state and re-establish commandability. Use that same transfer service to give a stranded guest a rescue craft.

This is a design and investigation, not an implemented or live-qualified transfer API. Existing paired-client evidence establishes several prerequisites, but does not establish a working AI-unit handoff. This checkpoint contains the design and an illustrative preview. No game scripts, server rules or native binaries are changed.

Open [the interactive PDA preview](coop-pda-sharing.html) in a browser. Controls above and below the PDA simulate player selection and key presses; the proposed in-game PDA uses keyboard input. The preview is self-contained and performs no game or network operations. The [editable preview source](coop-pda-sharing.fragment.html) is an HTML fragment; the standalone file includes its browser wrapper.

## What the current work establishes

### Source and working state

| Repository | Inspected source tree | State observed |
|---|---|---|
| OpenShim | `BZR-OpenShim` | `agent/daywrecker-lifecycle`, `d37aa851`; unrelated investigation changes present |
| Campaign Reimagined | `Campaign-Reimagined` | `agent/misn02b-coop-start`, `388445f`; further uncommitted camera guards in `Scripts/misn02b.lua` |
| EXU | `ExtraUtilities` | `agent/hud-ring-gauge`, `f4f8c2f`; unrelated ring-gauge changes present |
| Multiplayer flow harness | `BZR-OpenShim-coopflow` | `agent/coop-mission-flow`, `5579745f` |
| DedicatedServer | `Battlezone98Redux_DedicatedServer` | `agent/client-decomp-validation`; local Claude metadata present |

The Documents/GIT CR checkout is canonical. The retained Google Drive tree and generated installed/staged copies are not editing targets. The game installation itself is not a Git repository. These observations are a snapshot; other sessions are active in this workspace.

Reviewed Claude session excerpts include the October 5 paired-client work, camera audit, server/lobby fixes and October 6 server launcher work; the game-root handoffs and `bzr-same-pc-mp-harness.md` connect those sessions to the current test rig. Older notes about CR authority and ownership are superseded by current AGENTS.md and the October 7 replication measurements.

### Relevant established behavior

The CR contract uses distinct allied human teams 1–4. Team 1 plus `IsHosting()` determines campaign authority. Guests have their own player objects; they do not run campaign progression or receive extra starting recyclers. Host departure ends the campaign, and late joining/rejoining requires a restart. Sharing must preserve that contract.

The October 7 `cr-misn03-repl-4` run used two real GOG Redux clients and the local relay server, with separate fresh objects and a six-second observation window:

| Operation | Measured result | Design consequence |
|---|---|---|
| Host `BuildObject` craft/building | Replicated | Existing host production/spawning remains the initial source of shared units |
| Guest `BuildObject` craft/building | Local only; `IsLocal` false even on guest | A guest cannot safely manufacture a replacement using stock `BuildObject` |
| Live handles sent in either direction | Resolved to the intended object | Send native handle userdata, with separate transaction identity and generation |
| Host `SetTeamNum` on a host-owned building | Local only | Team color/number changing on one screen is not a transfer |
| Names, custom max health and weapon changes | Local only in the tested cases | Explicitly synchronize required nonreplicated state |
| Guest mutation/removal of host objects | Ignored, reverted, or divergent | Execute authority-sensitive work on the actual owner |
| `Send` string argument of 128 bytes | Receiver crashed | Keep every string below 128 bytes, measured in bytes; avoid free text in this protocol |

These are findings for the tested object classes and operations, not universal claims about every craft/class. The current shared reference's approximate 244-byte budget is a conservative message-design target, not proof of the exact Redux encoder capacity. The newer capture notes trace a larger encoder buffer; this feature need not approach either limit.

The flow harness demonstrates assisted mission progression, presentation parity and selected world parity. It teleports objects, kills waves and advances timers, so it does not certify normal combat. Some runs labeled PASS contain warnings. The later misn02b host-skip run failed with a camera-stack alert; the canonical checkout has additional camera work in progress. Start transfer qualification with a minimal fixture or stable misn03 staging, independently of that camera issue.

### Native ownership lead

I recovered the installed executable's Lua registration entries and inspected the corresponding static instructions with Capstone, using the best-effort Redux corpus as supporting context. The installed executable SHA-256 was `8D71F56C1314E69A8AD38F4EEAF20A8FF825965A84CF196E5F77EA4CC3377413`.

The stock `SetLocal` route has a real remote-to-local transition, changes distributed-object bookkeeping, emits an ownership-grab message, and publishes permanent state. `SetTeamNum` follows a separate team-setter route. This is a credible basis for preserving the original object rather than replacing it.

**Static evidence is not live qualification.** The project explicitly reports broken remote-AI behavior after casual `SetLocal`. Native AI-process creation/retirement, command slots, embedded pilot-team state and packet ordering remain the central investigation. This design does not assume that adding acknowledgements makes unsafe `SetLocal` calls safe.

### Approaches considered

| Approach | Assessment |
|---|---|
| Broadcast `SetTeamNum` on every peer | Can address the measured team divergence, but by itself establishes neither ownership handoff nor working guest commands/crew lifecycle |
| Recipient calls unwrapped `SetLocal`, then changes team | Has a real engine ownership route, but project AI failures make it an unqualified implementation |
| Qualified same-object handoff | Preferred: preserves mission references and unit state; native AI and team-slot activation must pass first |
| Host retains all ownership and relays guest orders | Useful for a limited tactical-order panel; it does not establish the requested normal guest unit-control/boarding behavior without further native work |
| Clone on recipient, delete original | Risks lost references, duplicates, resource changes and guest-local-only spawning; no automatic fallback |

## Player experience

### Existing PDA integration and defaults

Use the PDA that already exists in `PersistentConfig.lua`, `PersistentConfigData.lua` and `PersistentConfigP.lua`. Reuse its EXU overlay IDs, layout, selected-row rendering, configured color/font/opacity, feedback channel and menu sounds. The co-op page supplies content and actions; it does not create a second command window or require a mouse cursor.

Keep the established controls: **Y** opens/closes the PDA; **[ / ]** changes page; **Up/Down** selects a row; **Left/Right** changes the row's recipient or option; **Enter** activates the selected action. Mouse motion continues aiming the tank, and mouse buttons remain gameplay inputs. No clickable controls, mouse focus, Shift mouse-menu mode or extra default modifier chord is needed for this page.

Add a stable `PdaPages.COOP` identity without renumbering the existing eight page IDs. Build the visible navigation order separately: Co-op first during campaign co-op, followed by the existing pages. Derive the displayed page position/count and bracket-key cycling from that visible list rather than cycling the raw integer `PdaPages.COUNT`. Hide Co-op outside campaign co-op; solo campaign retains its current default and navigation.

Treat campaign co-op activation as explicit mission integration plus a network session, not merely `IsNetGame()` in any game mode or a count of two connected players. A host waiting alone in a co-op lobby still gets the page. On entering an active co-op mission, default the initialized PDA to Co-op. Every subsequent closed-to-open **Y** transition starts there. A player may browse another page until closing; refreshes, incoming requests and teammate changes never force an already-open PDA back to Co-op. Do not turn PDA visibility on merely because co-op begins. If the mission stops being co-op while the page is visible, fall back to Vehicle and clear uncommitted actions.

The page shows a small teammate roster, the selected craft, **Give unit**, and the appropriate rescue rows. Hosts also get **Respond to rescue**, **Auto rescue: Off / Reserve only**, and **Selected craft: Normal / Rescue reserve**. Pilots get **Rescue me** and cancellation of their pending request. Guests in vehicles can give to any admitted teammate, including the host. Inactive or unqualified service actions show a specific unavailable reason.

### Keyboard confirmation and selection safety

The first **Enter** on Give or Send rescue captures an exact unit identity/revision and shows a confirmation such as **Give Grizzly 01 to Ada? Enter to confirm**. Commit only on a separate key-down after release; held keys/repeat must never both arm and confirm. For nearest rescue, choose and display the actual candidate at review time, then revalidate/reserve that same craft when confirming. If it becomes unavailable, reject the action and require a new review rather than silently substituting another craft.

Changing row, recipient or page, closing the PDA, loss of input focus, mission transition or an expired review clears the uncommitted confirmation. Merely moving the aiming reticle or changing the stock selection never retargets an armed action: its displayed captured craft stays fixed. Revalidate life, ownership, mission policy, recipient admission and pilot generation at commit. Closing the PDA after a transaction has committed hides its display but does not cancel the network operation.

### Give a unit

1. Select a unit normally, then press **Y** to open the PDA on Co-op. **Give unit** is the initial selected row for a player with an eligible selection; a living pilot can start on **Rescue me**.
2. Use **Left/Right** to choose an eligible recipient by player name, with team as secondary information. The selection display names the craft; it never substitutes the object under the aiming reticle.
3. Press **Enter** to review the named craft and recipient, then press **Enter** again to confirm. Both players see “Transferring Grizzly to Ada…” followed by either “Ada now commands Grizzly” or a concrete rejection reason.
4. On completion it leaves the sender's selection and becomes available through the recipient's normal unit command menu. Optionally select it on the recipient, without changing the recipient's current vehicle.

The same flow handles host → guest, guest → host, and guest → guest. The sender authorizes the gift; the host arbitrates it automatically. Routine guest gifts do not require an additional host approval. Recipients can opt out of gifts in their co-op preferences. A return is a new transfer; record the previous controller to offer a convenient **Give back** action.

Use names for decisions; team numbers are secondary. Do not equate a lobby network player ID with its team. Start with one unit per operation. Later group giving can report individual successes and rejections rather than pretend that several distributed objects move atomically.

### Rescue me

When the local player is a living pilot, the Co-op page offers **Rescue me** prominently. Select it with **Up/Down** and press **Enter** to send the request. The same row becomes **Cancel pending rescue** until assignment commits. The request broadcasts a short notification and pilot marker to teammates, and stays in the host's rescue queue. It does not spawn a ship or change the pilot's team. When the PDA is closed, use its existing feedback channel for a short request/assignment notice.

The host selects a pending pilot request, then uses the **Respond to rescue** row with **Left/Right** to choose **Selected craft** or **Nearest suitable craft**. **Enter** reviews the actual chosen craft and intended pilot, then a separate **Enter** confirms. The selected option is the precise manual path; the nearest option finds the closest eligible host-controlled craft. **Automatic dispatch** is an opt-in PDA setting using craft explicitly marked as a rescue reserve. This prevents repeated requests from taking essential defenders, tugs or scavengers. If several pilots are waiting, provide a separate request-selector row; preserve the selected player's identity when the queue changes.

Default assignment sequence:

1. Reserve a craft for the request and transfer it to the pilot's team using the ordinary handoff service.
2. After ownership and commandability are verified, that craft's new owning peer issues `SetCommand(craft, AiCommand.RESCUE, 0, currentPilotHandle)`.
3. Native rescue/boarding behavior brings the craft to the pilot. The player boards normally; completion is confirmed by the recipient's current player handle becoming the assigned vehicle.

Issuing the rescue order after transfer keeps craft and pilot under one team and one local owner. It avoids relying on unqualified cross-team rescue. `Pickup` is not the rescue operation: it has scavenger/tug/deployment semantics.

The panel tracks Requested → Assigned → En route → Ready to board → Rescued. Only show Ready to board when actual native state supports entry. Native automatic pilot dismount/boarding behavior must be tested; if that behavior needs a wrapper, expose the smallest qualified operation. Do not force `exu.SetAsUser`, destroy the current pilot, or remove an AI pilot as a substitute for boarding.

One active rescue request per player; repeated input updates it without repeating announcements. The request carries a pilot-handle generation, so ejection, boarding, death and respawn invalidate stale work. Guest craft can also be volunteered for another guest's rescue, but automatic selection never takes another guest's units without consent.

## Authority and transaction design

There are three separate identities: campaign leader, unit's gameplay team, and native network owner. The host approves and sequences transfers; it must not mutate a guest-owned replica as if it owned it. `SetOwner` is not an API for assigning a network player as distributed-object owner.

Maintain a session-local share ID for each admitted unit, plus a revision and local handle mapping on each peer. Lua handles travel as native userdata; never convert them to guessed numeric pointers or assume their printed values match across processes. Ownership-grab bookkeeping can change native identity mappings, so the wrapper must preserve or explicitly update the mapping for the same live object.

```mermaid
sequenceDiagram
    participant S as Sender
    participant H as Campaign host
    participant O as Current native owner
    participant R as Recipient
    participant P as Other peers
    S->>H: Request gift (unit, recipient, revision)
    H->>O: Reserve and prepare
    H->>R: Resolve object and prepare
    O->>H: Prepared; Lua managers suspended
    R->>H: Prepared; live replica present
    H->>R: Single-use ownership grant
    R->>R: Qualified native claim
    R-->>O: Redux ownership-grab path
    O->>H: Observed remote ownership
    R->>H: Observed local ownership
    H->>R: Apply team and establish commandability
    H->>O: Apply replica team state
    H->>P: Apply replica team state
    R->>H: Verified state
    O->>H: Verified state
    P->>H: Verified state
    H->>S: Gift complete
```

### State machine and checks

**Validate / reserve.** Derive the requester's team from native player callbacks. Verify they control this unit's team, the recipient is connected and admitted, alliances and capabilities match, the object is live, the expected revision matches, and no other operation owns its reservation. Validate again at every mutation boundary. Reject another player's unit, a human-occupied craft, an enemy, a mandatory mission asset, or an unqualified class.

**Prepare.** Suspend donor aiCore/PilotMode/micro-manager work for this handle. Preserve object state in place. Block stock commands and boarding that would race the ownership transition through a qualified per-unit native guard; a Lua flag alone cannot fence engine actions. Damage and destruction remain normal. The recipient resolves its native replica before acknowledging preparation. Missing replicas wait briefly; matching a similarly named object is forbidden.

**Claim.** Only the designated recipient may claim, once for a grant and revision. The initial candidate is the engine's native grab route wrapped by EXU. Never call `SetLocal` on every peer. Do not set a raw owner field or invent an ownership packet. The donor retires its local simulation through the engine's receive path and acknowledges observation; it does not immediately grab the unit back.

**Apply / activate.** After ownership convergence, apply required actual/perceived team state through qualified setters on every peer. Publish required owner state and establish the recipient's native AI process and command-menu slots. Update embedded crew-team/abandonment state where required: otherwise a later hop-out may create a pilot on the old team. Clear stale donor orders and script registrations, set a commandable default order, then release the lock. The host keeps mission observation and critical-handle references; it stops issuing gameplay orders for donated units.

Guest managers must execute locally on each guest for transferred units, without enabling campaign progression or late `SetAIControl`. Returning to the host re-admits the handle to the correct manager only when that unit is intended to be automatically managed. Transfers do not create another player record or change anyone's player team.

**Verify / complete.** Require donor remote, recipient local, remaining peers remote, agreed actual/perceived team and revision, a valid native AI process where applicable, correct team-slot membership and preserved object state. An ACK for receiving a packet is not an ACK for completing a transfer. Observe convergence across simulation updates; avoid assuming a single fixed-delay wait proves it.

**Failure.** Before any claim, release preparation and resume the donor's eligible managers. After a claim might have occurred, enter reconciliation: query owner state and continue or perform a separately authorized compensating transaction. A timeout alone must never trigger a competing claim. If ownership cannot be established, quarantine further sharing for that unit and surface the synchronization failure; require a restart if the session cannot recover. Never silently duplicate, recreate or delete the unit to mask uncertainty.

### Scope of “any unit”

The intended service covers all ordinary AI units on human teams, regardless of whether their controller is host or guest. Ship class support only as it passes native tests. Start with free mobile tank/scout craft, then extend to artillery/turrets, utility craft and optional producers.

Busy production, towing cargo, recycling, docking and deployment transitions require either an explicit safe completion/cancellation path or a temporary “finish this job first” rejection. Deployed turrets are a separate qualification lane, not permanently excluded. Mandatory recyclers, mission convoy vehicles/relic cargo and scripted actors use mission policy callbacks to reject unsafe transfers. A player-driven vehicle requires its human to hop out first; changing a human's team or teleporting their control is outside unit giving.

In-place transfer preserves damage, custom maximums, ammo, weapons, transforms, labels and mission references. Verify pilot accounting and crew behavior so transfer/return/rescue/recycle cannot generate extra pilots or scrap. Do not add resources merely because a team changed. Existing projectiles/mines retain their own recorded ownership; future firing must use the craft's new owner.

## Protocol and integration

Reserve one unused **one-character** Lua packet type, e.g. `U` after auditing all consumers, with compact numeric opcodes. CRCoop uses H/Q/K/P; current mission presentation uses E/A/C. Keep the sharing transaction stream independent so a delayed presentation marker cannot block an ownership grant.

A minimal message carries protocol version, mission/session epoch, transaction ID, unit share ID and revision, recipient ID and opcode-specific arguments. Bind deduplication to sender + session + transaction, not a counter alone. Include the epoch on delayed requests/grants; reset explicit state on repeated Start and Lua-state closing. Use finite Lua 5.1-compatible integer ranges.

Use retries and acknowledgements above `Send` even if its native transport proves reliable. Duplicate messages return recorded results; they never repeat claim, resource or rescue effects. No Lua tables on the wire. Keep messages comfortably below the conservative payload budget; split metadata. ODF names and short codes fit short strings; player names and translated error messages are local UI data, not repeated packet text. Strictly enforce the 127-byte string ceiling at the serialization boundary.

Resolve authority from native player records and `Receive(from, ...)`, then validate the host and expected actor at each stage. Do not accept a packet's claimed source team, owner, arbitrary Lua chunk or command. CRCoop's current handshake can fill a team from packet arguments; sharing must not treat that field alone as an authorization source. Extend the registry with authoritative player/team identity and pilot revisions.

Suggested proposed surfaces, **not existing APIs**:

| Owner | Proposed responsibility |
|---|---|
| EXU | `GetSelectedHandles()` snapshot, native object owner/identity/crew/AI inspection, qualified claim/activation helpers, per-unit transaction lock, thin Lua bindings |
| OpenShim | Required low-level fixes, build/signature qualification and consuming modal input before stock dispatch |
| CR `CRCoopUnits.lua` | Reservations, transaction/retry state, validated player mappings and per-mission transfer policy |
| CR `CRCoopRescue.lua` | Rescue requests, reserve candidates, assignment and pilot lifecycle |
| CR `CRCoopPda.lua` | Co-op page model/rows, capture and confirmation state, recipient actions, existing PDA feedback |
| CR `PersistentConfigData.lua` / `PersistentConfig.lua` / `PersistentConfigP.lua` | Conditional page registry and opening default, keyboard dispatch and existing EXU PDA rendering |

EXU already provides overlays, selection setters, smart-reticle lookup and foreground-aware `GetGameKey`. It does **not** currently expose a selected-unit enumeration or a qualified transfer operation in the inspected public definitions. Do not confuse `GetReticleObject` with the selected craft. A reticle-target prototype can be explicitly labeled as such until selection inspection is qualified.

Suppress co-op input while typing chat, using pause/shell UI, in editor mode, watching a cinematic or changing missions. EXU's current `IsGameUiOpen` covers shell/pause, not proven chat focus. Reuse the PDA's keyboard dispatch, but qualify native input consumption: `PersistentConfigR.ConsumePendingGameKeyMatch` only removes a key from the Lua queue, and does not demonstrate that native gameplay/chat input was consumed. Route only the active PDA keys before stock dispatch, especially Enter versus chat and arrows versus steering; release that routing immediately when the PDA closes or loses context. Keep relative mouse aiming and mouse fire untouched. Shift already controls the stock mouse menu, so the new default uses the existing Y/arrow/Enter controls without a Shift chord.

Preserve overlays and markers owned by the mission. Rescue markers need their own local presentation slots or reference counting so cancellation cannot turn off a mission objective marker on the same handle. Reuse one notification slot rather than adding unlimited objectives to the stock ten-entry panel.

The dedicated server remains a lobby/relay service. It does not own campaign simulation and needs no unit-transfer rules. Production logic remains with team 1; an optional future guest requisition queue asks the host to build a craft, then uses the same sharing service.

## Implementation and qualification sequence

1. **Native feasibility spike, isolated copies only.** Trace stock grab, owner maps, AI-process creation/retirement, permanent-state publication, command slots, embedded pilot team and normal boarding. Test the smallest host ↔ guest handoff without any overlay. If the existing path cannot safely activate AI on the recipient, fix that missing native behavior before exposing sharing. No clone-and-delete fallback by default.
2. **Transaction service.** Implement serialized grants, generation checks, duplicate suppression and the owner/team convergence checks. Exercise them with isolated Lua 5.1 peers, then real Redux processes.
3. **PDA page and rescue.** Integrate the conditional Co-op page and opening default into the existing PDA. Add exact selection capture, keyboard review/confirmation, qualified native input guards, host queue and same-team rescue after transfer. Integrate aiCore's protected-command handling and suspend/resume hooks, replacing overlapping co-op auto-rescue scheduling. Retain offline rescue behavior.
4. **Extend classes and policy.** Qualify utility/deployed/producer lifecycles; add group transfer only after individual transactions are stable.

Use `BZRCoopSession.ps1` / `BZRCoopLobby.ps1`, the coopflow `Run-BZRCoopMission.ps1` runner and `CRFlowProbe` to act on and inspect each process independently. The runner stages into `C:/BZRCoop`, checks for existing games/ports and uses the machine-wide harness. Normal stops use the project's safe stop path. Do not alter live Workshop caches or refresh shared test instances during someone else's run.

Required first live cases:

| Case | Required evidence |
|---|---|
| Host tank → guest → host, repeatedly | Same physical unit, one owner, normal native orders/firing/boarding after every direction; no duplicates |
| Guest A → guest B, with a third observing client | Host remains mission leader; nonparticipant replica agrees; only B commands |
| Damage and weapon state before/after | No heal, reload, loadout loss, wrong max health or health disagreement |
| Eject/hop out/board after transfer | Player and AI pilot teams/owners correct; pilot accounting unchanged except normal native lifecycle effects |
| Duplicate, reordered and delayed grants | One claim per revision; old session packets cannot mutate a new match |
| Destruction during preparation/claim | No stale handle dereference, refund or resurrection |
| Sender/recipient disconnect | No competing ownership claims; leader departure follows existing campaign failure |
| Two simultaneous pilot rescues | Separate reservations; each craft rescues the intended current pilot |
| Respawn, moving pilot, destroyed rescue craft, no suitable craft | Request completes/cancels/reassigns explicitly; no free fallback vehicle |
| PDA opening/cycling in co-op and solo | Y opens on Co-op in campaign co-op; browsing is preserved while open; all existing pages stay reachable; no Co-op page in solo |
| Aiming, firing and changing selection during review | Mouse keeps gameplay control; confirmation retains the named craft; no reticle substitution |
| Chat, pause, film, held Enter and custom bindings | No accidental transfer, native chat, steering or stock command from PDA input; one deliberate press cannot arm and commit |
| Utility/deployed/producer classes | Cargo/job/team-slot/AI lifecycle correct; mandatory mission assets protected |

Record each peer's share revision, handle resolution, native owner, locality, team/perceived team, native AI presence, current command/target, health/max/ammo/loadout and player handle. Screenshots alone are insufficient. Check later movement, firing, death and return; an immediate IsLocal result is insufficient.

The present two-client rig can prove the first bidirectional case. It cannot prove guest → guest; run at least three real clients for that. After the local native prototype passes, test real two-PC networking and matching Steam/GOG builds, then the supported Proton/Wine lanes before release. Mocks and local relay success must remain labeled as their own evidence classes.

## Useful co-op additions

- A small roster showing pilot/vehicle status and assigned rescue, using existing CRCoop handle exchange.
- A host requisition queue with Approve/Decline and normal scrap/pilot costs; no guest-side replacement spawning.
- A reserve/mission-essential toggle so auto rescue has predictable candidates.
- Return-all controls for voluntary session cleanup, implemented as individual verified transactions.
- Transfer receipts with unit name, sender and recipient, plus a concise reason when rejected.

The most valuable first milestone is a demonstrably safe repeated tank handoff. Keep the Co-op PDA page compact until that engine behavior is proven.

## Design artifact checks

The interactive preview is illustrative and does not connect to Redux. It now depicts the existing PDA shell and keyboard controls, with preview-only scenario and keypress controls outside the PDA. Headless Edge checks passed for actual keyboard events, the conditional opening default and all nine/eight visible pages, separate confirmation, ignoring held Enter, retaining a captured craft across selection changes, host/guest/guest gifts and returns, manual/nearest/reserve-only rescue, request cancellation and simulated boarding. Desktop and narrow layouts were inspected. These checks validate the sketch only; native handoff and mouse/input routing still require real Redux tests. No new live game test was run for this design.

## Evidence references

Campaign Reimagined source:

- [CRCoop source](../../Scripts/CRCoop.lua)
- [Existing PDA and keyboard dispatch](../../Scripts/PersistentConfig.lua) — PDA update/input handling near line 6505 in the inspected checkout.
- [PDA page registry](../../Scripts/PersistentConfigData.lua)
- [PDA page text builders](../../Scripts/PersistentConfigP.lua)
- [Current Lua ownership reference](../BZR_LUA_AGENT_REFERENCE.md)
- [Existing aiCore rescue](../../Scripts/aiCore.lua) — `Team:UpdateRescue`, near line 11504 in the inspected checkout.

Companion/local evidence, identified by repository and path rather than machine-specific links:

- `BZR-OpenShim-coopflow/reverse_engineering/coopflow/REPLICATION_FINDINGS.md` — October 7 paired-client findings, inspected on `agent/coop-mission-flow`.
- `C:/BZRCoop/runs/cr-misn03-repl-4/replication-findings.md` — raw local paired-client findings; not bundled with this design.
- `BZR-OpenShim-coopflow/reverse_engineering/Run-BZRCoopMission.ps1` — co-op runner.
- `ExtraUtilities/Definitions/ExtraUtils.lua` and `ExtraUtilities/ARCHITECTURE.md` — inspected public API and ownership boundaries.
- Local Claude paired-client session `866b37a8-8b32-4576-986e-55fcb3bcc606` — process context only; session contents are not bundled.
- [Engine-maintainer Lua reference](https://battlezone.videoventure.org/lua_script_utilities.html) — useful for API meaning, with current Redux measurements taking precedence.
- [Official Redux manual](https://steamcdn-a.akamaihd.net/steam/apps/301650/manuals/BZ98R_Manual_GB.pdf) — stock menu/keyboard behavior.
