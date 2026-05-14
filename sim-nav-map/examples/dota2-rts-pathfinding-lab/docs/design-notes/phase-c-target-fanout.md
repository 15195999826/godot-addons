# Phase C Target Fanout Baseline Note

> Status: accepted Phase C baseline, 2026-05-14.

## Decision

Phase C adds **lab-local command-layer target fanout plus deterministic
command release scheduling** for multi-unit move commands in
`dota2-rts-pathfinding-lab`.

Fanout means one click target is expanded into deterministic per-unit targets
near that click before normal independent move orders are issued.

Command release scheduling means the lab starts those already-independent move
orders in a deterministic front-to-back order instead of starting all units on
the same tick.

This is intentionally not destination packing or formation movement:

- fanout: one click becomes `N` independent nearby targets;
- release scheduling: those `N` independent targets are started over a short,
  deterministic command-layer cadence;
- packing / formation: `N` units are planned as a group with shape, slots,
  shared pathing, arrival coordination, or dynamic reassignment.

## Why

Phase B proved the ticket lifecycle is clean and bounded, but default group
move still has poor feel:

- `default_group_move`: `IDLE 1`, `FAILED 7`;
- `narrow_gap_bounded_terminal`: `FAILED 2`;
- `mixed_static_dynamic_obstacle`: `FAILED 4`;
- all accepted failures are bounded, queue-drained, and diagnosed as hard-block
  terminal behavior.

The worst normal-play case is several units receiving the exact same click
target and then blocking each other at the destination. Fanout attacks that
command-level convergence before the motion FSM needs to recover from it.

Dota2-style play is still mostly single-unit or small-selection movement. The
lab's multi-unit command is a manual-testing convenience, not a reason to
upgrade this lab into group movement.

## Scope

Allowed:

- implement only under
  `addons/sim-nav-map/examples/dota2-rts-pathfinding-lab/`;
- apply only in multi-unit command entry points:
  `issue_move_all_mobile()` and `issue_move_ids()`;
- keep single-unit `issue_move(unit_id, goal)` unchanged;
- keep `Dota2LabMotionController` and the five-state FSM unchanged;
- keep `sim-nav-map` core policy-free;
- add diagnostics showing original target, assigned target, and fanout status.
- add diagnostics showing pending/released command-layer starts.

Forbidden:

- no UI work;
- no Layer 2 AI;
- no `MAX_RETRY`, speed, or radius tuning to hide behavior;
- no push, phasing, friendly walk-through, pair-yield, or give-way state;
- no group / cluster object;
- no formation roles, facing, front/back/flank slots, or arrival sync;
- no path sharing, cluster pathfinding, or full destination packing;
- no per-frame reservation table or dynamic slot reassignment.
- no path or target recomputation after the command is issued.

## First Implementation Shape

For a multi-unit command:

1. Gather the target mobile units.
2. Sort them by stable `unit.id`.
3. Generate a small deterministic ring / spiral of candidate targets around
   the clicked target.
4. Assign at most one target per unit.
5. Keep each target close to the click point, using a radius derived from unit
   radius / clearance rather than a large magic fallback distance.
6. If no bounded offset is acceptable for a unit, issue the original target for
   that unit and record `fanout_status=no_slot`.
7. Sort command releases deterministically by front-most unit along the command
   direction, with `unit.id` as the final tie-breaker.
8. Release one independent move order every bounded interval.
9. Call the existing independent move-order path for each released unit.

The assigned fanout target is only a command target. It does not reserve space
and does not guarantee that another unit cannot later block it.

First-pass defaults:

- fanout is always-on for `issue_move_ids()` when more than one mobile unit is
  commanded to the same goal, and for `issue_move_all_mobile()`;
- offset assignment is deterministic and based on sorted unit id, not current
  selection order;
- reachability checks should be light. Prefer rejecting obviously blocked
  candidates if the lab already has a cheap query, but do not add a new
  reservation or group-planner layer for Phase C;
- debug export should expose recent fanout assignments; persistent world state
  is only needed if tests need a stable field to assert.
- command release scheduling must be diagnostics-visible and must fully drain
  before a smoke can consider the command settled.

## Acceptance

Phase C is accepted because:

- `./tools/run_tests.ps1 dota2lab/smoke` passes;
- default group move improves materially from Phase B:
  at least `6/8` units reach `IDLE`, and at most `2/8` end `FAILED`;
- single-unit movement remains behaviorally unchanged;
- rapid target switching still drains queue state:
  `pending_count=0`, `result_count=0`, `result_tickets=[]`;
- narrow-gap and mixed-obstacle scenarios remain bounded and diagnosed even if
  they still end in accepted `FAILED`;
- fanout diagnostics show original target, assigned target, and status per
  affected unit;
- no files outside `dota2-rts-pathfinding-lab` change except test group
  registration if needed.

## Implementation Result

Target-only fanout improved the Phase B baseline but did not meet the full
acceptance target. Adding deterministic command release scheduling stayed within
the command-layer boundary and completed Phase C.

Final observed result:

- `./tools/run_tests.ps1 dota2lab/smoke`: `PASS 4 / FAIL 0 / TIMEOUT 0`;
- `default_group_move_fanout`: `IDLE 6`, `FAILED 2`;
- queue drains: `pending_count=0`, `result_count=0`, `result_tickets=[]`;
- diagnostics export `last_fanout_assignments` with original target, assigned
  target, status, candidate index, and spacing.
- diagnostics export `pending_command_releases` and `recent_command_releases`
  so delayed command starts are observable.

This meets the Phase C target while preserving the core boundary:

- no `Dota2LabMotionController` FSM changes;
- no `sim-nav-map` core changes;
- no push, phasing, yielding, reservation, formation, path sharing, or cluster
  planner;
- single-unit `issue_move(unit_id, goal)` remains immediate and unchanged.

## Future Boundary

Future work can build on this as the current Layer 1 baseline. If the lab needs
true group movement later, create a separate design note first; do not grow this
Phase C policy into destination packing, formation movement, reservation,
push/yield dynamics, path sharing, or cluster planning by small increments.
