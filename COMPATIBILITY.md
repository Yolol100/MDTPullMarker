# Compatibility - 1.0.0-rc54

## Route identity and dungeon selection

- MDT is the authoritative source for pull membership and configured raid-target assignments.
- rc54 stores one explicitly chosen route binding per dungeon (`schema 12`). Existing rc45/schema-10 single bindings still migrate automatically into the matching dungeon entry; schema 12 only retires two historical settings that no longer control any runtime path.
- UID-backed routes resolve by UID. UID-less copied routes use bounded preset identity/name fallback so normal content edits do not silently rebind to another visible MDT preset.
- During an active Mythic+ run, the live challenge-map identity is authoritative. A saved binding from another dungeon is not substituted when the active dungeon has no binding.
- Binding or unbinding during an active key is constrained to the matching dungeon and fails closed on a verified mismatch.
- A route bound before a future season exposes its Challenge Map ID may be recovered after season activation only by one unique normalized match against MDT's current client-localized dungeon name for the saved MDT dungeon index. This also survives a client-locale change between binding and season start. The persisted bind-time name is fallback-only. This recovery applies only to bindings with no stored map ID; a binding with a different map ID is never reassigned.

## Precomputed secure macro model

- The complete bound route is planned outside combat into `MPM###A/B/C` macros.
- Each macro contains at most three marker operations; a pull supports up to eight raid icons across at most three batches.
- Generated bodies are validated against the 255-byte macro limit using actual string bytes.
- Macro bodies are never rewritten while `InCombatLockdown()` is active.
- Later-pull macros already exist before combat, so a chain-pull can select a later pull without a protected rewrite.
- Active bodies start with `/stopmacro [nocombat]` and apply set-if-unmarked `/tm [harm,nodead] ~N` operations.

## Execution gating

A route macro is executable only when the matching dungeon session is active, the challenge is not completed, the bound route matches, and this client is the elected marker owner. Otherwise managed macros are written to the safe idle body.

## Stable macro slots

- `MPM###A/B/C` names are reused across dungeons rather than multiplied per dungeon.
- When the active route needs fewer macro names than a previous route, extra proven addon-managed macros are **parked**, not deleted.
- Parked extras do not count as stale executable macros and can be reactivated at the same macro index on a later route refresh.
- If another dungeon binding remains after `/mpm unbind`, managed route macros are parked. Removing the last binding may retire them to free slots.
- Personal same-name macros are never modified because name alone never proves ownership.
- Partial create/edit/readback failures park all independently proven managed route macros first. Deletion is an emergency fail-closed fallback only when parking cannot make the set inert.

## Same-name limit

A secure exact-name macro cannot identify an MDT clone when physical units share the same visible name. rc54 resolves client-local names where possible and checks duplicate marked target names route-wide. This includes non-adjacent pulls because intermediate pulls may be skipped. Ambiguous automatic pulls become `manual-required`; no unfiltered target cycling is used.

## Overlap-aware progression

- Route macro tokens bind route fingerprint + pull + batch.
- Multiple marked pulls may be engaged and pending simultaneously.
- Forward jumps explicitly track untouched intermediate marked pulls as skipped.
- Returning to a skipped pull engages it and clears the skip state.
- `PullDeathTracker` maintains independent contexts for active overlapping pulls.
- A readable death that can belong to more than one active pull is rejected as ambiguous and blocks automatic completion for the affected context.
- Secret/restricted/unavailable combat identity remains advisory and never drives a protected combat action.
- A wipe clears pending submission/death progress rather than advancing the route.

## Marker submission semantics

The macro callback occurs after protected `/tm` lines. The addon can verify the route token and record a valid macro **submission attempt**, but Retail does not provide a reliable universal per-unit proof that every protected marker line succeeded. Progression therefore never labels those protected operations as individually confirmed.

The addon uses a conservative ~4 second local pacing window between A/B/C submissions. Blizzard documents the three-unit burst restriction but not an exact four-second reset.

## Target behavior

Exact-name route macros clear and retarget before each marker operation so a failed `/targetexact` cannot accidentally mark the previous unit. This necessarily changes the player's target. rc54 does not add automatic target-history restoration because it would increase the protected macro byte budget substantially and is not proven safe across all target-failure sequences in the Retail client.

## Party ownership

Grouped clients derive one deterministic roster anchor with the existing priority order: tank, group leader, DPS, healer, then stable name order. Only that roster member may become the marker owner when its local eligibility and addon communication are proven. Heartbeats still renew peer diagnostics every five seconds and silent peer records expire after 18 seconds, but peer silence is never treated as proof that a higher-priority addon client is absent. The effective owner is frozen for the current combat. Passive clients keep their route macros parked.

Grouped execution requires positively registered addon communication plus a complete readable group roster, including role and leader ranking data. Current Retail communication result codes are validated explicitly; throttle/lockdown/invalid/secret results are failures. Unknown group/raid state, incomplete unit identities, unreadable role/leader/death state, prefix-registration failure or a failed send leaves the client passive instead of falling back to local ownership. Solo play does not require the election channel.

This is intentionally availability-conservative: if the deterministic roster anchor does not run the addon, is locally ineligible, or cannot prove communication while remaining in the roster, no lower roster member is promoted from silence alone. A roster change can make another member the new deterministic anchor. This is required to prevent two isolated clients from each self-electing after delayed/lost addon messages.

The combat owner is a true frozen state, including a frozen `nil` owner. If combat begins before the settle window has proven one group owner, that combat stays passive; delayed peer/roster information is used only for the next election. While combat is frozen, peer heartbeats, settle completion and group-loss transitions do not refresh `MarkerExecutor`, so they cannot cancel an in-flight marker confirmation.

Macro ownership likewise requires a readable runtime account-macro boundary and valid account/character macro counts. Missing, secret or malformed slot metadata blocks create/edit/delete rather than guessing a capacity or slot index.

## Legacy mode

Without a binding for the active dungeon, the rc44-compatible `MDTPM1/MDTPM2` workflow remains available with a maximum of six automatic marker assignments and safe-boundary rewrites.

## Automated validation

The release suite covers package/version integrity, Lua syntax, static policy, macro byte budgets, 2/3-batch planning, 2,000 planner fuzz cases, schema-9/10 -> schema-12 migration, independent dungeon bindings, active-dungeon selection, full-route token/macro generation, route-wide same-name fail-closed behavior, overlap/skip state, multi-context death evidence, A/B/C pacing, wrong-dungeon/passive parking, stable parked macro indices, personal-name conflicts, partial-create failure handling, mutation readback, owner election/freeze, localized names, full TOC load, and MDT 6.1.20/6.2.x compatibility fixtures, current MDT 6.2.1 enemy-metadata hook behavior, and all eight Midnight Season 2 route identities, including pre-season bind -> client-locale change -> season activation recovery.

A real Retail/Midnight client test remains required for final taint/protected-action verification.
