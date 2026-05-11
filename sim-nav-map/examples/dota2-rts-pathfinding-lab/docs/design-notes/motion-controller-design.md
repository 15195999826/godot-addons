# Dota2 RTS Pathfinding Lab — Motion Controller Design

> **Status:** Design baseline. Settled via cross-review (Claude × Codex) on
> 2026-05-11. Future-Claude implements Layer 1 motion from this document.
>
> **Audience:** an implementer (Claude or developer) who has read the lab
> [README](../../README.md) and `sim-nav-map`
> [public-api.md](../../../../docs/public-api.md) and is about to write code.
> This doc fixes architecture trade-offs that should not be re-derived.

## 1. Purpose

The `0ad-rts-pathfinding-lab` motion controller is **1406 lines**. Most of
that complexity is *not* push pressure dynamics — push is bounded and could
be removed cleanly. The real complexity is an **implicit state machine
driven by magic numbers** (`ALTERNATE_PATH_TYPE_DELAY=3`,
`BACKUP_HACK_DELAY=10`, `KNOWN_IMPERFECT_PATH_RESET_COUNTDOWN=12`,
`MAX_FAILED_MOVEMENTS=35`, …). Each number is a latent state transition,
which is impossible to audit by reading the state of a single unit.

This lab fixes that by making **state explicit, transitions enumerable, and
the per-tick execution order fixed**. The LOC budget is **200–300 lines**.

## 2. Constraints (from [README](../../README.md), do not relitigate)

- **Hard block all units** including allies. No phasing, no friendly
  walk-through.
- **No push pressure.** Blocked → stop, then repath. No separation force.
- **Individual per-unit command model.** No formation, no cluster pathfinding,
  no destination packing.
- **`sim-nav-map` core is policy-free.** Retry, stop, repath, give-up logic
  live in this controller.
- **Layer 1 = manual frontend only.** Layer 2 (AI control) is frozen until
  the 5 Layer 1 OK criteria pass.

## 3. Architecture: Explicit State Machine

### 3.1 States (per unit)

| State | Meaning | Has `path`? | Pending ticket? |
|---|---|---|---|
| `IDLE` | No move order. | No | No |
| `WAITING_LONG` | Long path enqueued; waiting for result. | No (yet) | `pending_long_ticket > 0` |
| `FOLLOWING` | Has a path (long or short). Walking it. | Yes | No |
| `WAITING_SHORT` | Short detour enqueued; **current path frozen**, no movement this tick. | Yes (frozen) | `pending_short_ticket > 0` |
| `FAILED` | Retry budget exhausted. Emitted `MOVE_FAILED`. | No | No |

### 3.2 Transition Diagram

```text
                start_move_order             long success
       IDLE ─────────────────────→ WAITING_LONG ──────────→ FOLLOWING ──────→ (loop walking)
        ↑                              │                       │   ↑
        │ reached_goal                 │ long fail             │   │ short success
        │                              ↓                       │   │
        │                          FAILED ←─────────── WAITING_SHORT
        │                              ↑                       ↑
        │      retry_count > MAX_RETRY │                       │ blocked-by-unit
        │                              │                       │
        └──────────────────────────────┴───────────── (FOLLOWING blocked-by-static)
                                                              │
                                                              └→ WAITING_LONG (re-enqueue)

  At ANY state, `start_move_order(new_target)` cancels pendings and
  re-enters WAITING_LONG (target switch is universal).
```

### 3.3 Authoritative Transition Table

| Event | From state | Action | New state |
|---|---|---|---|
| `start_move_order(target)` | * | cancel pending tickets; `move_target = target`; `retry_count = 0`; enqueue long | `WAITING_LONG` |
| `long_result` status ∈ {`SUCCESS`, `DIRECT_GOAL`} | `WAITING_LONG` | `path = result.path` | `FOLLOWING` |
| `long_result` status ∈ {`UNREACHABLE`, `NO_PATH`, `INVALID_START`, `INVALID_QUERY`, **`CANONICALIZED`**, **`START_RECOVERED`**} | `WAITING_LONG` | emit `MOVE_FAILED("long_path_unreachable:<status>")` | `FAILED` |
| `step` reaches `move_target` (within `ARRIVE_EPSILON`) | `FOLLOWING` | clear `path`; emit `REACHED_GOAL` | `IDLE` |
| `step` blocked by **unit** (`UNIT_OBSTRUCTION_BLOCKED`) | `FOLLOWING` | enqueue short toward `move_target`; **freeze current `path`** | `WAITING_SHORT` |
| `step` blocked by **static** (`PASSABILITY_BLOCKED` / `STATIC_OBSTRUCTION_BLOCKED`) | `FOLLOWING` | enqueue long toward `move_target`; clear `path` | `WAITING_LONG` |
| `short_result.success` | `WAITING_SHORT` | `path = result.path` | `FOLLOWING` |
| `short_result.fail` | `WAITING_SHORT` | `retry_count += 1`; if `retry_count > MAX_RETRY` → emit `MOVE_FAILED` → `FAILED`; else enqueue long, clear `path` → `WAITING_LONG` | `FAILED` or `WAITING_LONG` |
| `cancel_move_order()` | * | cancel pending tickets; clear `path` | `IDLE` |

**No other transitions exist.** If implementation seems to need one, redesign
first; do not add a transient state silently.

## 4. Per-Tick Execution Order

```text
tick(delta):
  for each unit:
    apply_path_results(unit)      # collect long+short ticket results, drive transitions

  for each unit:
    if unit.state == FOLLOWING:
      step_unit(unit, delta)      # advance along path, detect block, may transition

  for each unit:
    emit_motion_updates(unit)     # REACHED_GOAL / MOVE_FAILED / OBSTRUCTED notifications

  queue.process_budget(PATH_BUDGET_PER_TICK)   # advance core's pending requests
```

**Order is fixed; do not interleave.** Specifically:

- `step_unit` must run **after** `apply_path_results` — otherwise newly
  delivered short paths sit idle for one tick.
- `process_budget` runs **last** — results land for the *next* tick's
  `apply_path_results`. This is the critical invariant in §5.

## 5. Critical Invariants (testable; encode in smoke)

These are the smoke-assertable rules that distinguish this lab from a
0AD-shaped implementation that would drift back to 1406 lines.

1. **NO_SAME_TICK_TAKEOVER.** After `enqueue_short()` in `step_unit`,
   the unit must NOT in the same tick: `take_short_path_result()`,
   modify `path`, or move. The state must transition to `WAITING_SHORT`
   and the function returns. This is the single invariant that prevents
   0AD's `_apply_pending_short_path_same_tick` complexity from re-emerging.
2. **NO_INTERLEAVE.** Each phase of §4 completes for **all** units before
   the next phase begins.
3. **PATH_FROZEN_WHEN_WAITING_SHORT.** `unit.path` is not mutated and not
   advanced while `state == WAITING_SHORT`. The unit stops in place.
4. **RETRY_RESET_ON_FRESH_ORDER.** `start_move_order` zeros `retry_count`.
   A new target gets a fresh retry budget.
5. **MAX_ONE_PENDING_TICKET.** At any moment, a unit has at most one
   pending ticket (`pending_long_ticket > 0` XOR `pending_short_ticket > 0`).
   Entering a new request state cancels the other ticket first.
6. **STATE_REFLECTS_TICKETS.** `WAITING_LONG ⇔ pending_long_ticket > 0`.
   `WAITING_SHORT ⇔ pending_short_ticket > 0`. Tested at end of every tick.
7. **TERMINAL_FAILED_IS_STICKY.** From `FAILED`, the only transition is
   `start_move_order` (which exits to `WAITING_LONG`). No automatic retry.

## 6. Path Request Policy

### 6.1 Queue throttle

Use `SimNavPathRequestQueue.process_budget(N)`, **not** `start_worker(0)`.
`start_worker(0)` drains all pending requests in one batch, which masks
queue pressure and removes any backpressure signal.

```gdscript
const PATH_BUDGET_PER_TICK := 4   # tunable; start at 4 for 10–40 unit density
```

If diagnostics show `pending_count_peak` consistently > 16 or `bounded_ticks_to_terminal`
gets near the smoke budget ceiling, raise to 8.

### 6.2 Diagnostics export (mandatory)

The controller exposes (read-only) for smoke / debug overlay:

```gdscript
func diagnostics() -> Dictionary:
    return {
        "pending_count_peak": ...,           # max simultaneous pending tickets seen
        "pending_count_not_monotonic": ...,  # bool; true if pending count grew without bound for > N ticks
        "processed_per_tick": ...,           # rolling average from queue.get_diagnostics()
        "state_counts": {...},               # {IDLE: n, WAITING_LONG: n, ..., FAILED: n}
        "retry_count_max": ...,
    }
```

`pending_count_not_monotonic` is the canary. If it ever flips `true`, the
controller is producing requests faster than the queue can drain. Treat as
test failure.

### 6.3 Short detour completion → re-enqueue long

When a unit successfully consumes a short detour path and reaches the end
of `path` without `REACHED_GOAL` (i.e. short path was a *detour*, not the
final path), it implicitly transitions through `FOLLOWING` (path empty,
not at goal) → handled as `WAITING_LONG` start. **No `long_path_resume_cursor`
is maintained.** Each detour completion costs one fresh long path request.

Cost analysis: 40 units mid-detour = 40 long requests. With
`PATH_BUDGET_PER_TICK = 4`, that's 10 ticks of queue work — visually
acceptable at lab density, and the diagnostics flag
(`pending_count_not_monotonic`) catches the pathological case.

## 7. Failure Model

```gdscript
const MAX_RETRY := 5   # recovery failures, NOT ticks
```

`retry_count` increments **only on `short_result.fail`**. It does not
increment on `step` blocks (the controller emits a fresh short request
and waits for the *result*).

**Smoke assertions about failure are bounded in TICKS using a budget
formula**, not literal numbers:

```gdscript
const QUEUE_LATENCY_BOUND := 4   # ticks; conservative upper bound for one short result
const FAILURE_TICK_BUDGET := MAX_RETRY * QUEUE_LATENCY_BOUND  # = 20 ticks
```

A smoke that pins a unit against a hard block and expects `FAILED` must
allow up to `FAILURE_TICK_BUDGET` ticks before asserting.

## 8. Layer 1 OK Standards → Smoke Mapping

Each [README](../../README.md) §"Layer 1 Approval Criteria" entry maps to
one or more smoke scenes under `tests/smoke/`.

| OK # | README claim | Smoke name (planned) | Key assertion |
|---|---|---|---|
| 1 | No deadlock | `smoke_no_deadlock_long_run.tscn` | After N=2000 ticks with random move orders, no unit stays in `WAITING_SHORT` for > `FAILURE_TICK_BUDGET` consecutive ticks. |
| 2 | Bumped → repath | `smoke_bumped_then_repath.tscn` | Place 2 units; force collision; assert blocker triggers `WAITING_SHORT` transition; assert `path` updates within `QUEUE_LATENCY_BOUND` ticks. |
| 3 | Target-switch smoothness | `smoke_target_switch_no_thrash.tscn` | Issue 10 move orders in 10 ticks to different targets; assert each cancels the previous (no orphan tickets, `pending_count_peak ≤ 1` per unit). |
| 4 | Narrow-gap behavior | `smoke_narrow_gap_deterministic.tscn` | 2 mobile units channeled into a 1-cell gap. Assert: **(a)** within `FAILURE_TICK_BUDGET`, both units reach `IDLE` (reached goal) OR `FAILED` (clean give-up); **(b)** no oscillation: position variance over last 10 ticks < `ARRIVE_EPSILON`; **(c)** no `pending_count_not_monotonic`. |
| 5 | Mixed static + dynamic | `smoke_mixed_static_dynamic.tscn` | Map with one static obstacle and 4 mobile units near it. Assert all reach `IDLE` within bounded ticks, no infinite repath loops (a unit's `WAITING_LONG` count over the run < 3). |

**Smoke template:** every smoke calls `controller.diagnostics()` at end and
asserts no `pending_count_not_monotonic`, no unit stuck in non-terminal
state past budget.

## 9. Out of Scope (rejected at design time)

These are not "future work" — they are **rejected** for Layer 1. Adding any
of them requires a fresh design note that justifies the LOC cost.

- **Push pressure / separation force / soft block.** No.
- **Long-path resume cursor.** Short detour completion re-enqueues long.
- **Pair-aware yield / "let lower-id unit pass".** May be revisited in
  Layer 1.1 if manual play surfaces unacceptable narrow-gap stalls.
  Acceptable Layer 1 result: both units `FAILED`.
- **Same-tick short takeover.** Explicit invariant 5.1.
- **Alternate-pathfinder rotation, backup hack, known-imperfect-path
  countdown.** All 0AD magic-number-driven implicit transitions. If a
  similar effect seems needed, redesign instead of adding a counter.
- **Acceleration, facing rotation, turning radius.** Constant speed,
  immediate direction change.
- **Hierarchical reachability pre-check** before enqueue long. Trust the
  long pathfinder's `unreachable` / `no_path` result to drive `FAILED`.
- **`STATUS_CANONICALIZED` / `STATUS_START_RECOVERED` fallback handling.**
  The long pathfinder returns these when the original goal/start is
  unreachable but a nearby reachable substitute exists. dota2 lab treats
  both as terminal `FAILED` rather than walking to the substitute — a
  fallback path would loop indefinitely (e.g. caged unit canonicalizes
  goal to an in-cage point each tick) and contradicts the "no fallback,
  no graceful degradation" principle of this lab. Only `STATUS_SUCCESS`
  and `STATUS_DIRECT_GOAL` are accepted as `FOLLOWING` transitions.

## 10. Files & API Touchpoints

Files (this lab):

- `logic/dota2_lab_motion_controller.gd` — this design's `class_name
  Dota2LabMotionController extends RefCounted`. Target ≤ 300 LOC.
- `logic/dota2_lab_unit.gd` — `class_name Dota2LabUnit`. Holds the 6
  motion fields in §3.
- `logic/dota2_lab_pathfinder_wrapper.gd` — thin adapter over
  `SimNavPathfinderFacade` + `SimNavPathRequestQueue`. Owns the
  per-tick `process_budget` call.
- `logic/dota2_lab_move_order.gd` — DTO: `target: Vector2`. (Layer 2
  may extend.)
- `logic/dota2_lab_world.gd` — owns the unit list and the
  per-tick loop ordering of §4.

Public API touchpoints (from
[public-api.md](../../../../docs/public-api.md)):

- `SimNavPathRequestQueue.enqueue_long_path(query) -> ticket`
- `SimNavPathRequestQueue.enqueue_short_path(request) -> ticket`
- `SimNavPathRequestQueue.cancel(ticket)`
- `SimNavPathRequestQueue.take_long_path_result(ticket)` / `take_short_path_result(ticket)`
- `SimNavPathRequestQueue.process_budget(N)`
- `SimNavPathRequestQueue.get_diagnostics()` (for `processed_per_tick`)
- `SimNavPathfinderFacade.validate_movement_line(...)` — single source of
  truth for step blocking. Use `SimNavMovementLineResult.failure_reason`
  to discriminate static vs unit.
- `SimNavMovementLineResult.FAILURE_PASSABILITY_BLOCKED` /
  `FAILURE_STATIC_OBSTRUCTION_BLOCKED` → enqueue long
- `SimNavMovementLineResult.FAILURE_UNIT_OBSTRUCTION_BLOCKED` → enqueue short

## 11. References

- Lab README: [../../README.md](../../README.md)
- `sim-nav-map` public API: [../../../../docs/public-api.md](../../../../docs/public-api.md)
- 0AD lab motion controller (negative example, 1406 lines):
  `addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_motion_controller.gd`
- Cross-review settling this design (2026-05-11): conversation archived
  by user.
