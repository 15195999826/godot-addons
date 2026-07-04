# CORE-020: Push Brushes Unit Sub-Pixel Into Static Clearance Ring at High Pressure

Status: **DORMANT (2026-05-11)**. Originally discovered by an AI-driven
exploration script during stress-test instrumentation, not by anyone
hand-testing the lab. The artifact is **sub-pixel** (0.77 px brush) with
**5–8 tick self-recovery** under crowded conditions; no path corruption
or permanent stuck. Severity is low and the surface is not visible during
normal demo play.

The CORE-018 fix (2026-05-11) changed short-path behavior in dense unit
clusters, which altered the swarm stress test trajectory at seed=42 just
enough that the deterministic violation at tick 362 no longer reproduces
within the 380-tick budget. The root cause (LOS boundary handling under
push at zero-path conditions) is unfixed; the trigger conditions just
happen to not assemble under the new short-path dynamics for that seed.

**Decision (2026-05-11)**: pull `repro_core_020_motion_brushes_clearance_under_push_known_limit`
out of the `zeroadlab/smoke` group so it does not block daily regression.
The repro file itself was retained in
`examples/0ad-rts-pathfinding-lab/tests/repro/` for future use; if anyone
sees the sub-pixel brush artifact during real play, re-enable the test
(or adjust the seed/budget) and proceed with the original fix options.

**Update (2026-07-03)**: `0ad-rts-pathfinding-lab` (and this repro file with it)
was deleted — only `dota2-rts-pathfinding-lab` is kept as the sim-nav-map
example (task-queue.md 1b). The re-enable plan above no longer has a repro
artifact to re-enable. The underlying root cause (LOS boundary handling under
push at zero-path conditions, in core) is still formally unfixed, but
`dota2-rts-pathfinding-lab`'s motion engine resolves unit-unit separation by
contact (units never enter the nav map), not by pushing through the core
clearance ring this issue describes — so it's unconfirmed whether this
specific manifestation still has a live surface anywhere. Re-open with a new
repro if the sub-pixel artifact is ever observed again; do not assume it
carries over 1:1 to the new lab's architecture.

## Symptom

In a dense moving cluster (`stress_playthrough.tscn -- --swarm`, 50 mobile
units, default seed=42, retarget every 120 ticks), at tick 362 unit
`swarm_3` enters `north_block`'s clearance ring 0.77 px deep at
position `(430.33, 114.23)`. The unit was not commanded into the ring;
its target `(500.31, 95.30)` and prior trajectory keep it **outside** the
ring under pure-motion conditions.

## Reproduction

1. Run `stress_playthrough.tscn -- --swarm` (seed=42, 50 units).
2. Output:
   ```text
   SWARM_VIOLATION: static_clearance tick=362 units=["swarm_3@(430.3,114.2) in north_block"]
   ```
3. After CORE-019 fix (path queue is fully deterministic), this
   reproduces bit-exact on every run.

A 1-unit minimal version of the same trajectory (no other units, same
spawn position, same target) does **not** reproduce — the unit walks the
detour cleanly. The bug requires the full crowded-cluster context.

## Trace at the violation tick

```text
unit       = swarm_3
pos        = (430.332, 114.227)   ← inside ring 0.77 px (depth on y axis)
target     = (500.31, 95.30)
long_path  = []                    ← empty (post-retarget, path not yet processed)
short_path = []
has_move_order = true
arrived    = false
move_failed= false
pushing_pressure = 76              ← near MIN_PRESSURE_IF_OBSTRUCTED=80
nearest_neighbour = swarm_8 d=20.40 ← in contact (combined radius=22)

trace last 8 ticks (oldest → newest):
  t-7 (430.84, 115.15)   ← y just above ring top y=115
  t-6 (429.92, 115.24)
  t-5 (429.01, 115.33)
  t-4 (428.09, 115.42)   ← drifting west along boundary
  t-3 (427.18, 115.51)   ← westernmost
  t-2 (428.04, 115.27)   ← turn east
  t-1 (428.93, 115.03)   ← y arrives at boundary
  t-0 (430.33, 114.23)   ← y crosses into ring 0.77 px, x jumps 1.4
```

The unit was **oscillating** along ring boundary y≈115 for 7 ticks under
push pressure from `swarm_8` (and likely others); the final tick's push
amplitude was large enough to cross y=115 by 0.77 px.

## Root cause analysis

`apply_push_adjust` validates each candidate position via
`validate_movement_line(unit, unit.position, candidate, units, false)` and
applies the push only when the LOS query succeeds.

For unit position **on** the ring boundary (y=115.000 = `north_block`'s
clearance top edge), the directional LOS rule
(`Geometry.cpp:308 TestRayAASquare`) treats the start point ambiguously
depending on whether the boundary is inclusive or exclusive in the
implementation:

- 0 A.D.'s rule: `if -hw <= a.X <= hw && -hh <= a.Y <= hh return false` —
  start strictly inside the obstruction → no cross detected (allow
  inside-to-anywhere escape).
- For a candidate that lands inside the ring from a boundary start, the
  same predicate sees `a` as "inside" (because boundary is inclusive in
  the `<=` test) and returns "not crossed" → push applied → unit ends
  inside the ring.

The bug only surfaces when **all** of these are true:
1. Unit center sits within ~1 px of a static clearance ring edge.
2. Unit has zero active path (path queue still processing the new
   retarget request, or a path was just consumed).
3. Push amplitude is non-trivial (high crowd density, multiple nearby
   moving units).

## 0 A.D. behavior

0 A.D. has the same `Geometry::TestRayAASquare` rule and the same push
system shape, but does not visibly suffer from this artifact in practice
because:

1. **Fixed-point coordinates** snap unit positions to integer-grid
   subdivisions. A unit cannot land at `y=115.000` exactly and stay
   there for 7 frames; either it's at `y=115` and snapped clear by
   collision resolution, or it's already `<115` and clipped out by
   regular static collision.
2. **`CCmpFormation` slot selection** thins crowd density at boundaries,
   so the trigger condition (3 above) is less common.
3. **Render snap to integer pixels** masks any sub-pixel artifact —
   even if the simulation drifts the unit center 0.5 px into a clearance
   ring, the rendered sprite stays on the outside pixel.

The lab uses GDScript floats and currently does not have a formation
controller, so all three protections are absent.

Severity in the lab: low. Self-recovery within 5-8 ticks (~80-130 ms
real-time) once unit oscillation moves position away from the boundary
and push direction changes. No path corruption, no permanent stuck.

## Fix options (deferred)

| Option | Where | Investment | Notes |
|---|---|---|---|
| **A.** Push validation also checks `obstacle.contains_point_with_clearance(candidate, radius)` and rejects strictly | `motion_controller.gd:apply_push_adjust` | small | Lab-only safety net. Conflicts with directional inside-to-outside escape semantics — would need an "is candidate strictly inside that wasn't strictly inside before" check, not just `contains_point`. |
| **B.** Path queue prioritizes units with high `pushing_pressure` so they get a path before push amplitude builds | `pathfinder.process_path_budget` | medium | Roots out the precondition (path empty) instead of the symptom (push direction). |
| **C.** Reduce push amplitude for path-empty units (units without intent shouldn't be moved by push) | `motion_controller.gd:_accumulate_pair_push` | medium | Aligns with the asymmetric pressure rule (motion intent matters). May break cases where idle units genuinely need to be nudged out of the way of moving teammates. |
| **D.** Add `CCmpFormation`-equivalent slot selection so crowd density at boundaries stays low | lab motion layer | large | Same as CORE-018 fix option D — addresses the root precondition rather than the geometric symptom. Reusable across multiple known limitations. |
| **E.** Make LOS boundary handling explicit: candidate strictly inside → block, even if start is on boundary | `sim_nav_line_of_sight.gd` (core) | small but cross-cutting | Affects all LOS callers, not just push. Needs full smoke regression after change. Closest to true root-cause fix. |

A is small and lab-only but treats only the symptom. E is the most correct
fix but cross-cutting. D is the most thorough — it would also resolve
CORE-018's visible symptom — but is a separate large effort.

No fix is shipped this round. The repro test pins the deterministic
behavior so a future fix attempt produces a clear pass/fail signal.

## How to repro

```text
./tools/run_tests.ps1 zeroadlab/smoke
# look for: repro/repro_core_020_motion_brushes_clearance_under_push_known_limit
```

The test asserts:
- swarm seed=42 stress run triggers exactly one static-clearance violation
- violation occurs at tick=362, unit=swarm_3, position ≈ (430.3, 114.2)
- violation depth on y axis is ≤ 1.0 px (sub-pixel brush, not a deep
  penetration)
- this is the deterministic outcome under CORE-019's fixed path queue
