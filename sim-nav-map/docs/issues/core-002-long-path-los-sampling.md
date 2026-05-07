# CORE-002: LongPathfinder LOS refinement sampling can miss narrow gaps

- Status: open
- Severity: P0
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

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
`addons/sim-nav-map/tests/repro_core_002_long_path_los_sampling.gd`
that asserts the refined path has no segment crossing a blocked cell.
That smoke replaces this section.

## Cross-refs

- [CORE-005](core-005-clearance-extension-radius.md) — both want a real navcell-line iterator
- [LAB-003](lab-003-active-jump-55px.md) — corner-crossing waypoints can amplify visible jumps
