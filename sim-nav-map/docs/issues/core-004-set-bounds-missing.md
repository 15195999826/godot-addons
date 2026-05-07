# CORE-004: `SetBounds()` missing — out-of-bounds undefined

- Status: resolved
- Severity: P1
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07
- Resolved: 2026-05-07

## Resolution

- submodule commit: `2155450`
- smoke: `addons/sim-nav-map/tests/repro/repro_core_004_set_bounds.tscn` (registered under `simnav/smoke` group)
- 0 A.D. files checked: `source/simulation2/components/ICmpObstructionManager.h::SetBounds` (rectangular bounds API; circular variant intentionally still deferred)
- Fix:
  1. Added `SimNavMap.set_bounds(x0, z0, x1, z1)` plus read-side helpers `is_inside_playable_bounds(world_pos)`, `get_playable_bounds_min()`, `get_playable_bounds_max()`. Default bounds = full backing-grid extent so existing callers see no behavior change.
  2. `_blocked_mask_for_point` skips cells whose world center is outside the playable bounds — a static OBB straddling the rectangle therefore rasterizes only its in-bounds portion. Re-rasterizes all statics on `set_bounds` (via `_mark_all_static_obstructions_dirty`).
  3. `SimNavLongPathfinder.compute_path_result` now also checks `is_inside_playable_bounds(query.start_world)` and (for `POINT` goals) `is_inside_playable_bounds(query.goal.center)` after the existing grid-extent check; out-of-bounds returns `STATUS_INVALID_QUERY` with `FAILURE_START_OUT_OF_BOUNDS` / `FAILURE_GOAL_OUT_OF_BOUNDS`.
- public-api.md updated: new method on `SimNavMap`, behavior contract for the rectangular bounds.
- baseline impact: `BASELINE.md` "Known correctness limits" — removed CORE-004 row. No metric in the lab table moves; default bounds preserve current behavior.

## Symptoms

`SimNavMap` has no public `set_bounds()` analogue to 0 A.D.'s
`ICmpObstructionManager::SetBounds(x0, z0, x1, z1)`. Grid out-of-range
start / goal checks already exist, but callers cannot express a playable
rectangle that is smaller than, or independent from, the underlying navcell
grid. Obstruction rasterization and path queries therefore have no shared
"outside playable bounds" contract.

## Root cause

`addons/sim-nav-map/model/sim_nav_map.gd:400-401` (`is_valid_navcell`) does
a bounds clip but no obstruction-side bounds layer exists. There is no
"map edge counts as wall" flag in the obstruction manager.

## 0 A.D. reference

- `docs/references/0ad-source/source/simulation2/components/ICmpObstructionManager.h:113`
  (`SetBounds`).
- `docs/references/0ad-source/source/simulation2/components/CCmpObstructionManager.cpp`
  enforces bounds in `Rasterize()` and in shape range queries.

`SetPassabilityCircular()` for circular maps is documented as
intentionally deferred ([source map](../references/0ad-source-map.md))
— this issue is rectangular bounds only.

## Proposed fix

1. Add `set_bounds(x0: float, z0: float, x1: float, z1: float)` to
   `SimNavMap`, storing the rectangle.
2. At `add_static_obstruction` / `update_unit_obstruction`, fail fast (or
   clip) when the shape is fully outside bounds. Decide whether partial
   overlap is supported (probably yes, with rasterization clipping to the
   bounds rectangle).
3. At long/short/hierarchical path query entry, validate start and goal
   against bounds. Surface `STATUS_INVALID_QUERY` with a clear failure
   reason in the result DTOs.
4. Default bounds: full navcell grid extent if `set_bounds()` is never
   called (preserves current behavior for callers that do not opt in).
5. Update `public-api.md` with the new method and behavior guarantees.

## Verify before fixing

- [ ] Confirm circular bounds are still in the deferred bucket; this issue does not own them
- [ ] Decide on partial-overlap rasterization policy before writing the code (probably clip-to-bounds; document the choice)
- [ ] Audit existing smoke for any test that depends on out-of-bounds being silently passable

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_004_set_bounds.tscn
```

Smoke: [`tests/repro/repro_core_004_set_bounds.gd`](../../tests/repro/repro_core_004_set_bounds.gd).

At HEAD (commit 6335f32) the smoke FAILs:

```text
SMOKE_TEST_RESULT: FAIL - CORE-004 reproduces:
  SimNavMap missing set_bounds(x0, z0, x1, z1); cannot express playable bounds tighter than the navcell grid
```

After `set_bounds()` exists, the same smoke verifies the intended contract:

1. configure bounds tighter than the underlying navcell grid,
2. assert a goal outside those playable bounds returns
   `STATUS_INVALID_QUERY` / `FAILURE_GOAL_OUT_OF_BOUNDS`,
3. assert a static OBB straddling the bounds rectangle rasterizes only the
   in-bounds portion.

## Regression after fix

The smoke flips to `PASS` after the rectangular bounds API and enforcement
land. Add it to `tests/test_groups.json` under `simnav/smoke` once green,
and update `public-api.md` in the same change.

## Cross-refs

- Source map: `../references/0ad-source-map.md` (`SetBounds()` listed under deferred items but rectangular case promoted here)
- [CORE-005](core-005-clearance-extension-radius.md) — bounds and clearance extension share rasterization touchpoints
- [LAB-003](lab-003-active-jump-55px.md) — well-defined edge behavior reduces the risk of edge-induced large jumps
