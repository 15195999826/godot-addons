# Fable Motion Design

2026-07-02. This design replaces the v1/v2 motion controller line
(five-state FSM, async ticket lifecycle, slide/relax tiers, detour-waypoint
insertion, HOLDING retry loop — all removed). It was written from scratch
after user verdicts judged both prior iterations' feel unacceptable.

## Stance

**Unit-vs-unit avoidance is not a pathfinding problem. It is a contact
problem.**

The prior failures all came from treating other units as things to *route
around*: detour waypoints (chord-math avalanche), unit-aware line validation
(same-tick staleness), holding/retry loops (forever-waiting orders). The
fable model splits responsibilities so those bug classes cannot exist:

- **Paths know only the static world.** Units never enter the nav map. Long
  paths come from `SimNavPathfinderFacade` synchronously at command time,
  with reachable-goal canonicalization (an unreachable goal becomes a path to
  the nearest reachable point — no retry loop needed, ever).
- **Contacts are resolved positionally.** Every tick, after all units take
  their intended step, an iterative separation solve splits overlapping pairs
  apart and projects bodies out of static shapes and map bounds
  (commit-then-resolve). Overlap cannot persist across a tick beyond the
  solver residual, by construction.
- **Facing is intention; pushes move bodies, not intentions.** The desired
  heading comes only from the path. Crowd pressure displaces a unit but never
  re-aims it, so pushing cannot cause pirouettes or heading oscillation.

## Tick pipeline (`Dota2LabMotionEngine.step`)

```text
Phase A  intent step        (per MOVING unit)
         shortcut path      raster-LOS pop of reached/visible waypoints
         turn               rotate_toward(desired), turn-rate capped
         walk               step along FACING, speed × alignment ramp
Phase B  separation solve   (all units, SEPARATION_ITERATIONS rounds)
         pair split         weighted by pushability, head-on lateral bias
         static project     circle-vs-OBB exact geometry + bounds clamp
Phase C  arrival + watchdog (per MOVING unit)
         arrive             dist(effective_target) ≤ ARRIVE_RADIUS
         near-goal stall    settle as arrived_crowded
         far stall          one replan, then fail as stalled
```

Everything iterates in array order — deterministic given identical inputs.

### Turn/walk pipeline

One movement rule for every situation: turn toward the tracking point, walk
along facing. There is no sideways displacement anywhere in the system (the
v1 ice-drift source). The walk-speed factor ramps linearly from full speed at
`TURN_ALIGN_FULL_RAD` (~11.5°, the Dota2 action cone) to zero at
`TURN_ALIGN_ZERO_RAD` — a continuous function, so a wobbling desired heading
cannot flip a binary walk gate (the v2 pirouette source). Because walking
happens along facing while still turning, curved approach arcs fall out for
free.

**Contact steering** (`contact_steering_enabled`, default on, lab UI toggle):
when a unit closes nose-first on a body that will not yield to it (equal or
lower pushability, or an immobile blocker), its desired heading gains a
tangential bias — continuous in gap and frontness. The unit then WALKS
around the contact through the normal turn/walk pipeline, keeping heading,
displacement, and visuals aligned. Off, squeezing past a non-yielder is
driven by Phase B pushes alone and reads as sideways translation (facing
locked on the path while the body slides). Anchored in smoke: rounding a
solid idle body keeps the per-tick displacement-vs-facing dot above 0.9
(measured ~0.99).

The go-around side follows geometry — whichever side of the contact the
intended direction already leans toward (nearest side), decided per unit via
`cross(to_other, intent)`. It is locked on the unit while contact persists
(no mid-squeeze flip-flops), released when contact breaks, and dead-center
ties fall back to a fixed handedness deterministically. Phase B's head-on
lateral push reuses the same side decision (lock first, then the same
geometry), so intent and push never fight. Smoke-anchored: starting slightly
right of a blocker's axis rounds right, slightly left rounds left.

### Separation solve

- Pair correction is split by **pushability**: `0` for `mobile == false`
  (unpushable round blocker), and runtime-tunable engine fields for the rest
  (`pushability_moving`, default `0.35`; `pushability_idle`, default `1.0`).
  Two flavors ship as presets, switchable live in the lab UI and settable by
  integrating projects on the engine instance:
  - **Soft (LoL)** — idle `1.0`: a mover shoves idle units aside.
  - **Hard (Dota2)** — idle `0.0`: a stopped unit is a solid body; movers
    round it via contact sliding. This is the creep-blocking flavor (real
    Dota2 blocks friend and foe alike — opening creep-blocking blocks your
    OWN creeps).
  Any value in `[0, 1]` is safe — overlap between mobile bodies is always
  resolved. Pushability decides *who yields*, physics decides *that they
  separate*: a both-zero pair splits evenly (rigid, never ghost), and only
  `mobile == false` blockers are truly immovable. Note mover-vs-mover
  contacts normalize to 50/50 regardless of the moving value; the sliders
  really tune who yields in mover-vs-idle contacts.
- **Head-on lateral bias**: when a mover is pushing nose-first into the other
  body (`|facing · dir| > 0.85`), the correction direction gains a
  fixed-handedness perpendicular component. This is the deadlock breaker:
  opposing streams lane-sort, idle units get shoved *aside* rather than
  bulldozed forward, and a dead-center blocker contact gains the eccentricity
  that sliding needs. Handedness is global and constant — deterministic.
- Static projection uses exact circle-vs-OBB geometry (paths keep the
  conservative raster band; contact does not). A unit dropped inside a shape
  is pushed out through the shallowest face — spawn-inside recovery for free.
- Coincident centers split along a deterministic id-ordered axis.

### Termination semantics (no order lives forever)

| Outcome                | Trigger |
|---|---|
| `arrived`              | within `ARRIVE_RADIUS` of the effective target |
| `arrived_partial`      | same, but the goal was canonicalized (asked-for point unreachable) |
| `arrived_crowded`      | within `NEAR_GOAL_RADIUS` and no goal-distance progress for `STALL_NEAR_COMPLETE_SEC` (clicking into a crowd stops at its edge; also catches crowd-ring orbiting) |
| `failed: no_path`      | core query failure (rare — canonicalization covers unreachable goals) |
| `failed: stalled`      | far from goal, net displacement stalled for `STALL_REPATH_SEC`, one replan spent |
| `failed: cancelled`    | explicit cancel or superseded by a newer order |

Near the goal the watchdog keys on *goal-distance progress* (orbiting a
crowd keeps displacement high while getting no closer); far from the goal it
keys on *net displacement* (so long detour arcs are never punished).
Turning in place is exempt.

## Numbers

| Constant | Value | Why |
|---|---|---|
| unit radius / speed | 11 / 110 | inherited feel baseline |
| turn rate | 10 rad/s | Dota2 0.6/0.03s × 0.5 visual scale |
| cell size / clearance | 8 / 12 | band = clearance + 8/side, keeps 56 px gaps open |
| `SEPARATION_ITERATIONS` | 6 | chain-length convergence for ~8-unit clusters |
| `ARRIVE_RADIUS` | 8 | point-click precision |
| `NEAR_GOAL_RADIUS` | 60 | "the crowd around my click" |
| stall timers | 0.7 s near / 1.5 s far | turn-in-place (~0.31 s max) never trips them |

## Boundaries kept

- `sim-nav-map` core stays policy-free: the engine consumes
  `plan_path` / `validate_movement_line` / `get_static_obstruction_shapes`
  and owns all movement policy itself.
- `Dota2LabMotionEngine` keeps no per-unit state (all on `Dota2LabUnit`), so
  the same engine drives the lab world and the `dota2-auto-battle` adapter.
- Group-move target fanout stays in `Dota2LabWorld` (command-layer concern).

## Known limits

- Go-around side is geometric (nearest side) with a fixed-handedness
  tiebreak only for perfect dead-center contacts.
- The separation solve is O(n²) per iteration. Fine for lab/adapter scale
  (≤ ~50 units); spatial hashing is the known upgrade path if that changes.
- An idle unit displaced by pushes does not walk back to its spot (Dota2
  behavior; also what keeps the solve stable).
- Planning is deferred and time-sliced, not threaded. Commands enqueue
  (~0.2 ms — synchronous group commands used to freeze the input frame for
  ~250 ms), units walk a straight-line placeholder, and the engine drains
  ONE query per tick (`PLAN_BUDGET_PER_TICK`).
- Measured GDScript JPS cost on the default map, using FRESH start cells per
  query (the realistic case — ray cache entries are keyed by start cell, so
  real play hits the cache rarely; a repeated-identical-query probe reads
  10× too fast): ~0.5 ms short/open, **~5-6 ms per cross-map query**,
  first query after a rebuild ~16 ms (includes the one-off passability
  bake). Two hot-path fixes got it there from 15-50 ms: an O(1) POINT-goal
  ray check replacing a per-cell scan on every cardinal probe, and the
  composed passability grid baked into a flat PackedInt32Array at cache
  reset so miss-path ray scans do local bit tests instead of three-layer
  cross-object composition per cell. The remaining cost is diagonal
  stepping's per-cell probe overhead in GDScript — the next meaningful cut
  is porting the pathfinding core to C++/GDExtension.
  `plans_applied` / `plans_waiting` in the step stats plus the HUD's
  `last plan` / rolling 5s peak attribute any spike at a glance.
- A worker-thread variant (core queue `start_worker`, and a WorkerThreadPool
  rewrite of it) was implemented and reverted — twice:
  - Godot 4.6 rc1: GDScript on spawned threads crashed unpredictably
    (dangling-callable "Nonexistent function" → access violations, both
    mid-run on world teardown and at engine exit — ObjectDB force-free does
    not wait for running threads).
  - Godot 4.7 stable retest: crashes mid-run were gone, but the pool task
    was STARVED — a batch the main thread computes in ~160 ms did not finish
    within 4+ seconds while the main thread kept ticking (probe:
    `WORKER_BATCH_STARTED` printed immediately, `is_task_completed` stayed
    false for 240+ ticks; high-priority made no difference). Concurrent
    GDScript execution contends on language-level global locks (allocation
    heavy JPS on the pool thread vs. the 60 Hz main loop), so threading buys
    negative throughput in pure GDScript.
  Verdict: threading the planner is off the table while it is GDScript.
  True background planning wants the pathfinding core ported to
  C++/GDExtension; the time-sliced queue is the main-thread ceiling until
  then. Do not re-attempt with the current stack.
