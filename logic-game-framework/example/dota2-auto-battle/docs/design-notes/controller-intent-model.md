# Controller And Intent Model For Dota2 Auto Battle

Status: design draft. No runtime GDScript implementation exists yet.

## Decision

M1/M2 should use persistent intent execution, not per-tick intent emission.

The controller/brain makes a decision only when the current intent needs to be
created, replaced, completed, failed, interrupted, or reconsidered. The selected
intent remains the unit's current intent until its lifecycle changes.

```text
Brain decision
  -> Dota2Intent
    -> stored as controller.current_intent
      -> systems advance current_intent every fixed tick
        -> Dota2IntentStepResult
          -> controller updates intent lifecycle
```

This follows the useful shape from the DESKTK auto-chess code: AI decision
produces one current action/command, then the stage/execution layer advances that
choice. DOTA2 auto battle keeps the same lifecycle idea but names it `Intent`,
because it is autonomous unit behavior rather than player command input.

`Command` remains a future optional player-input concept. It should not be used
by `WaveSpawner`, lane creep AI, tower AI, or normal automatic battle behavior.

## Why Intent Is Persistent

If intent is rebuilt every tick, systems cannot tell whether they are continuing
the same action or starting a new one. That makes path reuse, attack windup,
cast point, interruption, completion, and failure semantics muddy.

Persistent intent gives each unit a clear execution contract:

- decision chooses what the unit wants to do now;
- controller stores the current intent;
- systems advance the current intent;
- systems return execution status;
- controller decides when to keep, replace, interrupt, or clear it.

## Terms

- `Dota2UnitController`: per-unit runtime behavior owner. It owns behavior mode,
  current intent, last decision result, and decision scheduling.
- `Dota2LaneCreepController`: first concrete controller for lane march, aggro,
  chase, attack, and return-to-lane behavior.
- `Dota2DecisionResult`: output of a brain decision. It may create a new intent,
  keep the current intent, or clear it.
- `Dota2Intent`: persistent current intention, such as lane march, move to point,
  attack target, or future cast ability.
- `Dota2IntentStepResult`: per-tick execution result returned by systems.
- `Dota2IntentStatus`: lifecycle status of the current intent.

Actors own identity and battle state. AttributeSets own stats. Controllers own
behavior decisions and intent lifecycle. Systems own authoritative mutation.

## Lifecycle

Intent status should be explicit:

```text
NONE
RUNNING
COMPLETED
FAILED
INTERRUPTED
```

Recommended controller state:

```text
Dota2UnitController
  actor_id
  current_intent
  current_intent_status
  last_decision_result
  next_decision_tick
  behavior_mode
```

Recommended intent data:

```text
Dota2Intent
  intent_id
  kind
  created_tick
  priority
  payload
```

`intent_id` matters because systems can use it to distinguish "continue the same
intent" from "start a new intent". For example, movement can keep path-following
runtime while the intent id is stable and reset that runtime when a new intent
appears.

For `AttackTargetIntent`, `payload.target_id` is the authoritative target. Actor
fields may mirror that id for debug snapshots, but execution and decision logic
must read the current intent instead of maintaining a separate actor-owned
target truth.

## Layering

```text
Dota2AutoBattleProcedure
  -> controller pre-step: validate current intent / decide if needed
  -> systems advance current intents
  -> controller post-step: record result, clear or schedule reconsideration
  -> Actions / Events / LogicFrame
```

Controllers must not directly:

- change position,
- apply damage,
- mutate HP,
- bypass cooldowns,
- execute abilities,
- remove dead actors,
- call frontend nodes.

They can update their own behavior state, choose a new intent, interrupt their
own current intent, and record execution status.

## WaveSpawner Boundary

`WaveSpawner` is not a command source and does not issue intents.

It should only:

1. create the unit actor,
2. apply unit type config and AttributeSet values,
3. place the unit at the spawn point,
4. attach the correct controller,
5. register the actor/controller with Procedure or world runtime.

For lane creeps:

```text
WaveSpawner
  -> Dota2UnitActor(team_id, unit_type_id, spawn_position)
  -> Dota2LaneCreepController(lane_id, team_id)
```

The new controller starts with no current intent. On its first logic tick, it
decides and usually creates a `LaneMarchIntent`.

## First Intent Types

M1/M2 should keep the vocabulary small:

```text
LaneMarchIntent
  lane_id
  waypoint_index

AttackTargetIntent
  target_id
  leash_origin_or_lane_id

MoveToPointIntent
  point

IdleIntent
```

Future skill work can add:

```text
CastAbilityIntent
  ability_id
  target
  cast_policy
```

Ordinary lane march, chase, and stop behavior are not Abilities. They are
controller intents advanced by movement systems. Basic attack and future spell
casts are Ability executions requested by an intent and checked through
`AbilitySet`.

## Decision Triggers

A controller should decide only when one of these is true:

- no current intent exists;
- current intent completed;
- current intent failed;
- current intent was interrupted by a higher-priority reason;
- current intent became invalid, such as target dead;
- current tick reached `next_decision_tick` and the current intent allows
  reconsideration.

Decision should not happen merely because a new fixed tick happened.

## Decision Intervals

Decision interval is controller policy, not global tick policy.

Initial lane creep recommendation at 30 Hz:

- immediate decision when no current intent exists;
- immediate redecision when current target is dead or invalid;
- aggro search while lane marching every 5 ticks;
- add a small deterministic stagger, such as `actor_spawn_index % 3`, so all
  creeps do not search on the same tick;
- do not periodically swap attack targets while `AttackTargetIntent` remains
  valid;
- reconsider attack target only on death, invalid target, leash failure, or a
  future explicit high-priority policy.

This keeps DOTA2 creep behavior stable: units do not jitter between targets just
because a periodic scan found a slightly closer enemy.

## Execution

Systems advance the current intent every fixed tick and return a result:

```text
Dota2IntentStepResult
  status
  reason
```

Example status meanings:

```text
RUNNING: keep current intent
COMPLETED: clear current intent and decide again next tick or immediately
FAILED: clear current intent and decide a fallback
INTERRUPTED: current intent was cancelled by controller policy
```

Lane movement example:

```text
LaneMarchIntent:
  MovementSystem follows current lane waypoint
  if waypoint reached -> update waypoint or complete intent
  if blocked beyond policy -> FAILED

AttackTargetIntent:
  MovementAdapter follows target until in range
  BasicAttackAbility is requested when cooldown/range/legal checks allow
  if target dead -> COMPLETED
  if target invalid/leash exceeded -> FAILED
```

Ability-backed attack example:

```text
AttackTargetIntent:
  if target alive and in range and basic attack legal -> AbilitySet starts/continues attack
  if ability cooldown/cast point/backswing is active -> RUNNING
  if target out of range -> RUNNING, movement continues chase
```

The controller owns the lifecycle of `AttackTargetIntent`, but it does not own
the attack mutation. The movement adapter reports whether the target is in
range. `AbilitySet` and `Dota2BasicAttackAbility` own final legality,
cooldown/cast timing, and action emission. The damage Action owns HP mutation.

The brain may choose an attack target based on world-state conditions, but
cooldown, range, tags, and ability legality must still be enforced by the
execution path.

## Interruption

Interruption is explicit controller policy.

M1 lane creep rules:

- death/disabled actor interrupts any intent;
- target death completes `AttackTargetIntent`;
- target invalid or leash exceeded fails `AttackTargetIntent`;
- `LaneMarchIntent` may be interrupted by a valid enemy found during scheduled
  aggro search;
- `AttackTargetIntent` is not interrupted by ordinary lane marching;
- no multi-intent queue exists.

Future hero or player control can add higher-priority overrides, but that should
be designed with `PlayerController` separately.

## First Controller Behavior

The first lane creep controller can be a small explicit state machine. Do not
introduce a behavior tree in M1.

Expected decision behavior:

```text
No current intent:
  create LaneMarchIntent

LaneMarchIntent at reconsider tick:
  enemy in aggro range -> interrupt LaneMarchIntent, create AttackTargetIntent
  no enemy -> keep LaneMarchIntent, schedule next reconsider tick

AttackTargetIntent:
  target dead -> complete, next decision returns to LaneMarchIntent
  target invalid/leash failed -> fail, next decision returns to LaneMarchIntent
  otherwise -> keep AttackTargetIntent
```

## Relationship To Ability

Basic attack is an Ability from the first battle implementation.
`AttackTargetIntent` means "keep this target and advance toward a legal basic
attack." It does not mean "apply damage directly."

The intended path is:

```text
AttackTargetIntent
  -> movement adapter approaches/stops
  -> AbilitySet requests Dota2BasicAttackAbility
  -> Timeline reaches attack point
  -> Action applies damage
  -> Event records attack/damage/death facts
```

This keeps attack windup, backswing, projectile timing, modifiers, and passive
reactions on the same LGF path as future active skills. A controller may choose
a `CastAbilityIntent`, but the controller must not bypass Ability legality.

## Future Player Input

A future player-controlled hero can introduce a separate input boundary:

```text
PlayerController
  -> player request / command
    -> selected hero controller or AbilitySet
```

That future layer should be introduced only when there is a real player/debug
input requirement such as right-click movement, hero spell casting, replay, or
input recording.

If introduced later:

- command/request objects belong to `PlayerController` or debug tooling;
- lane creep AI and `WaveSpawner` still do not use commands;
- player input should not mutate actor internals directly;
- command/request processing must stay inside the fixed logic tick.

## Procedure Placement

Recommended fixed tick shape:

```text
1. tick AbilitySet cooldowns / durations
2. cleanup dead actors and invalidate impossible current intents
3. update targeting helpers or spatial indexes
4. controller decision step: create/keep/interrupt current intents
5. movement and ability systems advance current intents
6. controller result step: record COMPLETED/FAILED/RUNNING results
7. death cleanup and event snapshot
```

The exact order can be refined during implementation. The important boundary is
that controllers choose persistent intents and systems execute them.

## Acceptance Criteria

- M1 does not create `Dota2CommandBuffer`, `Dota2CommandSystem`, or
  `Dota2UnitOrder`.
- `WaveSpawner` creates actors and attaches controllers; it does not issue
  commands or intents.
- Every autonomous mobile unit has a controller, or is explicitly inert.
- Controllers own `current_intent`, `last_decision_result`, and
  `next_decision_tick`.
- Decision does not run every fixed tick by default.
- Systems advance persistent current intents every fixed tick.
- Systems can distinguish continuing an intent from starting a new intent.
- Controllers handle intent completion, failure, and interruption explicitly.
- Controllers do not directly mutate position, HP, cooldowns, death state, or
  ability execution state.
- Movement execution is owned by the movement adapter/systems.
- Basic attack execution is owned by `AbilitySet`, `Dota2BasicAttackAbility`,
  Timeline, and Actions.
- Cast intent activates abilities only through `AbilitySet`.
- Ordinary lane march and chase are not modeled as Abilities.
- Future player command/request work is optional and out of M1/M2 scope.
