# Contributing

MDT Pull Marker treats protected macro execution, route identity and multiplayer ownership as safety-critical code. Prefer small changes with explicit invariants over broad rewrites.

## Local checks

Run:

```bash
bash scripts/check.sh
```

The canonical gate requires Lua 5.1. Set `MPM_LUA=/path/to/lua5.1` when it is not on `PATH`. In a constrained environment you may use `MPM_ALLOW_COMPATIBLE_LUA=1` for diagnostics only; the script labels that result non-certifying and it does not replace the Lua 5.1 CI gate.

The check includes deterministic package regression and `scripts/package.py --verify`; no separate package command is required for the normal gate.

`.stylua.toml` defines the intended formatting contract and `.luarc.json` plus `types/MDTPullMarker.d.lua` define the LuaLS model. Formatting is intentionally not CI-blocking until a formatting-only baseline is normalized and reviewed separately from behavioral changes.

## Change rules

- Do not mutate macros in combat lockdown.
- Do not treat a macro callback as proof that preceding protected `/tm` commands succeeded.
- Do not infer physical clone identity from a visible name when ambiguity is known.
- Do not silently truncate persisted identifiers.
- Do not let a missing/secret/opaque API result become a successful fallback.
- Do not let loss of previously valid route/session data silently clear a watcher baseline while executable state remains active.
- Do not add a new MDT compatibility assumption without documenting the tested source/version.
- Add a regression for every correctness fix.

## Pull requests

Keep formatting-only changes separate from behavioral changes. Describe the invariant being protected, the failure path, the tests used, and any remaining Retail-client-only validation.
