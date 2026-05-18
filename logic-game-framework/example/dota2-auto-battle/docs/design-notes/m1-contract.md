# M1 Contract For Dota2 Auto Battle

Status: implementation contract draft. This document records the decisions that
must guide the first runtime implementation.

## Scene Goal

M1 should build an ARAM-like single-lane auto battle:

- one horizontal middle lane;
- left and right teams spawn lane creeps from opposite ends;
- units march toward the opposing side;
- units acquire enemies on contact range/aggro range;
- units chase into attack range;
- basic attacks resolve through LGF Ability/Timeline/Action;
- HP, death, intent state, movement state, and event logs are visible in the
  frontend for debugging.

This is enough scenario direction for M1. Do not wait for more map layout
details before starting.

## Intent Execution Ownership

Use the DESKTK auto-chess shape as the reference:

```text
AI decision
  -> CurrentCommand
    -> staged execution
```

For this example, rename the concept to intent because it is autonomous unit
behavior rather than player command input:

```text
Brain decision
  -> controller.current_intent
    -> movement and ability systems advance the intent
      -> systems return Dota2IntentStepResult
        -> controller updates lifecycle
```

Ownership:

- controller owns `current_intent`, `last_decision_result`,
  `next_decision_tick`, and final lifecycle state;
- movement system reports movement facts such as running, arrived, blocked,
  failed, or stopped;
- ability/basic-attack execution reports cast/attack facts such as running,
  hit, completed, failed, target invalid, or cooldown blocked;
- controller decides whether the current intent is kept, completed, failed,
  interrupted, or replaced.

Systems report facts. Controller owns lifecycle.

## Movement Contract

M1 should connect to `sim-nav-map` using the DOTA2 lab as the reference
implementation. Do not start with a separate straight-line movement prototype.

The battle layer still needs a movement adapter so controller/ability code never
mutates pathfinding or motion-controller internals directly:

```text
Dota2Intent
  -> Dota2MovementAdapter
    -> sim-nav-map DOTA2 movement primitives
```

The adapter is allowed to translate `LaneMarchIntent`, `AttackTargetIntent`, and
future `MoveToPointIntent` into movement goals, target following, stop requests,
or cancel requests. It must not move DOTA2 movement policy into LGF core or
`sim-nav-map` core.

Keep the existing DOTA2 movement feel constraints:

- hard block is acceptable;
- no friendly walk-through/phasing;
- no formation/destination packing/group pathfinding;
- no push pressure;
- no lab policy in `sim-nav-map` core.

## Basic Attack Contract

Basic attack is an LGF Ability from the first battle implementation.

`AttackTargetIntent` should not directly apply damage. Its execution path is:

```text
AttackTargetIntent
  -> approach or stop by movement adapter
  -> when target is valid and in range, request basic attack ability
  -> Ability/Timeline triggers attack timing
  -> Action applies damage
  -> Events feed logic frame and frontend
```

This keeps attack windup, backswing, projectile timing, passives, modifiers, and
future attack effects on the same LGF path as skills.

## Debug-Rich Frontend

The first frontend should favor observability over clean UI.

Show as much useful battle state as practical:

- logic tick and catch-up warning counters;
- actor id, team, unit type;
- HP/max HP;
- current intent kind, status, target id, and next decision tick;
- movement state, current goal, blocked/failed reason if available;
- basic attack ability state, cooldown/timing, and current target;
- recent events such as `unit_spawned`, `target_acquired`, `attack_started`,
  `attack_landed`, `damage_applied`, `unit_died`, and `unit_removed`.

This debug surface can be reduced later after behavior is stable.

## Attribute Generator Contract

The shared example AttributeSet generator boundary is a known design debt.

Long term, DOTA2 should have example-local attribute config/output. M1 should not
block on that generator refactor. For now, DOTA2 may add namespaced definitions
to the shared example attribute config/output if that is the only practical way
to use the current generator.

Rules for the temporary path:

- names should be clearly DOTA2-prefixed;
- avoid changing existing hex/rts generated semantics;
- document the generator coupling as temporary debt;
- keep the actor-side AttributeSet family shape intact:
  `Dota2BattleActorAttributeSet` -> unit/tower/building sets.

## M1 Acceptance

- Opening the frontend scene with F6 shows an ARAM-like lane fight.
- Both teams spawn lane creeps and move along one lane.
- Movement uses the DOTA2/sim-nav movement adapter path.
- Lane creeps use controllers with persistent current intents.
- Basic attack is an Ability and damage is applied through Action/Event flow.
- Frontend displays rich debug state and recent event logs.
- DOTA2-specific policy stays in this example layer, not LGF core or
  `sim-nav-map` core.
