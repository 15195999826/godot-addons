# Dota2 Movement Feel Policy (v2)

> Layer 1.1 contract, **v2 (2026-07-02)**. Replaces the v1 hard-block-only
> contract after the user verdict: v1's accepted baseline ("group move ends
> with most units FAILED", "narrow-gap cross ends FAILED") was itself the
> poor feel. v2 defines the contract forward from how Dota 2 actually moves
> units, instead of backward from implementation limitations.
> v1 history: git. Decision record: repo `docs/future/simnav-examples-disposition-proposal.md`.

## The Dota2 Motion Model (what we are reproducing)

Observed Dota 2 behavior, in order of feel importance:

1. **A moving unit never parks against a blocker.** When its straight step is
   obstructed by another unit it *slides* tangentially around the blocker and
   keeps making progress (Valve's pathfinder does continuous-space "wall
   tracing" — see `docs/references/dota2-style-source/README.md`).
2. **Two moving units brush past each other.** Passing contact between movers
   barely disturbs either path; movement collision is effectively relaxed.
3. **Idle units are real obstacles.** A parked unit blocks; the mover routes
   or slides around it, it does not phase through.
4. **A move order never gives up.** A unit walled in by other units waits and
   resumes the moment a gap opens. The only terminal outcome for a move order
   is *arrival* or *the goal being statically unreachable* (or a newer order).
5. **Click a crowded spot and units ring around it.** Ordering many units to
   one point ends with all of them IDLE in a cluster around the point — not
   with most of them giving up.
6. **Facing gates movement.** Units turn in place until the target direction
   is inside the `11.5°` action cone, then translate while still turning
   (unchanged from v1).

## Mechanisms (lab policy layer only; `sim-nav-map` core unchanged)

| # | Mechanism | Dota2 behavior it implements |
|---|---|---|
| M1 | **Micro-detour waypoint**: a `FOLLOWING` unit blocked by a *stationary* unit inserts a validated detour waypoint beside the blocker and walks to it through the NORMAL facing/step pipeline (turn, then arc around) — never a sideways displacement, which reads as ice-drift and fights the turn gate into pirouettes. A blocked waypoint sitting inside the blocker's body is popped first (0 A.D. PostMove rule) — it is physically unreachable and orbiting it helps nobody. Only when no detour side validates does the unit escalate to a short-path request. | 1, 3 |
| M2 | **Two collision tiers**: units WITH an active move order phase past each other entirely — geometry proves a frontal meeting cannot route around a same-size blocker at any clearance a corridor allows (the approach chord is always shorter than both endpoints), which is why 0 A.D. resolves crossings with push and Dota 2 lets crossing creep waves press straight through. Units WITHOUT an order (parked, arrived, failed) are solid at the mover's clearance relaxed by ½ raster cell (0 A.D. `relaxClearanceForUnits`). Order-based, not state-based: a crowd squeezing a chokepoint cycles through WAITING/HOLDING and treating those as solid turns a doorway into a mutual-blocking carousel. | 2 |
| M3 | **Crowded arrive**: when escalation finds the goal already occupied and the unit is within `ARRIVE_EPSILON + 2 × radius` of `move_target`, the order completes (`REACHED_GOAL`); once the recovery budget is spent the acceptance ring widens to `4 × radius` (second ring), so a crowd ordered to one point settles as concentric rings. | 5 |
| M4 | **HOLDING state**: when the recovery budget is exhausted, the unit enters `HOLDING` — order retained, position held, one long-path retry every `HOLD_RETRY_INTERVAL_TICKS`. It leaves via a successful path (gap opened), crowded arrive, a fresh order, or `FAILED` if a retry proves the goal statically unreachable. Replaces v1's `max_retry_exceeded → FAILED` parking. | 4 |

All unit-vs-unit blocking runs against LIVE unit positions in the motion
controller (the nav map's per-tick dynamic snapshot goes stale as soon as one
unit moves — stale data let same-tick pairs converge into overlap). The
movement-line filter carries statics/raster only; detour legs additionally
skip the raster DDA (their endpoints are geometry-validated at insertion and
may legally sit inside the raster band — the core impassable-escape rule
walks the unit back out) and ignore the unit being rounded (a walk-around
necessarily hugs it).

`FAILED` remains, but is reachable **only** from a long-path result whose
status is not `SUCCESS`/`DIRECT_GOAL` (goal statically unreachable, caged
start, etc.). It is never entered because other units are in the way.

## State Machine v2

States: `IDLE`, `WAITING_LONG`, `FOLLOWING`, `WAITING_SHORT`, **`HOLDING`**,
`FAILED`. v1 transitions carry over with these changes:

| Event | From | Action | New state |
|---|---|---|---|
| step unit-blocked, relax-revalidation passes | `FOLLOWING` | walk the step as planned | `FOLLOWING` |
| step unit-blocked, tangential slide validates | `FOLLOWING` | move along the tangent (no waypoint consumed) | `FOLLOWING` |
| step unit-blocked, slide fails, crowd-arrive check passes | `FOLLOWING` | complete order | `IDLE` |
| step unit-blocked, slide fails, retry budget left | `FOLLOWING` | enqueue short (v1 path) | `WAITING_SHORT` |
| short fails / block with `retry_count > MAX_RETRY`, crowd-arrive passes | `WAITING_SHORT`/`FOLLOWING` | complete order | `IDLE` |
| short fails / block with `retry_count > MAX_RETRY`, crowd-arrive fails | `WAITING_SHORT`/`FOLLOWING` | hold position, start retry countdown | `HOLDING` |
| countdown expires | `HOLDING` | enqueue long | `WAITING_LONG` |
| crowd-arrive passes during hold | `HOLDING` | complete order | `IDLE` |
| `start_move_order` / `cancel_move_order` | `HOLDING` | as from any state | `WAITING_LONG` / `IDLE` |
| long result not SUCCESS/DIRECT_GOAL | `WAITING_LONG` | emit `MOVE_FAILED` | `FAILED` (unchanged, now the only FAILED entry) |

`retry_count` is **not** cleared on entering `HOLDING`: a re-opened path that
immediately jams again drops back to `HOLDING` after one failed recovery
instead of re-running the full escalation storm. A fresh order still resets it.

## Invariants (carried from v1 + new)

v1 invariants 1–6 (NO_SAME_TICK_TAKEOVER, NO_INTERLEAVE,
PATH_FROZEN_WHEN_WAITING_SHORT, RETRY_RESET_ON_FRESH_ORDER,
MAX_ONE_PENDING_TICKET, STATE_REFLECTS_TICKETS) are unchanged. v1 invariant 7
(TERMINAL_FAILED_IS_STICKY) still holds for `FAILED`. New:

8. **SLIDE_IS_VALIDATED.** Every slide step passes the same movement-line
   validation as a normal step (with M2 relax). Slides never create overlap
   beyond the relax allowance.
9. **BOUNDED_HOLDING_ACTIVITY.** A `HOLDING` unit issues at most one path
   request per `HOLD_RETRY_INTERVAL_TICKS`. A walled-in unit is quiet, not a
   request storm.
10. **NEVER_FAILED_BY_UNITS.** No transition into `FAILED` originates from a
    unit obstruction. Grep-level check: `max_retry_exceeded` no longer exists
    as a failure reason.

## Acceptance Criteria v2

| ID | Criterion | Change vs v1 |
|---|---|---|
| A1 | Click-to-move latency: command tick puts the unit in `WAITING_LONG` with a pending long ticket. | unchanged |
| A2 | Long-path delivery: reachable solo command reaches `FOLLOWING` within queue latency. | unchanged |
| A3 | Target-switch immediacy: newest command owns the unit, stale results drain. | unchanged |
| A4 | Solo no-false-failed: reachable solo goal never ends `FAILED`. | unchanged |
| A5 | Static blocker mid-path: bounded replan, queue drains, still-reachable goal reaches `IDLE`. | unchanged |
| A6 | **Same-target group move completes.** All units end `IDLE`, ringed around the click point (crowded arrive). No unit ends `FAILED`. | v1 accepted `IDLE 3 / FAILED 5` |
| A7 | **Two-unit narrow-gap cross-pass succeeds.** Opposing units slide past each other inside the gap and both reach `IDLE`. | v1 accepted bounded `FAILED` |
| A8 | Facing gate: rotate in place until the action cone, then translate while turning. | unchanged |
| A9 | **Walled-in unit holds, then resumes.** A unit boxed in by idle units enters `HOLDING` (bounded request rate); removing a blocker lets it reach the goal without a new command. | new |

## Explicit Non-Goals (v2)

- No push pressure / separation force on *other* units: detours move only
  the mover; blockers are never displaced. (0AD-style push stays out.)
- No walk-through of PARKED units — idle/arrived/failed units are solid.
  (Movers phasing past movers is deliberate M2 policy, not a violation.)
- No formation movement, destination packing, reservation grids, or
  cluster pathfinding.
- No pair-aware yield protocols ("lower id passes first") — symmetric
  sliding plus relax must resolve pair crossings geometrically.
- No `sim-nav-map` core policy expansion: M1–M4 live entirely in this lab's
  controller/wrapper layer.

## Layer 2 Note

Layer 2 (automatic command source) remains a command emitter over
`issue_move*()`/`cancel_move()`. Nothing in v2 changes that boundary; the
Layer 2 smoke keeps working against the same public world API.
