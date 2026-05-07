# CORE-006: Per-tag flag mutation API incomplete

- Status: open
- Severity: P2
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

## Symptoms

`SimNavObstructionManager` exposes `set_unit_moving_flag()` and
`set_control_group()`, but there is no API for mutating the rest of the
flag bitfield (`BLOCK_MOVEMENT`, `BLOCK_FOUNDATION`,
`BLOCK_CONSTRUCTION`, `BLOCK_PATHFINDING`, `DELETE_UPON_CONSTRUCTION`).
Callers that need to flip these flags reach into the shape directly,
which bypasses the dirty-tracking signaling and can leave the rasterized
navcell grid out of sync.

## Root cause

- `addons/sim-nav-map/obstruction/sim_nav_obstruction_manager.gd:69-88`
  exposes only the two specific setters.
- `addons/sim-nav-map/obstruction/sim_nav_obstruction_shape.gd:14`
  declares `flags` as a public mutable field.

There is no `set_static_flags(tag, flags)` / `set_unit_flags(tag, flags)`
API that updates the flag and marks the affected navcells dirty.

## 0 A.D. reference

`docs/references/0ad-source/source/simulation2/components/ICmpObstructionManager.h`:

- `SetUnitControlGroup` / `SetUnitMovingFlag` (analogous to current GD setters)
- `SetStaticControlGroup`, `SetStaticDisableBlockMovementPathfinding`, etc.

Each mutation is a dedicated API call; flags are not directly mutated.

## Proposed fix

1. Add `set_static_flags(tag: int, flags: int)` and
   `set_unit_flags(tag: int, flags: int)` on
   `SimNavObstructionManager`. Both mark the affected obstruction range
   as dirty and trigger re-rasterization on the next `rebuild_dirty()`.
2. Audit lab and tests for any direct `shape.flags = ...` mutation; route
   them through the new setters.
3. Optional: add a `_assert_no_direct_flag_mutation` debug check (in
   `Log.assert_crash`-style) that the `flags` field is mutated only
   through the manager API. Off by default outside debug builds.

## Verify before fixing

- [ ] Grep `addons/sim-nav-map/` and `addons/sim-nav-map/examples/` for direct `.flags =` writes
- [ ] Decide whether to deprecate `set_unit_moving_flag()` in favor of `set_unit_flags()`, or keep the convenience wrapper
- [ ] Confirm dirty-tracking already supports flag-only changes that don't move/resize the shape

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_006_flag_setter_propagation.tscn
```

Smoke: [`tests/repro/repro_core_006_flag_setter_propagation.gd`](../../tests/repro/repro_core_006_flag_setter_propagation.gd).

**Note on what's actually broken.** `SimNavMap.rebuild_dirty()` does a full
re-rasterization, so even after a direct `shape.flags = X` mutation the
final navcell state is correct. The real bug is that direct mutation
*does not mark navcells dirty*, so incremental consumers
(`SimNavHierarchicalPathfinder.recompute_dirty()`, jump-point cache
invalidation, AI dirty export) cannot detect that anything changed.

Setup: add a 1-cell static OBB with `BLOCK_PATHFINDING`. Run
`rebuild_dirty()` then `clear_dirty_navcells()` /
`clear_dirty_obstruction_navcells()` to reach a clean baseline. Mutate
`shape.flags = 0` directly. Inspect `has_dirty_navcells()` /
`has_dirty_obstruction_navcells()`.

At HEAD (commit 6335f32) the smoke FAILs:

```text
SMOKE_TEST_RESULT: FAIL - CORE-006 reproduces:
  after direct mutation (shape.flags = 0), no navcells were marked dirty —
  incremental consumers (hierarchical / jump cache / AI export) cannot detect the flag change
```

Both `has_dirty_navcells()` and `has_dirty_obstruction_navcells()` return
false even though the rasterization-relevant flag changed. Any consumer
that reads dirty bits before calling `rebuild_dirty()` misses the change.

## Regression after fix

Once `set_static_flags()` / `set_unit_flags()` exists (or the flag setter
on the shape itself marks affected navcells dirty), the smoke detects the
new API via `has_method` and uses it; the dirty assertion becomes true and
the smoke prints `PASS`.

## Cross-refs

- [CORE-004](core-004-set-bounds-missing.md) — both work on the obstruction manager API surface
