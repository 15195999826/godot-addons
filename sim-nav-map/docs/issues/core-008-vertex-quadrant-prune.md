# CORE-008: VertexPathfinder lacks quadrant pruning

- Status: open
- Severity: P3
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

## Symptoms

The visibility-graph A* in `SimNavVertexPathfinder` builds and explores
every vertex pair, regardless of which side of the obstacle they sit on.
On dense static-obstacle maps this inflates the open list and the
per-frame vertex query cost. Likely a meaningful contributor to the
pre-gating stress vertex spike (~26-37 ms) recorded in BASELINE.

## Root cause

`addons/sim-nav-map/pathfinding/sim_nav_vertex_pathfinder.gd:246-286`
and the surrounding visibility-graph build do not prune vertices whose
"inward" half is on the wrong side of the connecting edge. There is no
analogue of 0 A.D.'s `quadInward` / `quadOutward` flags.

## 0 A.D. reference

`docs/references/0ad-source/source/simulation2/helpers/VertexPathfinder.cpp:63-101`
classifies each vertex into a quadrant relative to its parent obstacle
edge and uses that to skip clearly-redundant edge tests during graph
expansion. The pruning is a constant-factor speed-up on dense maps.

## Proposed fix

1. Add per-vertex metadata `quadInward: int`, `quadOutward: int` (e.g.
   bitmask of allowed quadrants) when generating corners from each
   static OBB.
2. During edge-visibility tests in A* expansion, skip vertex-pairs where
   the directional check fails the quadrant constraint.
3. Validate by comparing path output bit-identical (or at least same
   length within float tolerance) against pre-pruned baseline before
   landing.

This is an internal optimization; no public API change.

## Verify before fixing

- [ ] Read 0 A.D.'s implementation in detail; quadrant semantics are subtle
- [ ] Decide whether the gain is worth the code complexity for our current scale (small RTS lab); could be deferred until LAB-001 / LAB-002 numbers actually bottleneck on vertex
- [ ] Identify a stress scene that demonstrably stresses vertex (count A* node expansions) before doing the work

## Repro at HEAD (smoke pending instrumentation)

**No smoke yet.** A meaningful repro requires a debug A* node-expansion
counter in `SimNavVertexPathfinder` (currently absent). The counter must
be exposed to script (e.g. through a result metadata field or a
debug-only export) before a smoke can quantify the prune.

Manual recipe to characterize at HEAD:

1. Build a dense static-obstacle scene (e.g. 30+ small OBBs in a
   roughly-uniform grid, with a clear corridor a unit can path through).
2. Plan a short path through the corridor.
3. Time the call with `Time.get_ticks_usec()`. Expect the absolute time
   to be visibly worse than the same scene with `≤ 5` obstacles —
   confirms the visibility-graph A* is doing more work per query.

**Smoke deliverable** (after instrumentation lands): a
`addons/sim-nav-map/tests/repro_core_008_vertex_quadrant.gd` that
compares the expansion count before/after the quadrant prune on a fixed
dense scene. Acceptance: ≥ 30% reduction with bit-identical (or
float-tolerance-equal) path output.

## Cross-refs

- [CORE-001](core-001-vertex-obb-outset.md) — same vertex generation step
- [LAB-002](lab-002-stress-long-frames.md) — driver for whether the optimization ranks above core invariants
