# LAB-001: Default avg step ~0.45ms vs ~0.1ms target

- Status: open
- Severity: P1
- Layer: lab
- Source: codex-discussion
- Created: 2026-05-07

## Symptoms

Recent `rtslab/smoke` `default` scenario reports
`avg_step_usec ~= 450-480`. The earlier remembered baseline was ~100,
i.e. ~4–5× slower today. See BASELINE for the metric source.

## Current read

Not enough evidence to call this a core correctness bug. The lab now
runs richer navigation behavior than the old baseline: reachable goal
handling, canonical targets, richer result objects, obstacle-aware
queries, and debug/smoke metadata. Some overhead is core-contract cost,
but the lab also controls *when* those richer queries are requested in
the playable hot path.

## Investigation backlog

- Compare `RtsPathfindingLabPathfinder.plan_path()` hot-path usage
  against `inspect_core_primitives()` debug-only usage. The playable
  path should not request validation metadata every step.
- Track per-scenario plan counts, especially default movement after
  path completion and near-arrival frames.
- Cache reachable / canonical targets at the lab layer when the command
  target and obstacle revision have not changed.
- Consider a UnitMotion-style request budget so one frame does not
  synchronously perform every expensive path request.
- Only investigate core optimization after a core-only benchmark proves
  the path-only query is too slow without lab policy overhead.

## Proposed approach

1. Add a per-frame breakdown to `RTS_PATHFINDING_LAB_STEP_PERF` (or a
   sibling marker) splitting the time into: plan_path, reachability
   queries, vertex query, grid query, separation, debug export.
2. Run `default` once with the breakdown; identify the dominant phase.
3. Apply the relevant fix (cache, gate, or budget) per the dominant
   phase. Re-measure.
4. Repeat until `avg_step_usec` is at or under target. Update BASELINE.

## Verify before fixing

- [ ] Confirm the ~100us legacy baseline existed under the same scenario and the same definition of "step" (could be apples-vs-oranges)
- [ ] Pick the target number explicitly (~100us? ~200us?) and lock it in BASELINE before optimization

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_001_default_avg_step.tscn
```

Smoke: [`examples/rts-pathfinding-lab/tests/repro/repro_lab_001_default_avg_step.gd`](../../examples/rts-pathfinding-lab/tests/repro/repro_lab_001_default_avg_step.gd).

Setup: instantiate `RtsPathfindingLabWorld`, call `setup_default()`,
warm-up 1 step, then drive `step(1/60)` for 60 ticks while measuring
per-step wall time with `Time.get_ticks_usec()`. Threshold ≤ 200 µs
(stretch target 100 µs; 200 µs is generous enough to ignore noise but
strict enough to catch the current regression).

At HEAD (commit 6335f32) the smoke FAILs:

```text
LAB-001 default avg_step_usec = 326–358 µs (target ≤ 200.0 µs)
SMOKE_TEST_RESULT: FAIL - LAB-001 reproduces: ... exceeds target ≤ 200.0
```

**Stability**: 5/5 runs FAIL. Avg varies 326–358 µs with machine load
(±10%); the verdict (avg > 200 µs) is stable. Note: my machine measures
326–358 µs, BASELINE notes 450–480 µs — different absolute baseline,
same bug shape.

## Regression after fix

After the lab fix lands (caching canonical / per-call request budget /
hot-path inspection trim), the smoke flips to PASS. Update BASELINE with
the new number.

## Cross-refs

- [LAB-002](lab-002-stress-long-frames.md) — same kind of work but stress scenario
- [PROCESS-001](process-001-core-lab-proof-protocol.md) — apply before blaming core
- [CORE-007](core-007-static-rasterize-aabb.md) / [CORE-008](core-008-vertex-quadrant-prune.md) / [CORE-009](core-009-heap-improve.md) — only after lab caching/budgeting fails to close the gap
- Source note: seeded from prior Codex discussion; active tracking is this issue.
