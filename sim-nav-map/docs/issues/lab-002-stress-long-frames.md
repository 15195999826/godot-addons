# LAB-002: Stress long frames still 10-15ms

- Status: open
- Severity: P1
- Layer: lab
- Source: codex-discussion
- Created: 2026-05-07

## Symptoms

Pre-gating, stress scenes spiked on vertex queries:

- `dynamic_edit_stress` near step 53: `vertex_usec ~= 35-36ms`
- `comprehensive_scripted_stress` case 5 near step 25: `vertex_usec ~= 26-27ms`

Post-gating, vertex spikes are reduced, but max frames can still hit
10–15 ms, now mostly grid / long-path work.

## Current read

This looks like a scheduling / budgeting problem more than a wrong core
query. The lab can still ask for an expensive long path synchronously on
a crowded, edited, or edge-heavy frame.

## Investigation backlog

- Add or use phase-level profiling to identify whether the remaining
  long frame is grid search, obstacle rebuild, separation, or debug
  export.
- Avoid synchronous long-path retries immediately after a failed vertex
  attempt.
- Defer or budget long-path requests over multiple frames in stress
  scenarios.
- Use obstacle revision and command-target keys to avoid recomputing
  equivalent long paths.
- Re-check 0 A.D.'s queued path request pattern before adding another
  ad-hoc lab shortcut.

## Proposed approach

1. Reuse the breakdown introduced for [LAB-001](lab-001-default-avg-step.md)
   to attribute the 10–15 ms.
2. If the dominant phase is long-path: introduce a per-frame request
   budget at the lab layer, leaning on
   `SimNavPathRequestQueue.process_budget()`.
3. If the dominant phase is grid / obstacle rebuild during dynamic
   edits: throttle rebuild cadence; reuse cached canonical targets when
   revision has not changed.
4. If the dominant phase is core-side, re-measure with a core-only
   benchmark before promoting a perf fix to a core issue (see
   [CORE-007](core-007-static-rasterize-aabb.md), [CORE-008](core-008-vertex-quadrant-prune.md)).

## Verify before fixing

- [ ] Confirm the existing `RTS_PATHFINDING_LAB_STEP_PERF` already gives enough resolution per phase, or extend it
- [ ] Decide on stress scene target: peak frame ≤ ?ms; lock in BASELINE before optimization

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_002_stress_long_frames.tscn
```

Smoke: [`examples/rts-pathfinding-lab/tests/repro/repro_lab_002_stress_long_frames.gd`](../../examples/rts-pathfinding-lab/tests/repro/repro_lab_002_stress_long_frames.gd).

Setup: `setup_default()` + warm-up 5 steps. Then drive 360 ticks while
injecting rapid obstacle edits — drop a blocker every 6 ticks
(alternating row), remove the nearest editable every 9 ticks, re-issue
the group target every 30 ticks. Track max single-step wall time.
Threshold ≤ 4 000 µs.

At HEAD (commit 6335f32) the smoke FAILs:

```text
LAB-002 stress max_step_usec = 4719–8090 µs at step 3–47 (target ≤ 4000 µs, BASELINE ~10000–15000 µs)
SMOKE_TEST_RESULT: FAIL - LAB-002 reproduces: max single-step wall time = 4719–8090 µs ...
```

**Stability**: 7/7 runs FAIL. Peak varies 4719–8090 µs (±25%) due to
obstacle-edit timing within a tick. The verdict (peak > 4 000 µs) is
stable on this machine. BASELINE machine reported 10–15 ms — same bug
shape, different absolute timing.

**Initial threshold note**: an earlier 5 000 µs threshold was flaky
(4/5 FAIL, 1 PASS at 4798 µs). Threshold lowered to 4 000 µs gives
robust 7/7 FAIL with > 700 µs margin to the smallest observed peak.

## Regression after fix

After the lab fix lands (per-call budget / cached canonical / obstacle-
revision keys / phase profiling), the smoke flips to PASS. Update
BASELINE with the new peak.

## Cross-refs

- [LAB-001](lab-001-default-avg-step.md) — same instrumentation
- [LAB-003](lab-003-active-jump-55px.md) — long synchronous frames can amplify visible jump
- [PROCESS-001](process-001-core-lab-proof-protocol.md)
- Source note: seeded from prior Codex discussion; active tracking is this issue.
