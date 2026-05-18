# Layer 2 AI Control Plan

> Design note. Created 2026-05-15.
>
> First implementation status: a deterministic command-source smoke driver now
> exists. This document still defines the boundary for future Layer 2 work.

## Purpose

Layer 2 adds scripted command sources for the Dota2 RTS pathfinding lab. It is
not a new movement system, not a replacement for `Dota2LabMotionController`,
and not a new policy surface in `sim-nav-map` core.

The practical goal is simple: let tests and lab scripts issue the same kinds of
move commands that a player would issue by right-clicking, without requiring a
human to drive every scenario manually.

## Current Baseline

Layer 2 starts from the Layer 1.1 movement-feel contract:

- A1-A5 are expected to pass in `dota2lab/smoke`.
- A6 same-target self-jam is accepted as current Dota2 hard-block feel. A group
  right-click to one target can settle as `IDLE 3`, `FAILED 5`, with
  `failure_reason=max_retry_exceeded` and a drained queue.
- A7 narrow-gap cooperative passage remains a known gap. Layer 2 must not
  silently fix it with yield, push, phasing, reservation, or destination
  packing.

## Actual Layer 2 Scenarios

Layer 2 should cover command streams that are painful to drive by hand:

- Lane walk: automatically send a group of units through lane or checkpoint
  targets, using one command per waypoint.
- Target switch: repeatedly retarget one unit or a selected group to prove that
  the newest command owns the unit and stale path results drain.
- Chase and retreat: simulate a chase command toward an enemy-side point, then
  switch to a retreat target or cancel selected units.
- Pressure generation: produce deterministic batches of move commands across
  the map so smoke tests can stress queue drain and terminal settle without
  manual right-clicks.

These are all command-flow scenarios. They are not formation movement, group
pathfinding, cooperative passage, or steering fixes.

## Architecture Choice

Chosen shape: a command-source script.

The script may choose unit ids, choose goals, decide timing, and call the public
world command API. It must leave movement execution to the existing world and
motion controller.

The first implementation is a small deterministic driver used by smoke tests
and by a visible frontend demo scene. It does not add a new global system, new
motion controller, or new `sim-nav-map` API.

Rejected shapes:

- A second movement FSM.
- Direct calls into `Dota2LabMotionController`.
- Direct mutation of unit `position`, `state`, `path`, retry counters, pending
  tickets, or path result fields.
- A new queue or event bus for movement commands.
- A planner that packs destinations, reserves slots, assigns formation offsets,
  performs pair-aware yield, or clusters units.
- Any retry-policy change such as raising `MAX_RETRY` to hide hard-block
  failures.

## Allowed Entry Points

All movement side effects must go through `Dota2LabWorld`:

- `issue_move(unit_id, goal)`
- `issue_move_all_mobile(goal)`
- `issue_move_ids(unit_ids, goal)`
- `cancel_move(unit_id)`

Layer 2 may read world state or metrics to decide what command to issue next,
but reads must remain observational. If a future script needs richer state, add
a read-only snapshot/helper before adding write access.

## Command Timing

The automatic layer should emit commands at a single deterministic point in the
frame, before `world.step(delta)` consumes path results and moves units. This
keeps automated commands equivalent to frontend input arriving before the next
simulation tick.

Do not emit commands from inside `Dota2LabMotionController.apply_path_results`,
`step_unit`, pathfinder callbacks, or queue processing. That would interleave
Layer 2 with the motion FSM and make target-switch ownership harder to audit.

## Acceptance Criteria

Layer 2 is acceptable only if all of these remain true:

- The automatic layer only produces commands. It does not change motion state.
- Every move command goes through `issue_move()`, `issue_move_all_mobile()`, or
  `issue_move_ids()`.
- Every cancel command goes through `cancel_move()`.
- Target switching keeps only the newest target authoritative for each unit.
- After a command stream finishes and the bounded settle window completes, the
  path queue must drain: `pending_count=0`, `result_count=0`, and no live
  `result_tickets`.
- No unit may remain in `WAITING_LONG`, `WAITING_SHORT`, or `FOLLOWING` beyond
  the scenario's bounded settle budget.
- Group move under current Dota2 hard-block rules may end with bounded
  `FAILED` units when failures are terminal, stable, queue-drained, and
  explained by allowed reasons such as `max_retry_exceeded`.
- Narrow-gap cooperative passage remains a known gap for the first Layer 2
  version. A Layer 2 smoke may record bounded terminal behavior there, but it
  must not claim that cooperative passage is fixed.
- The implementation does not add push pressure, friendly walk-through,
  phasing, formation movement, destination packing, reservation, pair-aware
  yield, cluster pathfinding, or `sim-nav-map` core policy.

## First Smoke Shape

The first focused smoke scene is
`tests/smoke/smoke_dota2_lab_ai_command_source.tscn`.

The visible demo scene is `frontend/dota2_ai_command_demo.tscn`. It reuses the
manual lab renderer with `auto_command_demo=true` and a slower command schedule
so the sequence can be watched in the editor.

It verifies:

- one group lane move;
- one rapid target-switch sequence;
- one chase-to-retreat command switch;
- one cancel command;
- queue drain after the script stops issuing commands;
- latest-target ownership for commanded units.
- frontend boot coverage for the visible demo scene.

This smoke validates command automation, not improved movement feel.

Future command-source smoke scenes should follow the same shape:

1. Create a default `Dota2LabWorld`.
2. Drive a deterministic command script with at least:
   - one group lane move;
   - one rapid target-switch sequence;
   - one chase-to-retreat command switch.
3. Stop issuing commands.
4. Step the world until every commanded unit is terminal or the bounded budget
   expires.
5. Assert queue drain, latest-target ownership, and no non-terminal stuck
   states.

## Non-Goals For The First Implementation

- No UI or debug panel work is required.
- No new pathfinding primitive is required.
- No changes to `Dota2LabMotionController` are expected unless a smoke exposes
  a pre-existing command ownership bug.
- No attempt to improve A6 or A7 behavior belongs in the first Layer 2 patch.
- No parent `sim-nav-map` core contract changes belong in this layer.

## References

- Active route: [../development-plan.md](../development-plan.md)
- Movement-feel contract: [movement-feel-policy.md](movement-feel-policy.md)
- Motion controller design: [motion-controller-design.md](motion-controller-design.md)
