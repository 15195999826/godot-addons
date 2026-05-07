# CORE-002: LongPathfinder LOS refinement sampling can miss narrow gaps

- Status: resolved
- Severity: P0
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07
- Resolved: 2026-05-07

## Resolution

- submodule commit: `7111d3a`
- smoke: `addons/sim-nav-map/tests/repro/repro_core_002_long_path_los_sampling.tscn` (registered under `simnav/smoke` group)
- 0 A.D. files checked: `source/simulation2/helpers/Pathfinding.cpp::CheckLineMovement` (per-cell traversal model)
- Fix: replaced uniform-step sampling at `navcell*0.5` in `_segment_passable_clear` with an Amanatides-Woo voxel traversal that visits every navcell the segment crosses. Cannot skip a cell regardless of the segment's geometry, so the bug class is geometrically eliminated rather than tuned away.
- Adversarial smoke: the issue's text noted "Toy diagonal-wall scenarios... do not trigger the bug — sampling at navcell_size * 0.5 is robust enough that 2-3 sample points always land inside the blocked cell". An analytically-constructed segment `(32, 47) → (52, 49)` on a 16×16 grid with cell `(5, 5)` blocked DOES trigger it: `steps = ceil(20.10 / 4) = 6`, samples land at `t ∈ {0, 1/6, 2/6, 3/6, 4/6, 5/6, 1}` and the segment is inside cell `(5, 5)` only for `t ∈ [0.40, 0.50]` (arc ≈ 2 px) — squarely between two adjacent samples. The smoke calls `_segment_passable_clear` directly via `Object.call` and asserts the result is `false`. Pre-fix returns `true` (FAIL), post-fix returns `false` (PASS).
- baseline impact: `BASELINE.md` "Known correctness limits": removed CORE-002 row. Refined waypoint paths now provably never cross blocked cells.
- public-api.md: no change. `_segment_passable_clear` remains an internal helper.

## Symptoms

After `_refine_waypoint_path()` runs LOS-based waypoint compression, the
resulting path may keep a "diagonal shortcut" segment that crosses one or
more impassable navcells the original JPS path went around. In stress
scenes this manifests as units appearing to clip a 1-cell-wide wall edge
near corners.

## Root cause

`addons/sim-nav-map/pathfinding/sim_nav_long_pathfinder.gd:274-288`,
`_segment_passable_clear()` samples the segment at a fixed step of
`navcell_size * 0.5`:

```gdscript
var step := navcell_size * 0.5
# walk start → end, query passability at each sample point
```

A diagonal segment can pass cleanly through every sample point yet still
cross through the corner of an impassable navcell that no sample lands in
— classic Bresenham-vs-uniform-sampling failure mode.

## 0 A.D. reference

`docs/references/0ad-source/source/simulation2/helpers/Pathfinding.cpp`
`CheckLineMovement()` traverses navcell-by-navcell along the segment using
a Bresenham-style increment. Every navcell the segment intersects is
inspected. There is no possibility of skipping a cell.

## Proposed fix

Two acceptable directions, in order of preference:

1. **Replace uniform sampling with navcell-grid traversal.** Implement a
   Bresenham-style stepper that yields each navcell `(i, j)` the segment
   crosses, then check passability per cell. This is the 0 A.D.-faithful
   path and removes step-size tuning. Reuse for the missing
   `CheckLineMovement` primitive surfaced as part of [CORE-005](core-005-clearance-extension-radius.md).
2. **Tighten step size as a stopgap.** If full Bresenham is too invasive
   for this fix, drop step to at least `navcell_size / 4` and add explicit
   end-cell checks (start-cell and goal-cell). Document this as a stopgap
   and link this issue.

The Bresenham traversal also unblocks giving short paths a real
`CheckLineMovement` query (currently only obstruction-distance checks
exist in `sim_nav_line_of_sight.gd`).

## Verify before fixing

- [ ] Re-read `_segment_passable_clear()` to confirm the sampling step
- [ ] Confirm there is no other LOS check elsewhere in the file already doing per-cell walk
- [ ] Decide whether to extract a shared navcell-line iterator for reuse with CORE-005

## Repro at HEAD (smoke pending adversarial scenario)

**No smoke yet.** Toy diagonal-wall scenarios (e.g. blocked cells `(7,7)`
and `(8,8)` on 16×16 grid) do not trigger the bug — sampling at
`navcell_size * 0.5` is robust enough that 2-3 sample points always land
inside the blocked cell. To trigger the miss, the refined segment must
cross a blocked cell with arc-length < `navcell_size * 0.5` AND no
sample falls in the cell — geometrically possible but hard to hit on
small synthetic grids.

Manual recipe to characterize:

1. In a real lab scene, find a refined long-path waypoint pair `(A, B)`
   that visually grazes the corner of a static obstacle.
2. Walk the segment cell-by-cell with a Bresenham iterator (in addition
   to the visited-cell test that 0 A.D. uses, also include cells whose
   2D rectangle the segment intersects, even if Bresenham skips them).
3. If any visited / intersected cell is impassable for the request's
   passability mask, the segment is illegal and the bug is reproduced.

**Smoke deliverable** (when adversarial scenario is found): place
that exact OBB+passability+goal in a new
`addons/sim-nav-map/tests/repro/repro_core_002_long_path_los_sampling.gd`
that asserts the refined path has no segment crossing a blocked cell.
That smoke replaces this section.

## Cross-refs

- [CORE-005](core-005-clearance-extension-radius.md) — both want a real navcell-line iterator
- [LAB-003](lab-003-active-jump-55px.md) — corner-crossing waypoints can amplify visible jumps
