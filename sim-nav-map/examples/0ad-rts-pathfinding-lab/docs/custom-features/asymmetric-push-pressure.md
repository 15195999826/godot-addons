# Asymmetric Push Pressure (lab-only deviation from 0 A.D.)

Status: implemented (2026-05-11), with follow-up fix on the same day to
`_push_opposes_attempted_motion` (see "Follow-up: motion-intent-based opposes
check" below). All scenarios green; full smoke 40/40.

## Why this exists

0 A.D.'s push system accumulates `pushingPressure` symmetrically: every push
pair adds the same `addedPressure` to **both** participants regardless of which
unit is moving toward the other (`CCmpUnitMotion_System.cpp:794-796`). The
follow-on speed dampen (`CCmpUnitMotion.h:1235-1255`) is purely a function of
that pressure value.

The visible consequence in the lab demo: when 4-6 same-formation units are
issued a group order to a nearby goal, they start crowded together and stay
crowded — every unit's pressure saturates from mutual push, every unit gets
dampened to ~25% speed, and the group "stuck together moving slowly" instead of
spreading out as one unit naturally passes another.

This file specifies a **lab-only** rule that mirrors the user's intuition: only
the unit whose own forward direction is blocked by another unit should pay the
pressure cost. A unit that has nobody in its way pays no pressure regardless of
how many units sit behind it. Leaders break free; tail-enders queue.

This is **NOT** 0 A.D. parity. The 0AD baseline behavior is preserved by the
existing audit rules in `docs/0ad-unit-motion-policy-parity-audit.md`. This
file documents an intentional deviation, with its own test coverage, kept
isolated from the baseline parity tests.

## Specification

### Geometry

For each ordered pair `(A, B)` already inside push range:

```
AB         := B.pos - A.pos
a_motion   := some scalar field representing "where A wants to go next"
b_motion   := analogous for B

a_facing_b := a_motion.length_squared() > MOTION_DEAD_ZONE_SQ
              and a_motion.dot(AB) > 0
b_facing_a := b_motion.length_squared() > MOTION_DEAD_ZONE_SQ
              and b_motion.dot(BA) > 0   # BA = -AB
```

`MOTION_DEAD_ZONE_SQ` is a small threshold (e.g. `1e-4`) so noise / push-only
displacement does not register as motion intent.

### Cosine threshold (added during implementation)

A raw `dot > 0` test on the motion-vs-`AB` direction was too sensitive: side-by-
side parallel-moving units, after one tick of perpendicular push displacement,
have motion intent that points *very slightly* back toward their displaced-from
neighbor (recovery direction). That sliver of "facing" produced unwanted
pressure accumulation from frame 2 onward.

Fix: compare the **normalized** dot — i.e. the cosine of the angle between
motion and `AB` — against `MOTION_FACING_COSINE_MIN = 0.05` (≈ angle < 87°).
Anything within ~87° of facing counts; near-perpendicular doesn't.

Implementation avoids `sqrt` by squaring both sides:
`dot² > MOTION_FACING_COSINE_MIN² × |motion|² × |AB|²`

### Pressure rule (replaces the current symmetric add)

```
if a_facing_b: pressure_deltas[a.id] += pressure_delta
if b_facing_a: pressure_deltas[b.id] += pressure_delta
```

Push force itself (`_apply_pushes`) is **not** changed — units still get
displaced apart so they don't tunnel through one another.

### Source of `motion`

Use `unit.current_waypoint() - unit.position` when `unit.has_path()`, so the
motion vector tracks **intent** (where the unit is trying to go), not the
turbulent actual displacement that includes the previous tick's push reactions.

Fall back to `unit.position - previous_position` for units without a path
(idle, post-arrive). This fallback is mostly a precaution — units without a
path that aren't moving will register zero motion and naturally fail the
`> MOTION_DEAD_ZONE_SQ` test.

### Same control group

The 0 A.D. `same control group` exception (push idle formation members so
moving members don't visually pass through them) is preserved at the **push
force** layer. The pressure layer follows the same asymmetric rule as
out-of-group pairs: a stationary same-group teammate gets push force applied
(so it gets nudged out of the way) but does not pay pressure (its
`b_motion` ≈ 0, `b_facing_a` is false), and the moving teammate pays pressure
only if it is actually heading toward the stationary one.

This means a stopped formation member still gets nudged aside when an
in-formation moving teammate runs through, but the stopped one does not slow
down further moving teammates by inflating their pressure.

## Behavior matrix

| Case | a_motion·AB | b_motion·BA | a_facing_b | b_facing_a | Pressure | Intuition |
|---|---|---|---|---|---|---|
| Two units, same direction, B in front, A chasing | > 0 | < 0 | true | false | A only | Tail-ender slows, leader stays full speed |
| Two units, head-on collision | > 0 | > 0 | true | true | both | Both should yield |
| Two units, A is leader, B chasing | < 0 | > 0 | false | true | B only | Symmetric to row 1 |
| Two units side-by-side, motion roughly parallel | ≈ 0 | ≈ 0 | false | false | none | They just brush past |
| Moving + stopped, stopped is in front of mover | > 0 | 0 | true | false | mover only | Mover decelerates, stopped untouched |
| Moving + stopped, mover going elsewhere | < 0 | 0 | false | false | none | They just happen to be near, no slowdown |
| Stopped + stopped | 0 | 0 | false | false | none | Pressure is irrelevant for stationary pairs |

## Test plan (TDD red-green-refactor)

Each scenario is a smoke test in
`addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/smoke/smoke_zero_ad_rts_lab_motion.gd`.
Test names use the prefix `_test_asymmetric_push_*`.

1. **leader_stays_at_full_pressure** — A at (100,100) chasing B at (130,100), both
   moving toward (300,100). After a few ticks of `apply_push_adjust`,
   `B.pushing_pressure` stays at 0; `A.pushing_pressure` rises.

2. **head_on_both_pressured** — A at (100,100) moving toward (300,100), B at
   (130,100) moving toward (50,100). Both `pushing_pressure` rise.

3. **side_by_side_neither_pressured** — A at (100,100) moving toward (300,100),
   B at (100,130) moving toward (300,130). Neither `pushing_pressure` rises
   (they are within push range vertically but neither faces the other).

4. **moving_into_stopped_only_mover_pressured** — A moving toward where stopped
   B sits. A accumulates pressure; B does not.

5. **same_control_group_leader_unhindered** — three units in a row, all in the
   same control group, all moving the same direction. The frontmost has zero
   pressure; the back two accumulate pressure proportional to who is in front
   of them.

6. **regression: no_self_pressure_from_arrive_clear** — when a unit's path goes
   empty (arrived) on the same tick a push pair is evaluated, motion ≈ 0 falls
   back to the previous-position vector; ensure the pair does not register
   spurious pressure on the just-arrived unit.

Existing tests that may need predicted-value updates:

- `_test_pair_push_uses_goal_agnostic_pressure` — **pinned to baseline**: the
  test name and assertion message ("expected 0AD-style pair push to stay
  goal-agnostic") explicitly check 0 A.D. parity. Test now sets
  `world.motion.asymmetric_push_pressure_enabled = false` at the top.
- `_test_logged_offset_opposing_units_build_push_pressure` — passes unchanged
  under the new rule (units head-on, both face → both pressured).
- `_test_same_control_group_ignores_and_pushes_members` — passes unchanged
  (asserts push force application, not pressure values).
- `_test_logged_same_control_group_arrival_does_not_tunnel` — passes unchanged
  (asserts geometric outcomes, not pressure values).

For each, decide one of:
- Update expectation to match the new asymmetric rule (preferred where the new
  rule still validates the original intent of the test).
- Mark the case as 0AD-baseline check and pin it to the symmetric rule via a
  toggle if the original intent was strict 0 A.D. parity.

## Toggle (for keeping 0 A.D. baseline option)

Add `motion.asymmetric_push_pressure_enabled: bool = true` (default on, since
this is the lab's chosen behavior). Setting it to `false` restores 0 A.D.
symmetric pressure for parity audits and regression diffing.

## Implementation surface

Single function: `_accumulate_pair_push` in
`addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_motion_controller.gd`,
the block currently around lines 1150-1152:

```gdscript
var pressure_delta := _push_pressure_delta(average_distance, max_distance, moving_count)
pressure_deltas[a.id] = int(pressure_deltas.get(a.id, 0)) + pressure_delta
pressure_deltas[b.id] = int(pressure_deltas.get(b.id, 0)) + pressure_delta
```

becomes:

```gdscript
var pressure_delta := _push_pressure_delta(average_distance, max_distance, moving_count)
if asymmetric_push_pressure_enabled:
    if _unit_motion_faces(a, b, previous_positions):
        pressure_deltas[a.id] = int(pressure_deltas.get(a.id, 0)) + pressure_delta
    if _unit_motion_faces(b, a, previous_positions):
        pressure_deltas[b.id] = int(pressure_deltas.get(b.id, 0)) + pressure_delta
else:
    pressure_deltas[a.id] = int(pressure_deltas.get(a.id, 0)) + pressure_delta
    pressure_deltas[b.id] = int(pressure_deltas.get(b.id, 0)) + pressure_delta
```

Helper:

```gdscript
const MOTION_DEAD_ZONE_SQ: float = 1.0e-4

func _unit_motion_faces(
    unit: ZeroAdRtsLabUnit,
    other: ZeroAdRtsLabUnit,
    previous_positions: Dictionary
) -> bool:
    var motion := _unit_motion_intent(unit, previous_positions)
    if motion.length_squared() <= MOTION_DEAD_ZONE_SQ:
        return false
    var to_other := other.position - unit.position
    return motion.dot(to_other) > 0.0

func _unit_motion_intent(
    unit: ZeroAdRtsLabUnit,
    previous_positions: Dictionary
) -> Vector2:
    if unit.has_path():
        var wp := unit.current_waypoint()
        return wp - unit.position
    var prev: Vector2 = previous_positions.get(unit.id, unit.position) as Vector2
    return unit.position - prev
```

No other functions need to change. Push force, dampening, decay all unchanged.

## Follow-up: motion-intent-based opposes check

After the initial fix, log
`zero_ad_rts_lab_2026-05-11T01-30-44_tick_1495.json` showed a leader
(blue_3) still stuck at high pressure for ~80 ticks despite zero
`pressure_delta` accumulation. Root cause was a separate path:

`_push_opposes_attempted_motion` mirrors 0 A.D.
`CCmpUnitMotion_System.cpp:610-616` and uses

```
attempted_move.dot(attempted_move + push_vec) < 0.5
```

When push pressure has already dampened the unit's speed, the per-tick
`attempted_move` shrinks below the unit-circle scale (~0.4 px). The
`0.5` threshold then trips even when push and motion are roughly
aligned, because `attempted_move · attempted_move = |attempted_move|²`
is itself only ~0.16. The check then calls
`_mark_push_pressure_obstructed`, which force-elevates the unit's
pressure to `MIN_PRESSURE_IF_OBSTRUCTED = 80`. The leader is now stuck
at pressure 80 → speed dampened → `attempted_move` short → trigger
again → pressure stays at 80 → ... self-reinforcing.

Verified with blue_3 (tick 1290→1291):

- `attempted_move ≈ (0.38, 0.13)`, length² ≈ 0.16
- push from blue_2 (left-of-blue_3) ≈ (0.28, 0.30)
- `attempted_move · (attempted_move + push) ≈ 0.31 < 0.5` → TRUE
  (incorrect, push and motion are roughly co-directional)

Geometric "opposes" should be `motion · push < 0` — push pointing
roughly opposite to where the unit wants to go. blue_3 actual:
`motion (5.5, -1.5) · push (0.28, 0.30) = +1.09 > 0` → not opposes.

### Rule (under the asymmetric toggle)

A naive "motion-only" replacement (`motion · push < 0`) was tried first and
broke `_test_logged_corridor_push_replay_avoids_corner_repath`: it eagerly
marked head-on collisions even when units were at full speed, where the
0 A.D. baseline check (which has an implicit speed gate via
`|attempted|² >> 0.5`) intentionally lets fast units push through without
escalating to pressure 80.

The shipped rule **combines both** — keep the speed gate, but additionally
require geometric opposition under the asymmetric toggle:

```gdscript
var attempted_threshold_met := attempted_move.dot(attempted_move + push_vec) < 0.5
if not asymmetric_push_pressure_enabled:
    return attempted_threshold_met
if not attempted_threshold_met:
    return false
var motion := _unit_motion_intent(unit, previous_positions)
if motion.length_squared() <= MOTION_DEAD_ZONE_SQ:
    return false
return motion.dot(push_vec) < 0.0
```

Combined behavior:

| Case | attempted threshold | motion · push | 0 A.D. (toggle off) | Lab (toggle on) |
|---|---|---|---|---|
| Leader, slow (blue_3 stuck) | trips (0.31<0.5) | +0.41 (NOT) | **mark** | NOT mark — pressure can decay |
| Head-on, full speed | NOT (1.0>0.5) | strongly < 0 | NOT mark | NOT mark (matches baseline) |
| Head-on, slow | trips | strongly < 0 | mark | mark (genuine obstruction) |
| Leader being chased, fast | NOT (high \|attempted\|²) | > 0 | NOT mark | NOT mark |

### Test

`_test_asymmetric_push_leader_not_force_elevated_under_short_attempted_move`
sets up a leader/chaser pair with the leader's pressure already at 60,
provides a `previous_positions` that yields a short `attempted_move ≈
(0.4, 0)`, runs `apply_push_adjust` once, and asserts the leader's
pressure was NOT force-elevated to 80. Baseline (toggle off / pre-fix)
yields pressure 80 from the `_mark_push_pressure_obstructed` force; the
fix yields ~57 (pure decay).

## Acceptance

- All 6 new `_test_asymmetric_push_*` tests PASS.
- Toggle off: full smoke pack still PASS (0 A.D. baseline preserved).
- Toggle on: any failing existing test is reviewed and either updated or pinned
  to baseline via toggle, with rationale recorded above.
- Visual demo: 6 same-formation units issued a group order to a goal in open
  terrain do not "stick together"; the leader (geometrically frontmost) reaches
  the goal-area at full speed while the others queue.
