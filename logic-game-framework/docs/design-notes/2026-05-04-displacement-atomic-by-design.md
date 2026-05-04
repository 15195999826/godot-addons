# Displacement Is Atomic By Design

Date: 2026-05-04

Scope: `example/hex-atb-battle`

## Decision

Forced displacement is an atomic logic operation.

`PushAction` resolves raycast, collision, `grid.move_occupant`, actor `hex_position`, and displacement events in one HIT keyframe. It does not expose an intermediate "being pushed" state to the timeline scheduler.

When the target should be unable to immediately start its own next action, Push grants a timed `HexBattleActionLockStatus`:

- ability config: `status_action_lock`
- component tags: `action_locked`, `cant_act`, plus reason tag such as `displacement_stagger`
- duration for displacement V1: `250 + 200 * max(1, actual_distance)` ms
- collision bonus V1: `0ms`, still recorded as `collision_action_lock_bonus_ms`

This is not skill recovery on the caster. It is a target-side action lock caused by displacement.

## Event Protocol Rule

The deciding question is whether logic state is exposed in phases for other systems to read.

- Atomic completion: use one past-tense event, e.g. `actor_displaced`.
- Intermediate state exposed across ticks: use `start/complete`, status, reservation, or another explicit state protocol.

`Move` uses `move_start` + `move_complete` because the reserved destination exists across timeline ticks and other actors can observe or compete with it. `PushAction` does not hold such an intermediate state, so `actor_displaced` and `push_blocked` are enough.

## Why Push Is Not Start/Complete

Making Push cross-tick would require answers that V1 gameplay does not need:

- How to reserve path cells when the path can truncate on collision.
- How to resolve two simultaneous pushes on the same target.
- What happens if the target dies mid-flight.
- Whether AI and cast eligibility treat an actor mid-push as adjacent, occupying, or absent.
- How to represent committed-but-unresolved displacement in actor/timeline state.
- How to keep replay deterministic when intermediate events interleave.

For this sample, immediate position commit plus target action lock gives the desired feel with less scheduler coupling.

## Action Gate

`cant_act` has two gates.

Primary gate: `CharacterActor.can_act()` checks `cant_act`. If ATB is full but `cant_act` exists, the actor does not enter AI decision and `reset_atb()` is not called.

Secondary gate: active skills add `Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT)`. This blocks direct activation paths that bypass ATB.

This does not cancel in-flight abilities. `ActiveUseComponent` conditions are checked before activation; `AbilityExecutionInstance` timeline ticks continue after activation. Passive triggers, buff ticks, shield/thorn reactions, damage, heal, and post-event handlers are not blocked by `cant_act`.

`Move` currently uses `ActivateInstanceConfig`, not `ActiveUseConfig`; AI move is still blocked by the primary actor gate. A future direct player move command should add its own action-lock gate when that path exists.

## Event Metadata Is Fact

The logic action computes action-lock duration once and writes it into the displacement event:

- `actual_distance`
- `action_lock_duration_ms`
- `collision_action_lock_bonus_ms`

Frontend visualizers consume these event facts directly. They must not re-query skill config or duplicate the duration formula.

## Rejected Alternative: Scheduler Delay

Delaying the actor's next timeline keyframe in the scheduler was rejected.

It hides control state from cast eligibility, UI, replay, SkillPreview, and future status consumers. It also couples a gameplay control effect to timeline internals. A timed status with tags fits the existing `AbilitySet` / `TagComponent` / `TimeDurationComponent` pattern and composes with future control effects.

## Future Protocol Shapes

Not every future mechanic is just one event or `start/complete`.

- Channel: likely `channeling` status plus cancel/complete outcome.
- Jump: likely `airborne` status plus landing target reservation and landing event.
- Cast time: likely execution instance plus `casting` tag; may not need a separate start/complete event if no other system reads intermediate placement.

The protocol should follow the same rule: expose only the intermediate state that other logic systems actually need to read.
