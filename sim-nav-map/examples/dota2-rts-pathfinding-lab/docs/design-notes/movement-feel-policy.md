# Dota2 Movement Feel Policy

> Layer 1.1 contract. Created 2026-05-15.

This document turns the lab's "Dota2/LoL-style movement" goal into testable
rules. It is a movement policy contract for this example layer, not a
`sim-nav-map` core feature request.

## Purpose

Phase C accepted a playable manual baseline: explicit motion FSM, bounded hard
block failures, same-tick target fanout, short-detour subgoals, and diagnostics.
The next step is not Layer 2 AI control yet. First, the lab needs a contract
that says which movement outcomes are Dota2-style, which are known gaps, and
which are defects.

Layer 2 AI control stays frozen until the remaining prerequisites in this
contract are closed.

## Dota2-Style Motion Model

The lab models a strict individual-unit command feel:

- Units hard-block all units, including allies.
- Body block is gameplay, not a navigation bug.
- Commands are per-unit orders. Multi-unit commands are only a command-layer
  convenience that may fan out targets before issuing independent orders.
- Target switches are immediate: the newest command owns the unit.
- Blocked movement asks for a repath or a local short detour, then either
  resumes movement or terminates with an explicit failure reason.
- `sim-nav-map` core remains policy-free. Retry, stop, repath, failure, and
  command fanout policy live in this lab.

## Acceptance Criteria

These criteria are intentionally narrower than "make every jam feel good".
They define the baseline required before Layer 2 can safely drive the lab.

| ID | Criterion | Current status |
|---|---|---|
| A1 | Click-to-move latency: issuing a move command puts each target unit into `WAITING_LONG` on the command tick, with a pending long ticket and no hidden movement. | Covered by `smoke_dota2_lab_state_machine` and `smoke_dota2_lab_movement_feel_contract`. |
| A2 | Long-path delivery: a reachable solo command leaves `WAITING_LONG` and enters `FOLLOWING` within the queue latency bound. | Covered by `smoke_dota2_lab_movement_feel_contract`. |
| A3 | Target-switch immediacy: repeated commands cancel prior tickets, keep only the newest target, and drain stale results. | Covered by `smoke_dota2_lab_state_machine` and `smoke_dota2_lab_target_fanout`. |
| A4 | Solo no-false-failed: one mobile unit with no dynamic blocker and a reachable goal must not end in `FAILED`. | Covered by `smoke_dota2_lab_state_machine` and `smoke_dota2_lab_movement_feel_contract`. |
| A5 | Static blocker mid-path response: adding a static blocker ahead of an active mover must trigger a bounded replan and drain the queue; if the route is still reachable, the unit should reach `IDLE`, not `FAILED`. | Covered by `smoke_dota2_lab_movement_feel_contract`. |
| A6 | Same-target self-jam: many units ordered to the same clicked point may leave some units in bounded `FAILED` under strict hard-block rules, but all failures must be terminal, drained, stable, and explainable. | Accepted current Dota2 hard-block feel by `smoke_dota2_lab_target_fanout`; not a Layer 2 blocker. |
| A7 | Two-unit narrow-gap cross-pass: current Layer 1 accepts bounded `FAILED`; cooperative passage or yield is a known gap and requires a new design note before implementation. | Covered as bounded baseline by `smoke_dota2_lab_behavior_baseline`; not accepted as final feel. |

## Current Baseline Mapping

- `default_group_move_fanout` is accepted as current Dota2 hard-block feel:
  the player issues one group right-click, the command layer fans that clicked
  point into deterministic per-unit targets, three units reach `IDLE`, and the
  remaining five units end in bounded `FAILED` with `max_retry_exceeded` and a
  drained queue.
- `narrow_gap_bounded_terminal` is a known gap. It is allowed to end in bounded
  `FAILED`, but that does not prove final Dota2 feel.
- `mixed_static_dynamic_obstacle` is a known gap. It is allowed to end in
  bounded `FAILED`, but local yielding, destination packing, or push dynamics
  are not implied.

## Defect Boundary

Treat any of the following as a defect:

- A reachable solo command ends in `FAILED`.
- A command leaves stale pending tickets or result tickets after terminal settle.
- A unit remains in `WAITING_LONG`, `WAITING_SHORT`, or `FOLLOWING` beyond the
  bounded smoke budget.
- A `FAILED` unit has no explicit order failure reason.
- A target switch allows an old path result to own the unit after a newer
  command.
- A static obstacle edit leaves active movers using a stale path without replan.

## Explicit Non-Goals

These are rejected for this Dota2-style layer unless a future design note
explicitly reopens them:

- No push pressure or separation force.
- No friendly walk-through or phasing.
- No formation movement.
- No destination packing.
- No reservation grid or box reservation.
- No pair-aware yield such as "let lower-id unit pass".
- No cluster or group pathfinding.
- No `MAX_RETRY` increase as a first fix.
- No fallback path acceptance to hide queue or ticket bugs.
- No `sim-nav-map` core policy expansion for lab-specific movement behavior.

## Layer 2 Prerequisites

Layer 2 AI control should not start until:

- A1-A5 pass in `dota2lab/smoke`.
- A6 is accepted as current Dota2 hard-block feel, not a required improvement
  before automation.
- A7 stays marked as a known gap or has a separate Dota2-style design note.
- The active docs explain what Layer 2 means: automated command source, not a
  replacement for the motion controller.
