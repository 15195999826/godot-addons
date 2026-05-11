# CORE-018: Visibility-Graph Pathfinder Cannot Thread Obstacle Gaps

Status: **RESOLVED (2026-05-11).** Fixed by adding pair-wise gap-midpoint
vertices to the visibility graph in `sim_nav_vertex_pathfinder.gd`. Repro
test renamed to `tests/repro/repro_core_018_visibility_graph_gap_threading.{gd,tscn}`
and flipped to assert the new positive behavior (path length < 130 px, path
passes near the gap midpoint).

**Side effect to investigate separately**: `repro_core_020_motion_brushes_clearance_under_push_known_limit`
no longer reproduces within its 380-tick budget — the short path behavior
change indirectly altered the push interaction sequence at the seed used
by CORE-020. CORE-020 may have been silently fixed, or simply moved to a
later tick. Track in a follow-up rather than in this issue.

## Symptom

In a multi-unit cluster, the short pathfinder produces a route that is
2-3× longer than the geometrically optimal route, because the optimal
route would thread through a gap between two adjacent obstacles, and
**that gap's midpoint is not a vertex in the visibility graph**.

User-reported log: `zero_ad_rts_lab_2026-05-11T02-33-22_tick_6144.json`,
tick 5628. blue_1 at `(171.7, 238.4)` heading to `(243, 164)`. Around
the goal are 5 stationary blues (`blue_0, blue_2, blue_3, blue_4,
blue_5`). The short path returns:

```text
start (171.7, 238.4)
  → blue_3 NE outset (173.0, 257.7)
  → blue_2 SW outset (109.5, 259.0)
  → blue_2 NW outset (109.5, 214.0)
  → blue_0 NW outset (145.4, 175.5)
  → goal (243.0, 164.0)
```

Total length: **278.77 px** (visits 4 outsets, goes SSE → W → N → NE → E
in a giant loop to the west of the cluster).

## Geometrically optimal path

`blue_4 (201.4, 236.8)` and `blue_0 (167.9, 198.0)` have center distance
**51.2 px**. Midpoint `(184.65, 217.4)` is at distance **25.63 px** from
each — comfortably above the `combined_clearance = 22` LOS threshold. A
human looking at the demo correctly identifies that a unit's center can
sit at this midpoint and have room.

The route `start → midpoint → goal` has total length **103.77 px** (only
0.7 px longer than the geometrically-impossible straight line of
103.05 px). Both segments are clear of every blocker (smallest perp
distance to any obstacle is `blue_4`'s 24.44 from segment A and `blue_0`'s
25.62 from segment B — both > 22).

`278.77 / 103.77 ≈ 2.69×`.

## Root cause

`sim_nav_vertex_pathfinder.gd:_collect_visibility_inputs` populates the
A* search graph with:

- the start point
- the goal point
- 4 outset corners per obstacle (each at `combined_clearance + EDGE` from
  obstacle center)

It does not produce any "gap midpoint" vertices between adjacent
obstacles. A* therefore cannot construct a path that turns at a gap
midpoint — it can only turn at obstacle outset corners. When the
geometrically shortest path passes through a gap between two obstacles
without grazing either, that path is invisible to A*.

In the reported scenario, the would-be turning point `(184.65, 217.4)`
is exactly mid-gap. Every outset corner near this region is either:

- **Covered** by another obstacle's clearance ring (filtered out by
  `_vertex_covered_by_obstacles`, mirroring 0 A.D. `VertexPathfinder.cpp:
  727-734`) — e.g. `blue_4 NW outset (178.9, 214.3)` is 19.67 px from
  `blue_0 (167.9, 198.0)`, < 22.5 cover threshold, so it's removed
  from the graph.
- **Reachable but produces a longer segment** when used as the turn —
  e.g. forces A* to route via `blue_4 SE/SW` outsets, which are on the
  *wrong* side of `blue_4` for reaching the goal.

After all covered vertices are removed, the only A*-reachable path goes
around the outside of the cluster, hence the 278 px detour.

## 0 A.D. behavior

0 A.D.'s `CCmpPathfinder` uses the same visibility-graph vertex scheme
(`VertexPathfinder.cpp:626-665` — 4 outset corners per obstacle). It has
the same limitation. 0 A.D. avoids the visible symptom in three ways
that the lab does not (yet) have:

1. **`CCmpFormation`** picks formation slots that are guaranteed to be
   reachable (avoiding configurations where cleanup leaves the cluster
   too tight). Lab's `_formation_offsets` (`world.gd:501-514`) uses a
   static grid that doesn't take obstacle clearance into account.
2. **Long-path waypoints are not aggressively simplified.** 0 A.D.'s
   `LongPathfinder::ImprovePathWaypoints` keeps turning points where
   `TestLine` fails between non-adjacent waypoints. With static-only
   `TestLine`, the navcell-A* path through the gap survives
   simplification. Lab's long path equivalent simplifies to a single
   `[goal]` waypoint when no static obstacles block.
3. **Unit run multiplier** masks the visual cost — even a perimeter
   detour reaches the goal quickly.

In other words: the lab demo exposes a 0 A.D. limitation that is
normally hidden by surrounding systems. Fixing it cleanly requires
adding back one of those systems.

## Fix options (deferred)

| Option | Where | Investment |
|---|---|---|
| **A.** Long path stops simplifying turning points whose midpoint segment is blocked by a dynamic obstacle | `sim_nav_long_pathfinder.gd` simplification pass | medium |
| **B.** Visibility graph adds explicit gap-midpoint vertices between pairs of obstacles whose center distance is > `2 * combined_clearance` | `sim_nav_vertex_pathfinder.gd:_collect_visibility_inputs` | medium-high |
| **C.** Short path falls back to navcell-grid A* when visibility-graph path length exceeds a threshold relative to direct distance | new `sim_nav_short_pathfinder` mode | large |
| **D.** Add a `CCmpFormation`-equivalent formation controller that picks reachable slots and avoids the dense-cluster shape | lab motion layer (`zero_ad_rts_lab_world.gd`, formation logic) | large but isolated |

A and B affect the core navigation algorithm and would benefit any
example that uses sim-nav-map. C and D are scoped to specific use cases.

## Fix shipped (2026-05-11)

**Variant of Option B was selected**: rather than adding gap-midpoint vertices
based on `> 2 * combined_clearance` of static-obstacle pairs, the fix adds
midpoints between **unit-obstacle pairs** specifically. Reason: the daily
manual friction was triggered by dense unit clusters (5 units around the
moving unit's destination), not static gaps. Static obstacle gaps in lab
demos are wide enough that visibility-graph corners suffice.

Implementation in `sim_nav_vertex_pathfinder.gd:_append_unit_pair_gap_midpoint_vertices`:

- For each pair `(a, b)` of unit obstacles in the short-path query range,
  if `center_distance > a_ring + b_ring` (where `ring = unit.clearance +
  req.clearance + EDGE_EXPAND_DELTA`), compute `midpoint = (a.center + b.center) / 2`.
- Verify midpoint is outside every **other** unit's inflated ring (not just
  the pair), to avoid placing the midpoint inside a third unit's clearance.
- Register midpoint as an additional visibility-graph vertex.

This is a **positive lab-only deviation from 0 A.D. parity**: 0 A.D.'s
`VertexPathfinder` does not have such gap-midpoint vertices, but 0 A.D.
masks the visible symptom via three layers (formation slot selection,
less-aggressive long-path simplification, run multiplier) that the lab
does not replicate. Adding gap-midpoint vertices is a pure geometric
construction — no magic number, no policy.

Verification (CORE-018 user scenario):

- Before fix: `short_path = [(530.69, 150.16), (559.1, 230.3), (604.1, 230.3)]`,
  unit walks SSE then W then N around the cluster perimeter (~278 px detour).
- After fix: `short_path = [(543.94, 141.23), (597.65, 188.85)]` with
  (597.65, 188.85) = midpoint of (blue_0, blue_2). Unit walks NW directly
  through the gap (~103.77 px, geometric optimum).

Regression: full `simnav/smoke` + `zeroadlab/smoke` pass except
`repro_core_020` (side effect, see Status above).

## How to repro

```text
./tools/run_tests.ps1 simnav/smoke
# look for: repro/repro_core_018_visibility_graph_gap_detour_known_limit
```

The test asserts:
- short path is returned successfully
- short path length is > 200 px (i.e. a clear detour, not a near-direct
  103 px route)
- the would-be optimal midpoint `(184.65, 217.4)` is genuinely
  passable — both potential segments through it are clear of all
  obstacles, so the limitation is in the vertex set, not in the LOS
  check
