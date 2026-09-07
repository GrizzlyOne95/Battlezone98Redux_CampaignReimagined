# Campaign Reimagined (Canonical Source)

This is the authoritative Campaign Reimagined source tree for campaign content, Lua, materials/shaders, assets, packaging, and publishing.

## Authoritative Paths and Promotion
- Canonical source: `C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined`.
- GOG test game: `C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux`; runtime mod: `...\mods\3686673790`.
- Steam subscribed payload: `C:\Program Files (x86)\Steam\steamapps\workshop\content\301650\3686673790`.
- Required promotion: **edit canonical source -> validate/build -> `Manage-CampaignFiles.ps1 -deploy` to GOG -> test GOG -> build/upload Workshop item `3686673790` -> synchronize the Steam Roadmap discussion -> let Steam download it -> final Steam test**.
- A real Workshop publication is not complete until the Roadmap discussion at `https://steamcommunity.com/workshop/filedetails/discussion/3686673790/216888303627073611/` has been synchronized from OpenShim's canonical `Docs/STEAM_ROADMAP_BBCODE.txt`. Follow `docs/STEAM_PUBLISH_CHECKLIST.md`. Dry runs are exempt from public Steam edits.
- Steam/Workshop is never the development deploy target. Never copy source directly into Steam's Workshop cache or use it as a GOG fallback; final Steam evidence is valid only after upload/download.
- Use `Manage-CampaignFiles.ps1` for deploy/sync, Workshop staging, and publishing. `Local\Workshop` is generated staging, not a runtime. `BZR_CAMPAIGN_RUNTIME_DIR` may override the GOG runtime intentionally but must not point at a Steam Workshop cache.
- Preserve runtime-only files intentionally excluded by the manager; installed/deployed copies are not source and must not be committed.

## Shipping Lock
`Shipping\shipping.lock.json` is the explicit list of what this mod installs. Committing a file no longer puts it in players' installs: deploy ships the intersection of this tree and the lock, and reports anything on either side of the difference.

- It records **membership only** — source path and the runtime path it lands on — never content hashes. Editing a shipped texture or mission script needs no ceremony; adding or removing a *file* does, and appears as a reviewable diff.
- `Manage-CampaignFiles.ps1 -bless` regenerates it and prints what that adds to or drops from the install. Review that diff before committing; it is the moment a file becomes something players receive.
- `-bless` refuses to run when two source files flatten onto the same runtime path. Deploy flattens most of the tree to a bare filename, so a basename collision means whichever file is copied last silently wins.
- `Manage-CampaignFiles.ps1 -verify` compares the install against the lock read-only and reports missing, content-different and unexpected files. It writes nothing, so it is the safe way to answer "is my install clean?" before or after a test run.
- `.github`, `Tools`, `Shipping`, `docs`, `Local` and `References` are authoring-only trees and never deploy.

**This tree is canon. Never deploy from a GitHub clone.** `%USERPROFILE%\Documents\GIT\Battlezone98Redux_CampaignReimagined` is a blobless partial clone that lags this tree; deploying from it resurrects files pruned here and overwrites current content with older copies. Run `-verify` if you suspect an install was built from the wrong tree.

Direction of truth: **canon -> install** for everything the mod ships. The install is a build output, not a source. When a file is validated in the install and needs keeping, copy that specific file back deliberately and commit it — never sync the tree back wholesale, because the flatten step cannot tell which source folder a runtime file came from. Files the game itself authors (settings, saves, progress) are runtime-only; leave them alone.

## BZR Bundle
Local sibling/reference checkouts normally live under `%USERPROFILE%\Documents\GIT`; verify `origin` before editing because local folder names may be historical. The CR Git checkout there is useful for cross-reference, but the canonical edit/promotion paths above remain authoritative.

- **Campaign Reimagined / CR** — `GrizzlyOne95/Battlezone98Redux_CampaignReimagined` (this repo): addon content, Lua consumers, assets, packaging, integration/validation.
- **OpenShim** — `GrizzlyOne95/Battlezone98Redux_Shim`: low-level hooks, patches, RE, SDK/native engine integration.
- **EXU / ExtraUtilities** — `GrizzlyOne95/ExtraUtilities`: reusable native/Lua-facing runtime features. **EXU always means this repository.**
- **bzfile** — `GrizzlyOne95/bzfile`: Lua-accessible file I/O and update/deployment support.

Cross-repo reading is encouraged. Do not edit another repo merely because it was consulted; read that repo's `AGENTS.md` before coordinated changes.

## Shared BZR Lua Reference
Before writing, reviewing, or changing BZR Lua behavior—or adding Lua-facing native APIs—read `Docs/BZR_LUA_AGENT_REFERENCE.md`. This document is mirrored across the four core BZR repos and should remain byte-identical. Repo-specific `AGENTS.md`/architecture docs still govern implementation ownership. When the shared reference changes, mirror the same content to OpenShim, EXU, Campaign Reimagined, and bzfile in the same workstream.

Reference/tooling repos under `%USERPROFILE%\Documents\GIT` (reference, not default edit targets): `BZ98RBlenderToolKit`, `Battlezone98Redux_DedicatedServer`, `BZ1-GameWatcher`, `BZ1_Source`, `BZ2_Source`, `Battlezone_LobbyMonitor`, `BZNTools`, `Battlezone98Redux_AudioTool`, `Battlezone98Redux_WorldBuilder`, `Battlezone98Redux_ZFSSpecialist`. Rendering work may also consult local `ogre-1.10.0`.

## Git Workflow
- Before editing, inspect `git status -sb` and the relevant diff; preserve pre-existing user changes.
- Normal work goes on a task branch, usually `agent/<short-description>`, never directly on the default/protected branch.
- Agents may commit and push coherent task-owned checkpoints without repeatedly asking. Prefer validated build/validator/game-test milestones; a clearly labeled `WIP:` checkpoint may preserve valuable intermediate work but must stay out of the default branch and Workshop publication.
- Stage only task-owned files. Never blanket-stage, clean, restore, or otherwise absorb/destroy unrelated changes in a mixed worktree.
- Do not rewrite shared history or force-push unless explicitly requested.
- PR merges, releases/tags, Steam Workshop upload/publication, and other external publishing require explicit user instruction. GOG deployment is allowed when it is part of requested local validation.
- Do not commit secrets, machine credentials, transient output, runtime copies, generated Workshop staging payloads, crash dumps, or scratch artifacts the repo does not intentionally track.

## Ownership Routing
- Engine/native hooks, loader/save patches, low-level RE -> **OpenShim**.
- Reusable higher-level Lua/native runtime APIs -> **EXU**.
- File I/O and constrained update/deployment primitives -> **bzfile**.
- Campaign-specific Lua/content/assets/integration -> **this repo**.
- Consult sibling implementations before duplicating functionality, but keep changes in the repo that owns the behavior.

## GPT-6 Astra Optimization (Prompting Best Practices)

This project is optimized for **GPT-6 Astra** (`gpt-6-astra` via Responses API). Astra is more capable but more sensitive to instruction priority and more likely to pause for clarification than GPT-5.6. The following prompts tune Astra for this repo without weakening safety gates on irreversible actions. See `https://developers.openai.com/api/docs/guides/latest-model.md#prompting-best-practices`.

### Initiative and Follow-Through — Bias Towards Action

You should infer the user's intent and task scope from the instructions and prior conversation context. Your job is to bias towards action and carry the user's intended task to completion.

When the user expresses intent to perform new work or fix an existing issue, persist until the user's intended goal is complete. Progress autonomously towards the user's goal (e.g. creating isolated worktrees / checkouts if needed, resolving merge conflicts, read-only actions, creating draft PRs etc.) unless they are clearly destructive or irreversible.

When the user's prompt indicates a request for action, such as "can you...", "I want to...", "help me..." and similar expressions, treat these as instructions to do the work and take action. Do not stop at acknowledging capability (e.g. "Yes…"), proposing a plan, or offering to continue. Do not settle for a partial or "helpful enough" solution that does not fully satisfy the user's task to save time, effort or tokens. If a task requires sustained work, complete all the necessary work until the intended outcome is fulfilled.

Before asking the user clarifying questions, you should complete the work that is already authorized from context and necessary to make the proposed action concrete and reviewable. The user should be approving a concrete, reviewable result. For example, before deploying a change, writing to an external application, merging a PR or publishing a site, do all the required work first so that user approval is the final step. You don't need user permission for reversible tasks, read-only actions, reviews or fixes, or anything for which authorization is provided earlier in the session or strongly implied from the task instruction.

Do not introduce unsolicited warnings, disclaimers, approval flows, or safety/compliance checklists due to hypothetical risk.

**Repo-specific application:**
- **Reversible without approval:** local reads, `git status -sb` / diff inspection, editing canonical source files on `agent/*` branches, local validation (`Manage-CampaignFiles.ps1` staging checks without `-deploy`), shader checks, creating isolated worktrees.
- **Irreversible — requires explicit user instruction (preserve existing gates):** `Manage-CampaignFiles.ps1 -deploy` to GOG when not part of requested validation, `git push` to protected `main`, PR merges, releases/tags, `workshop.config.json` publishing / Steam Workshop upload (`3686673790`), synchronizing the live Steam Roadmap discussion (`https://steamcommunity.com/workshop/filedetails/discussion/3686673790/216888303627073611/`), force-push / history rewrite. Prepare the concrete payload first; approval is the final step.

### Instruction Following — Precedence and Transparency

The user's instructions take precedence over guidelines provided in a skill or in this `AGENTS.md`. If explicit user instructions conflict with a skill's instructions or with guidance in `AGENTS.md`, prioritize the user's instructions.

If a skill or this file causes you to ask for permission or confirmation, pause, leave requested work unfinished, or diverge from the user's intent, name and link to the exact file you read (e.g. `AGENTS.md:32` or `SKILL.md:15`), quote the relevant instruction, and briefly explain how it applies. Distinguish explicit requirements from your interpretation of guidelines.

Audit note: Astra is more sensitive to instructions in skills and `AGENTS.md`. When the workspace loads many instruction files, actively check for silent or conflicting guidance that could block work early.

### Personality and Writing Style

Default to using clear, concise paragraphs, each developing one main idea. Use lists only when the information is genuinely parallel, sequential, or easier to compare, and avoid nested lists unless the hierarchy cannot be expressed clearly in prose. Use plain, simple language: familiar words, concrete examples, and precise verbs. Prefer active voice and direct statements.

Make sure to state the main point clearly and early, then develop it with the explanation and detail the reader needs. Let each sentence build on what came before.

Use plain language over jargon, and reference technical details only to the degree that it helps illustrate an idea or your work to the user. Communicate complex concepts in a clear and cohesive manner, and calibrate your writing to the level of background knowledge assumed from the user's prompt and context.

Avoid using slop words or phrases like "Bottom Line:" in conclusions, "delve," "foster," "leverage," "it's worth noting," "importantly," "Question? Answer." or "This isn't about X. It's about Y.", "genuinely" or hyphenated compound descriptions and adjectives. Do not use concluding summary statements such as "In short:..", "The simplest mental model is:...". State the intended action directly. Avoid adding what you won't do, what will remain unchanged, or how you'll separate or categorize results. Do not use contrastive framing such as "X, not Y" or "X—not Y" that introduces an unprompted alternative that the user didn't ask about.

### Subagent Delegation — Parallelize Where Possible

If at any point you can parallelize work by delegating tasks to another agent (no matter if you are the root or subagent), you should do so using collaboration tools if it could save time or improve quality.

Messages that you send to other agents and your final answer may be read by a human, so ensure they are legible. Always put proper spaces between words and/or numbers.

Repo hint: parallelize across `Scripts/` / `Missions/` / `Assets/` / `Shaders/` / `ODF/` scans, cross-repo reads (`%USERPROFILE%/Documents/GIT` siblings), and independent validation steps (shader smoke tests, manifest checks, staging diffs).

### Testing and Verification — Calibrated Thoroughness

Do not write tests for reversible, low-impact changes that mirror the implementation. If you do choose to verify your work with tests, make sure that the tests are meaningful and necessary to verify implementation.

Run tests appropriate to the change and complete required checks. Once those pass, broaden or repeat testing only when new changes, failures, or unresolved concerns justify it; otherwise, continue toward completing the task.

Repo mapping: for small Lua/ODF/text edits use targeted checks (`Manage-CampaignFiles.ps1` staging validation, `Tools/Validate-DX11Shaders.ps1` when shaders touched). Reserve full promotion (`-deploy` → GOG runtime test → Workshop staging) for changes that alter mission flow, save/load, AI/economy, overlays, or native payload. See `docs/STEAM_PUBLISH_CHECKLIST.md:25` for full publish gates.

### Model and API Notes (for external callers)

To build with Astra, set `model: gpt-6-astra` in a Responses API request (`https://developers.openai.com/api/docs/guides/migrate-to-responses`). Remove `temperature`, `top_p`, `top_logprobs` / `logprobs`, replace `prompt_cache_retention` with `prompt_cache_options.ttl: "30m"`, and preserve `reasoning.effort` (if you used `none`/`minimal` start with `low`). Astra does not support `none` reasoning or `service_tier: "fast"/"priority"` with EU data residency. Use `configuration_update` items to change reasoning mid-conversation without breaking prompt cache.
