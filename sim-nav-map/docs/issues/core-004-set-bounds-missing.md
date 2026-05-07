# CORE-004: `SetBounds()` missing — out-of-bounds undefined

- Status: open
- Severity: P1
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

## Symptoms

`SimNavMap` has no public `set_bounds()` analogue to 0 A.D.'s
`ICmpObstructionManager::SetBounds(x0, z0, x1, z1)`. Out-of-bounds queries
silently return "no obstruction" because `is_valid_navcell()` clips and
`world_to_navcell()` does not flag out-of-range. Path queries near the
map edge can plan into space that is conceptually outside the play area
without any failure signal.

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
intentionally deferred ([roadmap](../roadmap-refs/0ad-navigation-source-map.md))
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

## Repro at HEAD (no smoke possible — API does not exist)

The repro is by absence. Verify the API is missing:

```powershell
# From repo root
Select-String -Path 'addons/sim-nav-map/**/*.gd' -Pattern 'set_bounds' -SimpleMatch
```

At HEAD (commit 6335f32) this returns zero hits. There is no `set_bounds`
or analogous method on `SimNavMap` or `SimNavObstructionManager`.

Out-of-bounds queries are silently clipped without flagging:

- `SimNavMap.is_valid_navcell(coord)` returns false for out-of-range
  coords (sim_nav_map.gd:400-401), but no caller-facing `STATUS_*` /
  failure reason exists.
- `add_static_obstruction(shape)` accepts a shape with a center far
  outside the navcell grid; rasterization is a no-op (no cells overlap),
  and queries against that shape return "no obstruction nearby" without
  signalling that the shape was outside the playable area.

**Smoke deliverable** (when API is added): a
`addons/sim-nav-map/tests/repro_core_004_set_bounds.gd` that
1. asserts `SimNavMap` exposes `set_bounds(x0, z0, x1, z1)`,
2. with bounds set tighter than the underlying navcell grid, verifies
   in-bounds query succeeds and out-of-bounds query returns
   `STATUS_INVALID_QUERY` with `FAILURE_GOAL_OUT_OF_BOUNDS` /
   `FAILURE_START_OUT_OF_BOUNDS` as appropriate,
3. verifies a static OBB straddling the bounds rectangle rasterizes
   only the in-bounds portion.

## Cross-refs

- Roadmap: `../roadmap-refs/0ad-navigation-source-map.md` (`SetBounds()` listed under deferred items but rectangular case promoted here)
- [CORE-005](core-005-clearance-extension-radius.md) — bounds and clearance extension share rasterization touchpoints
- [LAB-003](lab-003-active-jump-55px.md) — well-defined edge behavior reduces the risk of edge-induced large jumps
