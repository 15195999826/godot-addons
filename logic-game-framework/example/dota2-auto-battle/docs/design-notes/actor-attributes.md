# Actor Attributes For Dota2 Auto Battle

Status: design draft. This document defines the intended actor/attribute shape
before any runtime GDScript implementation lands.

## Why This Exists

DOTA2-style combat depends on many runtime stats: HP, attack damage, attack
range, move speed, aggro range, cooldown timing, armor, modifiers, and later
auras/items/buffs. These values should not become scattered fields on
`Dota2UnitActor`, `Dota2TowerActor`, or other battle actors, and actors should
not grow pure forwarding getters such as `get_hp()` / `set_hp()`.

LGF already has an AttributeSet model. DOTA2 should reuse it.

## Hex Reference

`hex-atb-battle` is the reference shape:

- `HexBattleActor` does not own a concrete `attribute_set` field.
- Each concrete actor subtype owns its strong typed AttributeSet field.
- Shared code calls `get_attribute_set()` to read common attributes such as
  `hp` and `max_hp`.
- Specialized code directly reads the strong typed field, for example
  `actor.attribute_set.atk`.
- Attribute inheritance is expressed by generated AttributeSet classes:
  `HexBattleActorAttributeSet` -> `HexBattleCharacterAttributeSet` /
  `HexBattleEnvironmentAttributeSet`.
- `hp <= max_hp` is owned by AttributeSet cross-attribute clamp, not by actor
  setter code.

Keep the contract. Do not copy hex-specific ATB or hex-grid behavior.

## Dota2 Actor Contract

Planned actor shape:

```text
Dota2BattleActor
  ability_set
  team_id
  position_2d
  velocity
  debug_current_target_id # optional mirror only; not authoritative
  is_dead / check_death()
  get_attribute_set() -> Dota2BattleActorAttributeSet

Dota2UnitActor extends Dota2BattleActor
  unit_type
  attribute_set: Dota2UnitAttributeSet

Dota2TowerActor extends Dota2BattleActor
  tower_kind
  attribute_set: Dota2TowerAttributeSet

Dota2BuildingActor extends Dota2BattleActor
  building_kind
  attribute_set: Dota2BuildingAttributeSet
```

Rules:

- `Dota2BattleActor` should expose `get_attribute_set()` as the common view.
- Concrete subtypes should own their strong typed `attribute_set` field.
- `_on_id_assigned()` should sync `ability_set.owner_actor_id` and
  `get_attribute_set().actor_id`.
- Death is data driven: `hp <= 0` marks the actor dead.
- Shared systems/actions use `get_attribute_set()` when they only need common
  fields.
- Unit-specific systems can read `unit.attribute_set.move_speed` directly.
- Tower-specific systems can read `tower.attribute_set.attack_range` directly.
- Do not add pure actor forwarding methods for every stat.
- Actor methods are reserved for semantic behavior such as `is_dead()`,
  `can_attack()`, or target/cooldown decisions.
- The authoritative attack target lives in the controller's current intent,
  such as `AttackTargetIntent.payload.target_id`. Any actor-side target id is an
  optional debug/cache mirror and must not become a second source of truth.

## AttributeSet Family

Do not model DOTA2 as a single `Dota2UnitAttributeSet`. Model it as a battle
actor AttributeSet family:

```text
Dota2BattleActorAttributeSet
  hp
  max_hp
  armor

Dota2UnitAttributeSet extends Dota2BattleActorAttributeSet
  move_speed
  attack_damage
  attack_range
  attack_interval_ms
  aggro_range

Dota2TowerAttributeSet extends Dota2BattleActorAttributeSet
  attack_damage
  attack_range
  attack_interval_ms
  projectile_speed
  aggro_range

Dota2BuildingAttributeSet extends Dota2BattleActorAttributeSet
  # may add production/repair/protection stats later
```

`Dota2BattleActorAttributeSet` should contain only stats that all combat-relevant
actors can meaningfully share. `hp` and `max_hp` are mandatory. `armor` belongs
there only if units, towers, and other attackable buildings all participate in
the same armor/damage model. If the first version has no armor formula, keep
`armor` planned but unused rather than inventing a fake formula.

Tower/building support is the reason the base actor returns
`Dota2BattleActorAttributeSet`, not `Dota2UnitAttributeSet`.

## Static Config Vs Runtime Attributes

Type config is static shared data. It defines the initial values for an actor
kind and any non-modifiable constants.

AttributeSet is runtime mutable data. It is what buffs, auras, items, and
ability modifiers should read or change.

First-version split:

| Field | Owner | Reason |
|---|---|---|
| `hp` / `max_hp` | AttributeSet | runtime combat state, clamped |
| `armor` | shared AttributeSet if all attackable actors use it | modified by buffs/items/protection later; can be unused until damage formula needs it |
| `attack_damage` | subtype AttributeSet | unit/tower attack modifiers can affect it |
| `move_speed` | unit AttributeSet | slows/haste/aura need to affect moving actors; towers/buildings should not inherit it |
| `attack_range` | subtype AttributeSet | unit/tower range modifiers are combat stats |
| `attack_interval_ms` | subtype AttributeSet | unit/tower attack speed modifiers should affect it |
| `aggro_range` | subtype AttributeSet | AI/targeting range can differ by unit/tower |
| `team_id` | Actor | identity, not a stat modifier target |
| `position_2d` / `velocity` | Actor | simulation state, not AttributeSet data |
| `current_intent.payload.target_id` | Controller intent | authoritative targeting state for `AttackTargetIntent` |
| `debug_current_target_id` | Actor, optional mirror | debug/snapshot cache only; derived from the current intent if kept |
| `tower_kind` / `unit_type` / `building_kind` | Actor/config | actor identity and config lookup |
| `footprint` / `collision_shape` | Actor or config first | pathing/shape data; promote only if modifiers need it |
| `collision_radius` | Actor or config first | unit pathing/shape data; promote only if modifiers need it |
| `attack_point_ms` / `backswing_ms` | skill/timeline config first | authored timing; promote only if dynamic modifiers need it |
| `projectile_speed` | tower/weapon/skill AttributeSet only if modifiable | otherwise keep in weapon/skill config |
| `backdoor_protection` / `glyph` | AbilitySet/tag/modifier state | tower/building protection should not be hardcoded as plain actor flags |

Spawn order should set `max_hp` before `hp`, so cross-attribute clamp never
clips a high-HP unit against the default max value.

## Tower And Special Actor Rules

Special actors should not break the AttributeSet model.

- If an actor can take damage, it should extend `Dota2BattleActor` and expose a
  `Dota2BattleActorAttributeSet` view.
- If an actor has stats that can be changed by external systems, those stats
  belong in that actor's typed AttributeSet.
- If a value is pure identity, geometry, or static authored timing, keep it on
  the actor/config until a real modifier needs it.
- A tower should not inherit unit movement stats just to reuse code.
- A unit should not inherit building footprint/production stats just to reuse
  code.
- Shared combat actions should operate on the common view when possible:
  `target.get_attribute_set().hp`, `target.get_attribute_set().armor`.
- Attack systems can either use typed actor branches for unit/tower-specific
  attack stats, or a small combat interface later if enough actor kinds share
  the same weapon contract. Do not add that interface before it removes real
  duplication.

## AttributeSet Codegen Boundary

The current LGF generator has two hardcoded output families:

- project-level config/output under `res://logic-game-framework-config/attributes`;
- shared example-level config/output under
  `res://addons/logic-game-framework/example/attributes`.

The second path is now a design debt. It couples all examples through one shared
example attribute config and one shared generated output folder. That was
acceptable for early demos, but it is not a good multi-example boundary.

For `dota2-auto-battle`, the desired boundary is example-local ownership, but
M1 should not block on a generator refactor if the current practical route is
the shared example generator/config.

Preferred long-term direction:

- the generator should accept an explicit config path and output directory, or
  scan per-example attribute config roots;
- each example should be able to own its own attribute schema and generated
  files, for example:

```text
example/dota2-auto-battle/logic/attributes/attributes_config.gd
example/dota2-auto-battle/logic/attributes/generated/
```

Allowed M1 paths, in preference order:

1. refactor the generator first so DOTA2 uses example-local generated
   AttributeSet files;
2. temporarily hand-write generated-compatible AttributeSet classes under
   `logic/attributes/`, directly extending `BaseGeneratedAttributeSet`, as
   `rts-auto-battle` currently does;
3. temporarily add clearly namespaced DOTA2 definitions to the shared example
   generator/config and generated output if that is the least disruptive current
   path.

If the third path is used, treat it as explicit technical debt:

- DOTA2 names must be prefixed/namespaced, such as `Dota2BattleActor...`;
- existing hex/rts generated names and semantics must not change;
- the debt should be documented in the implementation notes;
- the long-term target remains example-local config/output.

Do not move the existing hex generated files during the DOTA2 M1 work. That is a
separate migration.

## Acceptance Criteria

- DOTA2 actor stats are represented through LGF AttributeSet, not raw actor
  fields.
- Shared combat code can read `hp/max_hp` through `get_attribute_set()`.
- Unit-specific code can directly read typed stats through
  `unit.attribute_set.<stat>`.
- Actor does not grow pure forwarding getter/setter methods for each stat.
- Attribute changes can be recorded through the existing AttributeSet listener
  path.
- DOTA2 may temporarily use the shared `example/attributes` generator/config
  only as documented M1 debt, with DOTA2-prefixed names and no semantic changes
  to existing examples.
- Any generator refactor keeps LGF core policy-free and project/example
  ownership explicit.
