# Compatibility - 1.0.0-rc55

## Route identity and dungeon selection

- MDT is the authoritative source for pull membership and configured raid-target assignments.
- rc55 stores one explicitly chosen route binding per dungeon (`schema 12`). Existing rc45/schema-10 single bindings still migrate automatically into the matching dungeon entry; schema 12 only retires two historical settings that no longer control any runtime path.
- UID-backed routes resolve by UID. UID-less copied routes use bounded preset identity/name fallback so normal content edits do not silently rebind to another visible MDT preset.
- During an active Mythic+ run, the live challenge-map identity is authoritative. A saved binding from another dungeon is not substituted when the active dungeon has no binding.
- Binding or unbinding during an active key is constrained to the matching dungeon and fails closed on a verified mismatch.
- A route bound before a future season exposes its Challenge Map ID may be recovered after season activation only by one unique normalized match against MDT's current client-localized dungeon name for the saved MDT dungeon index. This also survives a client-locale change between binding and season start. The persisted bind-time name is fallback-only. This recovery applies only to bindings with no stored map ID; a binding with a different map ID is never reassigned.
- New writes reject assigning the same positive Challenge Map ID to two different dungeon bindings. If legacy/corrupt SavedVariables already contain an ambiguous active-map or name mapping, active Mythic+ route refresh fails closed instead of falling through to the currently selected MDT route.

## Precomputed secure macro model

- The complete bound route is planned outside combat into `MPM###A/B/C` macros.
- Each macro contains at most three marker operations; a pull supports up to eight raid icons across at most three batches.
- Generated bodies are validated against the 255-byte macro limit using actual string bytes.
- Macro bodies are never rewritten while `InCombatLockdown()` is active.
- Later-pull macros already exist before combat, so a chain-pull can select a later pull without a protected rewrite.
- Active bodies start with `/stopmacro [nocombat]` and apply set-if-unmarked `/tm [harm,nodead] ~N` operations.

## Execution gating

A route macro is executable only when the matching dungeon session is active, the challenge is not completed, the bound route matches, and this client is the settled marker owner. Otherwise managed macros are written to the safe idle body.

A new pre-combat group-owner election parks managed execution surfaces immediately. This closes the gap where a previously active macro body could otherwise reach its protected `/tm` lines before the trailing `/mpm b` callback noticed that ownership had become unsettled. Reactivation happens only after the settle window completes and ownership is proven again.

## Stable macro slots

- `MPM###A/B/C` names are reused across dungeons rather than multiplied per dungeon.
- When the active route needs fewer macro names than a previous route, extra proven addon-managed macros are **parked**, not deleted.
- Parked extras do not count as stale executable macros and can be reactivated at the same macro index on a later route refresh.
- If another dungeon binding remains after `/mpm unbind`, managed route macros are parked. Removing the last binding may retire them to free slots.
- Personal same-name macros are never modified because name alone never proves ownership.
- Partial create/edit/readback failures park all independently proven managed route macros first. Deletion is an emergency fail-closed fallback only when parking cannot make the set inert.

## Same-name limit

A secure exact-name macro cannot identify an MDT clone when physical units share the same visible name. rc55 resolves client-local names where possible and always checks duplicate target names across the complete bound route, including non-adjacent pulls because intermediate pulls may be skipped.

When a normalized MDT snapshot contains broader enemy metadata, clone totals for those known enemy types are also used. A duplicate proven outside the route therefore becomes `manual-required`. Legacy/global MDT enemy data is explicitly scoped as `dungeon`. MDT 6.2.x UI-hook/cache metadata is explicitly scoped as `captured-enemy-types` or `cached-enemy-types`: each captured type can carry its full clone list, but that scope is not claimed to prove enumeration of every other enemy type in every sublevel. The adapter reports `dungeon-name-coverage-partial` for that case.

Ambiguous automatic pulls become `manual-required`; no unfiltered target cycling is used.

## Overlap-aware progression

- Route macro tokens bind route fingerprint + pull + batch.
- Multiple marked pulls may be engaged and pending simultaneously.
- Forward jumps explicitly track untouched intermediate marked pulls as skipped.
- Returning to a skipped pull engages it and clears the skip state.
- `PullDeathTracker` maintains independent contexts for active overlapping pulls.
- A readable death that can belong to more than one active pull is rejected as ambiguous and blocks automatic completion for the affected context.
- A tracking pull with ordinary readable combat-log access and zero expected death evidence returns a negative completion verdict instead of being treated as advisory success.
- Readable but incomplete death evidence also blocks completion.
- Combat-log API/read/secret failures are recorded as restricted evidence for active contexts. Restricted identity remains advisory because the client has explicitly prevented a normal proof path; it is kept distinct from an ordinary no-evidence state.
- Missing/unavailable death contexts fail closed rather than implicitly completing a submitted pull.
- A wipe clears pending submission/death progress rather than advancing the route.

On Retail 12.1, the tracker prefers `C_CombatLog.GetCurrentEventInfo` directly and retains `CombatLogGetCurrentEventInfo` only as a compatibility fallback. This prevents disabling Blizzard's deprecated global fallbacks from being misclassified as combat-log restriction while preserving the existing event-level secret checks.

## Marker submission semantics

The macro callback occurs after protected `/tm` lines. The addon can verify the route token and record a valid macro **submission attempt**, but Retail does not provide a reliable universal per-unit proof that every protected marker line succeeded. Progression therefore never labels those protected operations as individually confirmed.

A valid submission alone is not treated as readable death proof. When the combat log is normally readable, at least expected pull-death progress is required before completion can be accepted; zero expected evidence blocks. The restricted/secret fallback remains advisory for environments where Retail withholds the relevant identity.

The addon uses a conservative ~4 second local pacing window between A/B/C submissions. Blizzard documents the three-unit burst restriction but not an exact four-second reset.

## Target behavior

Exact-name route macros clear and retarget before each marker operation so a failed `/targetexact` cannot accidentally mark the previous unit. This necessarily changes the player's target. rc55 does not add automatic target-history restoration because it would increase the protected macro byte budget substantially and is not proven safe across all target-failure sequences in the Retail client.

## Party ownership

Grouped clients derive one deterministic roster anchor with the existing priority order: tank, group leader, DPS, healer, then stable name order. Only that roster member may become the marker owner when its local eligibility and addon communication are proven. Heartbeats still renew peer diagnostics every five seconds and silent peer records expire after 18 seconds, but peer silence is never treated as proof that a higher-priority addon client is absent. The effective owner is frozen for the current combat. Passive clients keep their route macros parked.

Grouped execution requires positively registered addon communication plus a complete readable group roster, including role and leader ranking data. Current Retail communication result codes are validated explicitly; throttle/lockdown/invalid/secret results are failures. Unknown group/raid state, incomplete unit identities, unreadable role/leader/death state, prefix-registration failure or a failed send leaves the client passive instead of falling back to local ownership. Solo play does not require the election channel.

A failed send immediately clears communication availability and ownership. Later safe group/world/heartbeat boundaries first prove whether the prefix is already registered and register it only when needed. Communication is then retried through a new settle window; an old owner is never silently restored. Retail's `DuplicatePrefix` result is accepted only when `IsAddonMessagePrefixRegistered` independently proves the prefix is registered.

This is intentionally availability-conservative: if the deterministic roster anchor does not run the addon, is locally ineligible, or cannot prove communication while remaining in the roster, no lower roster member is promoted from silence alone. A roster change can make another member the new deterministic anchor. This is required to prevent two isolated clients from each self-electing after delayed/lost addon messages.

The combat owner is a true frozen state, including a frozen `nil` owner. If combat begins before the settle window has proven one group owner, that combat stays passive; delayed peer/roster information is used only for the next election. While combat is frozen, peer heartbeats, settle completion and group-loss transitions do not change the effective owner for the current combat.

Macro ownership likewise requires a readable runtime account-macro boundary and valid account/character macro counts. Missing, secret or malformed slot metadata blocks create/edit/delete rather than guessing a capacity or slot index.

## Runtime commands

Bound-route cursor navigation can still move between already-prebuilt pulls/instructions during combat. Manual commands that change completion history (`complete` and `reopen`) are rejected during combat and must run at a safe boundary.

## Legacy mode

Without a binding for the active dungeon, the rc44-compatible `MDTPM1/MDTPM2` workflow remains available with a maximum of six automatic marker assignments and safe-boundary rewrites. An ambiguous/corrupt saved binding for an active Mythic+ map is not treated as equivalent to “no binding”; that state blocks route refresh instead of silently entering the visible-route fallback.

## Validation status

The source history describes a release suite covering package/version integrity, Lua syntax, static policy, macro byte budgets, 2/3-batch planning, planner fuzzing, migrations, independent dungeon bindings, active-dungeon selection, route tokens/macros, same-name behavior, overlap/skip state, multi-context death evidence, pacing, parking, macro conflicts, owner election/freeze, localized names, full TOC load and MDT compatibility fixtures.

The published runtime repository does not contain that engineering test suite or `LIVE_TEST_CHECKLIST.md`, so changes on this branch have been reviewed statically against the complete runtime source and current MDT 6.2.1 integration contract, but the historical automated suite has not been independently rerun here. A real Retail/Midnight client test remains required for final taint/protected-action verification.