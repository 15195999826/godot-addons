# CORE-019: Sim / Render Rate Decoupling (lab architecture)

Status: **moot — subject lab deleted (2026-07-03)**. This issue is entirely
about `0ad-rts-pathfinding-lab` running its 5Hz-designed logic at a 60Hz
frame-driven cadence; that lab was removed (task-queue.md 1b: only
`dota2-rts-pathfinding-lab` is kept). No fix was ever attempted, and none is
needed now. Kept as archived architecture analysis — the observation that a
frame-rate-driven sim can make otherwise-correct per-tick logic pathological
is still valid knowledge, just no longer actionable against a live example.

<details>
<summary>Original tracking status (pre-deletion)</summary>

Status: **open / accepted limitation**. No fix attempted. Tracking entry
only — surfaces a design pivot that, if taken, would let us simplify or
delete several lab-only mitigations shipped this round.

</details>

## Symptom

Several recurring observations point at the same root cause:

- `world.metrics.applied_pushes` / `rejected_pushes` /
  `push_pressure_obstructions` / `blocked_moves` / `short_path_requests`
  counters accumulate **~12× faster than equivalent 0 A.D. counters
  would** in the same scenario.
- Concrete burst in log
  `zero_ad_rts_lab_2026-05-11T02-53-57_tick_3077.json`: tick
  2700–2779 (80 ticks ≈ 1.33 s) blue_3 chases blue_2 inside formation_9.
  Per tick the chaser fires:
  `_mark_push_pressure_obstructed` (force-to-80 via the opposes check)
  → `_handle_blocked_move` → `blocked_recovery` path-decision →
  `_compute_path_to_goal` → `short_path_requested`.
  That's 3 path_decisions per tick × 80 ticks = 240 entries (saturates
  the recent_path_decisions ring buffer) and ~80 short-path
  re-requests over 1.3 s — all for the chaser to advance ~4 px.
- Most lab-only `custom-features/` written this round
  (asymmetric-push-pressure motion-intent opposes, arrive-without-
  has_path, etc.) exist because the 0 A.D. logic, when sampled at 60 Hz
  instead of its native 5 Hz, becomes pathological at the per-tick
  level even though the per-second behavior is fine.

## Root cause

Lab simulation is **frame-rate driven**: `main scene _process(delta)`
calls `world.step(delta)` once per render frame, so the entire
motion / push / path-request pipeline fires at 60 Hz.

0 A.D. decouples its simulation from its renderer:

- **Simulation tick rate**: 5 Hz (one "turn" every 200 ms). All of
  `Push()`, `HandleObstructedMove`, `RequestShortPath`, `PerformMove`'s
  decision logic, and pressure accumulation fire **once per turn**.
- **Render rate**: 60+ fps. Renderer interpolates unit display
  positions between the previous and current turn's simulation
  positions, so the player never sees the 5 Hz simulation.
- **Per-turn sub-stepping** inside `PerformMove`: the 200 ms turn is
  sliced into navcell-sized sub-steps so collision detection stays
  accurate at full unit speed.

0 A.D.'s logic isn't more sophisticated than the lab's at the
algorithmic level — it just runs 1/12 as often, with interpolation
hiding the rate drop. The chaser case here behaves identically in
0 A.D., it just generates 5 path_decisions/sec instead of 60.

## Why this matters beyond cosmetic counters

Several lab-only deviations from 0 A.D. only exist because we are
running 0 A.D. logic at 12× its design frequency:

| Lab-only feature (this round) | Would still be needed under 5 Hz sim? |
|---|---|
| asymmetric push pressure (only pusher pays) | Probably yes — improves on 0 A.D. directly |
| arrive epsilon without `not has_path()` | Yes (orthogonal — about path-queue churn, not rate) |
| motion-intent opposes check (combined with attempted_move) | Borderline — at 5 Hz `attempted_move` is much longer, the original 0 A.D. check might suffice |
| `_push_max_distance` no same-control-group short-circuit | 0 A.D. parity correction, keep regardless |
| chaser blocked-recovery throttle (proposed, not shipped) | **No** — at 5 Hz the burst rate is naturally tolerable |

So a 5 Hz sim could probably let us drop the chaser throttle entirely
and simplify the motion-intent opposes check back to 0 A.D. parity.

## Fix options

| Tier | Approach | Investment |
|---|---|---|
| **Light** | Add a per-unit cooldown on `_handle_blocked_move` and `_request_short_path` (e.g. fire at most every 12 ticks). Lab stays frame-driven, but logic frequency falls to ~5 Hz. | Small (~30 lines) |
| **Medium** | Fixed-timestep accumulator: `_process(delta)` accumulates dt, calls `world.step(SIM_TICK_INTERVAL)` whenever accumulator ≥ 200 ms. Renderer reads `unit.prev_render_pos` and `unit.position` and lerps by `alpha = accumulator / interval`. Visualizer needs a small refactor to consume the lerped position. | Medium |
| **Heavy** | Full sim/render thread split. Sim runs on its own timer / thread; PerformMove gets navcell-sized sub-steps; smoke tests gain deterministic replay. | Large |

Medium is the architecturally correct mirror of 0 A.D. and is the
natural next step if the lab is meant as a long-running 0 A.D. parity
testbed. Light is a cheaper mitigation that hits the immediate
counter-flood symptom without committing to interpolation.

### Medium sketch

```gdscript
var _sim_accumulator: float = 0.0
const SIM_TICK_INTERVAL: float = 0.2  # 5 Hz, matches 0 A.D.

func _process(delta: float) -> void:
    _sim_accumulator += delta
    while _sim_accumulator >= SIM_TICK_INTERVAL:
        for unit in world.units:
            unit.prev_render_position = unit.position
        world.step(SIM_TICK_INTERVAL)
        _sim_accumulator -= SIM_TICK_INTERVAL

    var alpha: float = _sim_accumulator / SIM_TICK_INTERVAL
    for unit in world.units:
        visualizer.set_display_position(
            unit, unit.prev_render_position.lerp(unit.position, alpha)
        )
```

Caveats:

1. `_perform_move` must sub-step internally (navcell-sized chunks) so a
   200 ms step doesn't sweep past a dynamic obstacle without hitting
   `validate_movement_line` mid-way.
2. User input latency rises to 0–200 ms — acceptable for 0 A.D.-style
   RTS pacing, possibly not for fast-twitch demos.
3. Existing smokes that assert "after N ticks at 1/60 dt" need to be
   re-expressed in terms of simulation time rather than tick count.

## Related

- CORE-018 visibility-graph gap detour — both are deferred
  architectural items; sim/render rate decoupling does **not** fix
  CORE-018 but reduces the per-second cost of the wasted vertex-graph
  re-requests it currently triggers.
- `examples/0ad-rts-pathfinding-lab/docs/custom-features/asymmetric-push-pressure.md`
  — its "Follow-up: motion-intent-based opposes check" section may
  collapse back to the plain 0 A.D. check once sim rate is fixed.
- `docs/references/0ad-source-map.md` — Sim/render decoupling lives in
  `CCmpUnitMotionManager.h` (per-turn `Push()`) and 0 A.D.'s renderer
  (interpolation), worth re-reading before committing to Medium.
