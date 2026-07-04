# Sim Nav Map Smoke Matrix

This file defines the stable regression gates for `sim-nav-map` issue work.
It should stay small enough to answer "what must stay green now?"

## Test Categories

Three buckets, kept apart on purpose:

| Bucket | What it asserts | Where it lives | Gate |
|---|---|---|---|
| **Smoke** | Product contract — thresholds reflect what the system *should* do and should not drift with implementation tweaks. | `tests/smoke/` | In `test_groups.json`, must stay green to merge |
| **Repro** | A specific user report or logged scenario. Thresholds may track implementation changes (note in code why). | `tests/repro/` (or alongside smoke if already PASS-locked) | In `test_groups.json` once the underlying issue is fixed |
| **Stress** | Beat the system into corners. **Only** hard safety invariants assert (NaN / inf / out-of-map / illegal teleport). No business outcome assertions. | `tests/stress/` (fuzz mode lives in the same scene) | Out of `test_groups.json` — observation only, but exits non-zero on invariant violation |

Why the three are separate: **smoke** locks in correctness, **repro** locks in known fixes (and is allowed to evolve), **stress** discovers what neither smoke nor repro thought to ask. Promoting a stress phase into smoke means writing the binary contract the phase should have asserted from day one.

## Stable Gates

Run both groups before merging any issue fix:

```powershell
./tools/run_tests.ps1 simnav/smoke dota2lab/smoke
```

| Group | Manifest | Responsibility |
|---|---|---|
| `simnav/smoke` | `addons/sim-nav-map/tests/test_groups.json` | Core addon contracts: public API defaults, map state, passability, terrain, obstruction, dirty lifecycle, reachability, long/short pathfinding, line validation, cache, request queue, and diagnostics exports. |
| `dota2lab/smoke` | `addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/tests/test_groups.json` | Plugin-local playable adapter sample: Dota2/LoL-style contact-resolved movement — move basics, separation-solve invariants, crowd blockers, stall watchdog, target fanout, flying layer, AI command source, and UI ops. |

Baseline gate:

```powershell
./tools/run_tests.ps1 simnav/smoke dota2lab/smoke
git -C addons diff --check
```

## Repro Tests

Issue repro scenes are intentionally separate from the stable smoke manifests.
They may fail at HEAD and should not be discovered by `./tools/run_tests.ps1`
until the matching issue is fixed.

| Kind | Location | Rule |
|---|---|---|
| Core repro | `addons/sim-nav-map/tests/repro/` | Add a focused scene for one core issue. Register it into `simnav/smoke` only after the fix turns it green. |

`dota2-rts-pathfinding-lab` has no separate `tests/repro/` tier — its `smoke/` scenes assert
regression invariants directly (e.g. residual-overlap == 0 after separation solve). Add a new
smoke scene there instead of a repro scene when locking in a dota2-lab-specific fix.

## Stress

Neither `simnav` core nor `dota2-rts-pathfinding-lab` currently has a stress/fuzz harness. If one
is added later, follow the same rule the old 0ad lab used: hard safety invariants only (NaN / inf
/ out-of-map / illegal teleport), no business-outcome assertions, and keep it out of
`test_groups.json` (observation only, non-zero exit on invariant violation).

## Current Coverage

`simnav/smoke` covers:

- public API constructor/default contracts
- passability class registration
- terrain tile data and terrain-derived navcell passability
- class-aware clearance rasterization for terrain and static obstructions
- dirty navcell lifecycle
- spatial index queries
- path goal geometry
- map tracing
- obstruction manager behavior
- hierarchical reachability and dirty recompute
- reachability/canonical goal result metadata
- long-path query/result status, canonicalization metadata, raw/refined path boundary, max spacing, excluded-region isolation, and path cost/length
- jump-point cache invalidation
- vertex pathfinder
- filtered obstruction queries and line validation
- path request queue, queued request cloning, and queue diagnostics
- map dirtiness diagnostics and connectivity exports

`dota2lab/smoke` covers:

- move-order basics (issue → arrive / arrived_partial / arrived_crowded / bounded stalled-fail)
- unit-unit separation-solve invariants (no persistent overlap across ticks)
- separation under the spatial-hash broad phase at higher unit counts
- perf budget guardrails (plan/flush/line-check/tick timing thresholds)
- crowd blockers (dense packing near a target, sealed corridors)
- stall watchdog (bounded termination when no progress is possible)
- target fanout (many units, distinct destinations)
- flying-layer movement
- AI command source (scripted Layer 2 command stream driving lane moves/chase/retreat/cancel)
- frontend UI tool ops

> Note: this matrix predates the GDExtension native port (1d ⑤, 2026-07-03) and does not yet
> cover the `simnav/native` / `dota2lab/native` required groups — pre-existing gap, out of scope
> for this pass.

## Discovery Contract

`tools/run_tests.ps1` discovers sim-nav-map manifests from:

```text
addons/sim-nav-map/tests/test_groups.json
addons/sim-nav-map/examples/*/tests/test_groups.json
```

Paths inside each manifest are relative to that manifest directory. New core
addon smoke scenes belong under `addons/sim-nav-map/tests/` and should be added
to `simnav/smoke` after they are expected to pass. New lab behavior smoke scenes
belong under `examples/dota2-rts-pathfinding-lab/tests/smoke/` and should be added
to `dota2lab/smoke` after they are expected to pass.

## Issue Fix Checklist

- `README.md`, `docs/mental-model.md`, `docs/public-api.md`,
  and this file still agree on the same boundary.
- `simnav/smoke` and `dota2lab/smoke` are discoverable by `./tools/run_tests.ps1 -List`.
- Fixed issue repros are promoted into the correct smoke manifest.
- Red repros stay in `tests/repro/` (core only — `dota2-rts-pathfinding-lab` has no lab-level repro tier), not in the stable manifest.
- Stress/fuzz lives in `tests/stress/`, never in the smoke manifest, and only ever asserts hard safety invariants.
- Old RTS private pathfinder wording points to archived compatibility, not a future implementation path.
- `addons/sim-nav-map/docs/references/0ad-source/` remains ignored/untracked.
