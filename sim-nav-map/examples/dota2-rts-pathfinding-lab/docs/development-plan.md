# Dota2 Lab Development Plan

> Active document. Updated 2026-05-14.

## Baseline

Current baseline:

- Parent repo commit: `2229aad`
- `addons` submodule commit: `7cc09df`
- Scene: `frontend/dota2_pathfinding_lab.tscn`
- Smoke entry: `./tools/run_tests.ps1 dota2lab/smoke`

What exists:

- Manual Layer 1 frontend with command/select, edit tools, debug HUD, and JSON
  export.
- Explicit five-state motion FSM: `IDLE`, `WAITING_LONG`, `FOLLOWING`,
  `WAITING_SHORT`, `FAILED`.
- DevAgent debug adapter for live capture, input, state dump, and export.
- Basic smoke coverage for state-machine shape and frontend operations.

Baseline verdict:

- This is a useful investigation baseline, not an approved gameplay baseline.
- Layer 2 AI control remains frozen.
- Current behavior can look bug-like under normal manual play, especially group
  movement, rapid target switching, and dynamic blockers.

## Evidence From Free Play

DevAgent session `codex-dota2-freeplay-20260513-151151` produced:

- Rapid target switching after an east move: `FAILED 5`, `FOLLOWING 3`,
  `IDLE 1`, with `long=85`, `short=61`, `UnitBlock=61`, and queue
  `result_count=7`.
- Reset plus move east plus two placed blockers: `FAILED 6`, `FOLLOWING 2`,
  `IDLE 3`, with `long=46`, `short=36`, `UnitBlock=36`.
- Several units failed with `max_retry_exceeded` before the manual blocker
  case became the main issue.

This means the next phase should not tune feel by increasing retry counts or
adding fallback paths first. The first objective is to make the current state
machine and ticket lifecycle correct and observable.

## Root Problems

### 1. Pending Ticket Lifecycle

`Dota2LabWorld.issue_move()` calls `unit.begin_move_order()` before
`motion.start_move_order()`.

`Dota2LabUnit.begin_move_order()` clears `pending_long_ticket` and
`pending_short_ticket`. By the time `Dota2LabMotionController._cancel_pending()`
runs, the old queue ticket ids are already lost, so old results can remain in
the queue.

Expected repair direction:

- Move pending-ticket cancellation ownership into `Dota2LabMotionController`.
- Keep `Dota2LabUnit` as state/order data, not the owner of queue cancellation.
- Add smoke that proves rapid target switching leaves no orphan pending or
  result tickets.

### 2. Group Movement Policy

The current contract says hard block, no push, no formation, and no destination
packing. With eight mobile units commanded to the same target, self-blocking is
expected to be harsh.

Expected repair direction:

- Do not silently add push, phasing, or fallback movement.
- After ticket lifecycle is correct, decide whether the lab remains a strict
  hard-block policy lab or grows a Layer 1.1 movement-feel policy.
- If better feel is required, design it explicitly before implementation.

## Next Development Route

### Phase A: Stabilize Current FSM

Goal: make the existing FSM internally correct before changing movement policy.

Status 2026-05-14:

- Implemented controller-owned ticket lifecycle for new move orders and manual
  cancellation.
- `Dota2LabUnit` no longer clears pending tickets directly; order finalizers
  assert that the controller already cancelled pending queue work.
- `Dota2LabPathfinderWrapper.diagnostics()` now exposes the full queue
  diagnostics used by smoke and DevAgent export.
- `smoke_dota2_lab_state_machine` includes rapid target-switch cleanup
  assertions for queue drain, ticket mutex, latest target, and cancellation
  counting.
- Verification: `./tools/run_tests.ps1 dota2lab/smoke` passes.
- Remaining follow-up: rerun the DevAgent/free-play rapid-switch scenario and
  compare failure counts against the 2026-05-13 baseline.

Tasks:

- Done: fix target-switch cancellation so old tickets cannot survive a fresh
  order.
- Done: surface full queue diagnostics through the lab export:
  `cancelled_count`, `stale_result_count`, `result_tickets`,
  `last_processed_requests`.
- Done: add smoke for rapid target switching:
  - issue many orders over consecutive ticks;
  - assert max one pending ticket per unit;
  - assert no orphan results after commands settle;
  - assert the active order id matches the latest target.

Acceptance:

- Done: `dota2lab/smoke` passes.
- Pending manual verification: DevAgent target-switch reproduction no longer
  leaves orphan result tickets.
- Pending manual verification: failures, if any, are tied to actual current
  orders, not old queue results.

### Phase B: Make Baseline Failures Explicit

Goal: separate acceptable hard-block terminal failure from real bugs.

Tasks:

- Add a default group-move smoke that records current behavior.
- Add narrow-gap bounded-terminal smoke.
- Add mixed static + dynamic obstacle smoke.
- Decide which failures are allowed baseline behavior and which are defects.

Acceptance:

- The docs and smoke agree on what `FAILED` means.
- No non-terminal state can persist beyond the bounded budget.
- The HUD/export gives enough data to explain each failed unit.

### Phase C: Decide Movement-Feel Policy

Only start this after Phase A and Phase B.

Two possible directions:

- **Strict policy lab:** keep hard block/no push/no destination packing. Improve
  diagnostics and deterministic failure only.
- **Playable-feel lab:** add a new explicit policy such as destination slots,
  local reservation, or pair-aware yield. This requires a new design note before
  code changes.

Do not mix these directions in one patch.

## Non-Goals For The Next Patch

- Do not start Layer 2 AI.
- Do not increase `MAX_RETRY` as the first fix.
- Do not add fallback path acceptance to hide queue/ticket issues.
- Do not add push pressure or phasing without a new design note.
- Do not expand `sim-nav-map` core policy surface for lab-specific behavior.
