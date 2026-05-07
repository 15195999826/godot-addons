# CORE-003: Hierarchical fallback uses fixed 256-cell radius

- Status: open
- Severity: P0
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

## Symptoms

When a goal is unreachable from start, or when start is impassable,
`SimNavHierarchicalPathfinder` falls back to a concentric ring scan with
radius capped at `_MAX_NEAREST_RADIUS = 256` navcells. On maps larger than
~512×512, or when the geographically nearest reachable region is more than
256 navcells away (e.g. behind a long wall, in an L-shaped reachable
component), canonicalization fails and the long pathfinder reports
unreachable even though a valid path exists via the region graph.

## Root cause

- `addons/sim-nav-map/pathfinding/sim_nav_hierarchical_pathfinder.gd:139-149`
  (POINT goal in unreachable region path) falls through to
  `_find_nearest_in_global_region()`.
- Same file `:169-178` `find_nearest_passable_navcell()` does ring scan.
- Same file `:424-443` `_find_nearest_in_global_region()` ring scan body.

All three use `_MAX_NEAREST_RADIUS = 256` and stop early without
consulting the region graph itself.

## 0 A.D. reference

`docs/references/0ad-source/source/simulation2/helpers/HierarchicalPathfinder.cpp`:

- `MakeGoalReachable()` (`:689-720`, especially `:713-719`) collects every
  region reachable from start via global-region ID, computes the nearest
  navcell per region to the goal anchor, then takes the global minimum.
- `FindNearestPassableNavcell()` (`:741-786`) iterates *all* regions for
  the passability class with a region-center distance prune, not a fixed
  navcell radius.

The region graph is already O(1) reachable per global-region ID, so the
per-region scan is bounded by the number of reachable regions, not by
geographic distance.

## Proposed fix

Replace ring scans with region-graph traversal in three places:

1. `_find_nearest_in_global_region()`: enumerate regions of `pass_mask`
   whose `globalRegionID == start_global_id`, for each region scan its
   navcells, compute distance to goal anchor, return overall minimum.
2. `find_nearest_passable_navcell()`: enumerate all regions of `pass_mask`
   (any global ID), same scan, return overall minimum to the input cell.
3. POINT-goal-in-unreachable-region branch: route through (1) instead of
   the ring scan.

Keep the fast path: if the ring scan succeeds within a small radius (say
8 cells), still take it — that is the common case and avoids the
full-region walk for nearby fallbacks. But never *fail* on the small
radius; always fall through to the full walk.

The chunk / region storage already exists; this is mostly traversal
plumbing, not new data structures.

## Verify before fixing

- [ ] Confirm region storage layout in `sim_nav_hierarchical_pathfinder.gd` lets us iterate per-region navcells without re-flooding
- [ ] Decide whether the fast small-radius scan is worth keeping or just inline the full walk
- [ ] Cross-check `SimNavReachabilityResult` carries enough metadata for the new path; if not, surface a "fell back via region walk" status (extension of existing `canonicalized` status)

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/tests/repro_core_003_hierarchical_far_goal.tscn
```

Smoke: [`tests/repro_core_003_hierarchical_far_goal.gd`](../../tests/repro_core_003_hierarchical_far_goal.gd).

Setup: 320×16 navcell grid. Vertical wall at column 30, full height (no
gap). Start at navcell (5, 8); goal at navcell (319, 8). The goal is
fully unreachable; the nearest passable cell on the start side is
(29, 8), which is 290 cells from the goal anchor (> 256).

At HEAD (commit 6335f32) the smoke FAILs:

```text
SMOKE_TEST_RESULT: FAIL - CORE-003 reproduces:
  goal at navcell (319, 8) should canonicalize to start's reachable region (failure_reason=no_reachable_goal)
```

The `failure_reason=no_reachable_goal` confirms the fallback ring scan ran
out of radius before finding any passable cell in the start's region.

## Regression after fix

After the fix routes through the region graph (enumerating all reachable
regions instead of doing a fixed-radius ring scan), the smoke prints
`SMOKE_TEST_RESULT: PASS` and reports a canonical navcell with `x ≈ 29`.
Add the smoke to `simnav/smoke` once green.

## Cross-refs

- [LAB-001](lab-001-default-avg-step.md) — fewer fallback bailouts means fewer wasted lab retries
- [LAB-002](lab-002-stress-long-frames.md) — slow region walks could appear here; instrument both at the same time
