# Tick Model For Dota2 Auto Battle

Status: design contract draft. No runtime implementation exists yet.

## Decision

`dota2-auto-battle` uses a single-threaded fixed logic tick.

- Logic is the only authority for controller state, combat, targeting, movement
  intent, cooldowns, HP, death, and event emission.
- Godot render frames provide elapsed real time, but they do not own simulation
  decisions.
- The frontend reads logic frames and events. It must not mutate battle state.
- Multi-threaded logic is not part of this example's design path. If a future
  project needs an isolated simulation runtime, it should be designed as a new
  runtime boundary instead of treating this example as a stepping stone.

The default playable frontend should use a small frontend-owned logic clock
block with finite catch-up:

```gdscript
const LOGIC_DT_MS := 1000.0 / 30.0
const MAX_LOGIC_STEPS_PER_RENDER_FRAME := 2
const MAX_ACCUMULATOR_MS := LOGIC_DT_MS * MAX_LOGIC_STEPS_PER_RENDER_FRAME
```

This gives the frontend a small tolerance for occasional long frames without
allowing an unlimited catch-up spiral.

## Why Fixed Tick

DOTA2-style lane combat needs stable "seconds" semantics:

- attack cooldowns,
- aggro rechecks,
- chase and stop decisions,
- DOT/HOT intervals,
- projectile travel timing,
- future cast point and backswing timing.

Variable delta logic would make these systems harder to reason about and harder
to test. Fixed tick keeps battle behavior tied to logic frames instead of render
frame timing.

## Catch-Up Policy

Catch-up is supported, but it is not considered the standard path.

The intended path is:

1. a render frame arrives,
2. exactly one fixed logic tick is executed when enough time has accumulated,
3. frontend renders from the latest logic frame.

When a render frame is late, the logic clock block may execute more than one
fixed logic tick in the same render frame, up to
`MAX_LOGIC_STEPS_PER_RENDER_FRAME`.

When accumulated debt exceeds `MAX_ACCUMULATOR_MS`, the logic clock block must
drop the extra debt instead of trying to fully catch up. This means a very long
stall may cause a short simulation slowdown, but it must not create a runaway
loop of logic work.

## Warning Log Contract

Any catch-up or debt drop must emit a warning log.

This is intentional. Catch-up is a tolerance mechanism, not a normal operating
condition, and it should be visible during tuning and frontend profiling.

The frontend-owned logic clock block must call `Log.warning(...)` when either
condition happens:

- more than one logic tick is executed during one render frame;
- accumulated debt is clamped or dropped.

The warning should include enough data to diagnose the frame:

- `real_delta_ms`,
- `accumulator_ms_before`,
- `logic_steps_executed`,
- `dropped_debt_ms`,
- current `logic_tick_index`.

One warning per affected render frame is acceptable. If a later implementation
adds rate limiting, it must still report catch-up as warning-level telemetry and
must include aggregate counts instead of silently downgrading it to debug.

Normal one-tick advancement should not log a warning.

## Logic Clock Shape

The first version should not create a dedicated `Dota2SimulationDriver.gd`.
That would add a formal architecture class before the example has enough
runtime complexity to justify it.

Instead, the render-facing scene should own a small private logic clock block:

```gdscript
var _accumulator_ms := 0.0

func _process(delta: float) -> void:
    _advance_logic_clock(delta * 1000.0)
    _world_view.render_interpolated(_get_render_alpha())
```

The private clock block owns the accumulator and catch-up policy:

```gdscript
func _advance_logic_clock(real_delta_ms: float) -> void:
    var accumulator_before := _accumulator_ms
    _accumulator_ms += real_delta_ms

    var dropped_debt_ms := 0.0
    if _accumulator_ms > MAX_ACCUMULATOR_MS:
        dropped_debt_ms = _accumulator_ms - MAX_ACCUMULATOR_MS
        _accumulator_ms = MAX_ACCUMULATOR_MS

    var steps := 0
    while _accumulator_ms >= LOGIC_DT_MS and steps < MAX_LOGIC_STEPS_PER_RENDER_FRAME:
        var frame := _procedure.tick_once(LOGIC_DT_MS)
        _logic_frame_sink.push_frame(frame)
        _accumulator_ms -= LOGIC_DT_MS
        steps += 1

    if steps > 1 or dropped_debt_ms > 0.0:
        Log.warning("Dota2AutoBattle catch-up frame", {
            "real_delta_ms": real_delta_ms,
            "accumulator_ms_before": accumulator_before,
            "logic_steps_executed": steps,
            "dropped_debt_ms": dropped_debt_ms,
            "logic_tick_index": _procedure.get_tick_index(),
        })
```

The concrete private method names can change, but the ownership must not:

- frontend scene owns real-time accumulation;
- procedure owns fixed-step simulation order;
- logic frame sink stores frames/events for frontend consumption;
- view renders snapshots and events only.

Within one fixed Procedure tick, controller decisions and intent execution are
separate. Controllers do not rebuild intents every tick; they keep a persistent
`current_intent` and only decide when its lifecycle requires it. The expected
shape is:

```text
1. tick ability/cooldown durations
2. cleanup dead actors and invalidate impossible current intents
3. update targeting helpers or spatial indexes
4. controller decision step: create/keep/interrupt current intents
5. movement and ability systems advance current intents
6. controller result step: record COMPLETED/FAILED/RUNNING results
7. emit frame/events
```

The exact implementation can change, but both decision and intent execution must
happen inside fixed logic ticks, not from render callbacks or view nodes
directly.

Extract this block into a dedicated class only after there is real pressure to do
so, such as multiple frontend scenes sharing the same clock, a step-frame debug
UI, runtime speed controls, or separate headless/live runners that need the same
catch-up policy.

## Rejected Alternatives

### Variable Delta Logic

Rejected. It makes cooldowns, movement, aggro, and authored timing less stable
and harder to test.

### Unlimited Catch-Up

Rejected. A long render stall could create many logic steps in one frame and
make the stall worse.

### No Catch-Up In Playable Frontend

Rejected as the default. It is useful for a debug mode, but it makes gameplay
speed depend too directly on render performance. The default should tolerate
small frame delays while warning when this happens.

### Multi-Threaded Logic

Rejected for this example. The added complexity in request queues, snapshot
copying, ordering, and Godot thread boundaries is not justified for this local
single-player example.

## Acceptance Criteria

- Logic uses a fixed timestep.
- Logic and frontend run on one thread.
- The frontend does not mutate controller state, combat, target, movement,
  cooldown, HP, or death state directly.
- The first version keeps accumulator/catch-up code in the frontend scene as a
  private logic clock block, not a standalone simulation-driver class.
- Catch-up is finite and capped by `MAX_LOGIC_STEPS_PER_RENDER_FRAME`.
- Excess accumulated debt is dropped instead of fully chased.
- Any catch-up frame emits `Log.warning`.
- Any debt clamp/drop emits `Log.warning`.
- The warning includes timing and tick-count data useful for profiling.
