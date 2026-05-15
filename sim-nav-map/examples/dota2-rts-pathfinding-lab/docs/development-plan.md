# Dota2 Lab Development Plan

> Active document. Updated 2026-05-15.

## Baseline

Current baseline:

- Status: Phase C accepted baseline, 2026-05-14.
- Baseline reference: the `addons` submodule commit containing this file,
  tracked by the parent repo commit that points at it.
- Scene: `frontend/dota2_pathfinding_lab.tscn`
- Smoke entry: `./tools/run_tests.ps1 dota2lab/smoke`
- Smoke result: `PASS 5 / FAIL 0 / TIMEOUT 0`

What exists:

- Manual Layer 1 frontend with command/select, edit tools, debug HUD, and JSON
  export.
- Explicit five-state motion FSM: `IDLE`, `WAITING_LONG`, `FOLLOWING`,
  `WAITING_SHORT`, `FAILED`.
- Controller-owned ticket lifecycle and queue diagnostics for stale/cancelled
  path requests.
- Same-tick command-layer target fanout for multi-unit move commands.
- Unit-blocked movement uses a local short-detour subgoal instead of sending
  the far final click target to short path.
- Debug HUD and export fields distinguish long vs short path source and last
  short-path result.
- DevAgent debug adapter for live capture, input, state dump, and export.
- Smoke coverage for state-machine shape, frontend operations, behavior
  baseline, Phase C target fanout, and Layer 1.1 movement-feel contract.

Baseline verdict:

- This is the accepted Layer 1 baseline for continuing Dota2 lab work.
- Layer 2 AI control remains frozen.
- Single-unit movement remains strict hard-block behavior.
- Single-unit short detours are now observable and should not fail merely
  because the final click target is outside the short search range.
- Multi-unit movement is still independent per-unit movement. Target fanout is
  a command convenience, not formation, destination packing, or group pathing.
- Remaining bounded `FAILED` outcomes in narrow-gap and mixed-obstacle cases
  are accepted diagnostics, not a reason to tune retry counts or core policy.
- The Layer 1.1 movement-feel contract is now documented at
  `docs/design-notes/movement-feel-policy.md`; Layer 2 AI control remains
  frozen until the remaining prerequisites in that contract are closed.

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
- DevAgent/free-play rapid-switch verification:
  `codex-dota2-phaseb-20260514-153930`.
  - Final export:
    `C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/Inkmon/dota2_rts_pathfinding_lab_logs/codex_phaseb_devagent_final_20260514_153930.json`
  - Final metrics at tick `2418`: `FAILED 7`, `IDLE 2`,
    `FOLLOWING 0`, `WAITING_LONG 0`, `WAITING_SHORT 0`.
  - Queue diagnostics: `pending_count=0`, `result_count=0`,
    `result_tickets=[]`, `cancelled_count=12`, `stale_result_count=12`.
  - Verdict: no orphan pending or result tickets reproduced. Stale results were
    discarded after cancellation; remaining failures are tied to current
    hard-block movement orders.

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
- Done: DevAgent target-switch reproduction no longer leaves orphan result
  tickets.
- Done: failures are tied to actual current orders, not old queue results.

### Phase B: Make Baseline Failures Explicit

Goal: separate acceptable hard-block terminal failure from real bugs.

Status 2026-05-14:

- Added `smoke_dota2_lab_behavior_baseline` to `dota2lab/smoke`.
- The smoke covers:
  - default group move baseline;
  - narrow-gap bounded terminal behavior;
  - mixed static + dynamic obstacle behavior.
- Each `FAILED` unit is classified by `last_order.failure_reason`.
  `max_retry_exceeded` is accepted only when the scenario also records hard
  block evidence and reaches a drained terminal state.
- Verification: `./tools/run_tests.ps1 dota2lab/smoke` passes with
  `PASS 3 / FAIL 0 / TIMEOUT 0`.

Tasks:

- Done: add a default group-move smoke that records current behavior.
- Done: add narrow-gap bounded-terminal smoke.
- Done: add mixed static + dynamic obstacle smoke.
- Done: decide which failures are allowed baseline behavior and which are
  defects.

Acceptance:

- Done: the docs and smoke agree on what `FAILED` means.
- Done: no non-terminal state can persist beyond the bounded budget.
- Done: the HUD/export gives enough data to explain each failed unit.

#### Phase B Accepted Baseline Failures

The following are accepted only as the current baseline, not as final gameplay
feel:

- `default_group_move`: settled in 572 ticks; `IDLE 1`, `FAILED 7`;
  all failed units have `failure_reason=max_retry_exceeded`;
  `pending_count=0`, `result_count=0`, `blocked_by_unit_count=47`.
- `narrow_gap_bounded_terminal`: settled in 89 ticks; `FAILED 2`;
  both failures have `failure_reason=max_retry_exceeded`;
  `pending_count=0`, `result_count=0`, `blocked_by_unit_count=12`.
- `mixed_static_dynamic_obstacle`: settled in 115 ticks; `FAILED 4`;
  all failures have `failure_reason=max_retry_exceeded`;
  `pending_count=0`, `result_count=0`, `blocked_by_unit_count=24`, static
  obstacle fixture count `2`.

Interpretation:

- These failures are allowed hard-block terminal behavior because they are
  bounded, terminal, queue-drained, stable, and have explicit order failure
  reasons.
- They are still poor-feel outcomes under normal play. Improving them belongs
  to Phase C policy work, not this baseline patch.

#### Phase B Defect Boundary

Treat any of the following as a defect:

- a unit remains in `WAITING_LONG`, `WAITING_SHORT`, or `FOLLOWING` beyond the
  bounded smoke budget;
- `pending_count` or `result_count` does not drain after all target units are
  terminal;
- a `FAILED` unit has an empty or unexpected `last_order.failure_reason`;
- a `FAILED` unit has an allowed reason but no hard-block evidence;
- rapid target switching leaves live orphan `result_tickets` or pending tickets.

No such defect is present in the current Phase B smoke or DevAgent evidence.

### Phase C: Decide Movement-Feel Policy

Only start this after Phase A and Phase B.

Status 2026-05-14:

- Implemented command-layer target fanout for multi-unit commands:
  `issue_move_all_mobile()` and `issue_move_ids()`.
- All selected units receive independent move orders on the command tick.
- Single-unit `issue_move(unit_id, goal)` remains immediate and unchanged.
- Added diagnostics for:
  - `last_fanout_assignments`;
  - `recent_fanout_assignments`.
- Corrected short-path request semantics after manual testing:
  - unit-blocked short requests target a local subgoal inside short range;
  - repeated blocked recovery attempts remain bounded by `max_retry_exceeded`;
  - debug HUD shows long paths in green, short paths in cyan, and the last
    short subgoal as a cyan ring.
- Added `smoke_dota2_lab_target_fanout` to `dota2lab/smoke`.
- Verification: `./tools/run_tests.ps1 dota2lab/smoke` passes with
  `PASS 4 / FAIL 0 / TIMEOUT 0`.
- DevAgent real-input verification:
  `codex-dota2-shortfix-20260514-174112` selected `blue_6`, issued a real
  right-click move to `(73, 472)`, and observed
  `kind=short`, `status=success`, `path_size=2`, with no stderr output.

Phase C accepted result:

- `default_group_move_fanout`: same-tick target-only fanout settles with
  `IDLE 3`, `FAILED 5` in the default hard-block layout.
- Queue diagnostics at settle: `pending_count=0`, `result_count=0`,
  `result_tickets=[]`.
- `narrow_gap_bounded_terminal` and `mixed_static_dynamic_obstacle` remain
  bounded hard-block terminal scenarios.
- No Layer 2 AI, `MAX_RETRY` tuning, push, phasing, formation, reservation,
  cluster pathfinding, or `sim-nav-map` core policy changes were introduced.
- UI work is limited to debug observability for long/short path source; it does
  not change command semantics.
- A delayed command-release experiment could reach `IDLE 6`, `FAILED 2`, but
  it made units visibly move one by one and is not part of the accepted
  baseline.

Decision:

- Use a narrow command-layer movement-feel policy: same-tick target fanout.
- Keep the strict Dota2 motion layer: hard block, no push, no destination
  packing, no reservation, no pair-aware yield.
- Do not mix this with SC2-style group movement or 0AD-style push dynamics.

Phase C decision items now visible from Phase B:

- Default group move currently leaves most units in accepted terminal failure
  under strict hard-block policy.
- Narrow gap currently resolves by bounded `FAILED`, not cooperative passage.
- Mixed static + dynamic blockers currently resolve by bounded `FAILED`, not
  local yielding or destination packing.

### Layer 1.1: Define Dota2 Movement-Feel Contract

Status 2026-05-15:

- Added `docs/design-notes/movement-feel-policy.md` as the Dota2-style movement
  contract for this lab.
- The contract keeps policy in the example layer, not in `sim-nav-map` core.
- Added `smoke_dota2_lab_movement_feel_contract` to `dota2lab/smoke`.
- Verification: `./tools/run_tests.ps1 dota2lab/smoke` passes with
  `PASS 5 / FAIL 0 / TIMEOUT 0`.

Acceptance:

- Done: click-to-move command latency is explicit and smoke-covered.
- Done: reachable solo movement must not false-fail.
- Done: mid-path static blocker edits must trigger bounded replan and queue
  drain.
- Done: Layer 2 AI is documented as an automated command source, not a
  replacement for the motion controller.

Open decisions before Layer 2:

- Decide whether Phase C same-target self-jam is accepted final Dota2 feel or a
  future improvement target.
- Keep two-unit narrow-gap cooperative passage as a known gap unless a new
  Dota2-style design note reopens it.

## Non-Goals For The Next Patch

- Do not start Layer 2 AI.
- Do not increase `MAX_RETRY` as the first fix.
- Do not add fallback path acceptance to hide queue/ticket issues.
- Do not add push pressure or phasing without a new design note.
- Do not expand `sim-nav-map` core policy surface for lab-specific behavior.
