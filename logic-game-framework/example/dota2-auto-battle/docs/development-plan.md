# Dota2 Auto Battle Development Plan

Status: v0 planning document. The directory skeleton exists, but no runtime
GDScript implementation has landed yet.

## Goal

Build a minimal DOTA2/LoL-style lane auto-battle example under LGF:

1. two teams spawn lane creeps,
2. creeps march along one ARAM-like middle lane,
3. enemies are detected by aggro range,
4. units chase until attack range,
5. basic attacks apply damage through LGF Ability/Timeline/Action/Event flow,
6. dead units leave combat,
7. a debug-rich frontend scene shows the loop live.

This is not a continuation of the DOTA2 movement-feel lab. The movement lab stays
Layer 1: hand-feel, hard-block, target switch, and queue-drain behavior. This
example is the game-layer battle prototype.

## Reference Architecture

Use `hex-atb-battle` as the main architectural reference:

- World and Procedure are explicit objects.
- Procedure owns the tick order.
- Actors hold runtime state.
- Actors expose runtime stats through LGF AttributeSet.
- Type/config objects hold shared unit data.
- Actions perform atomic state changes and emit events.
- Frontend subscribes to state/events and does not drive logic.

Do not copy the ATB timing model, hex grid, or "run full logic then replay"
frontend flow. DOTA2 auto battle should be a live single-threaded fixed-tick
simulation.

`rts-auto-battle` can be used as reference material for continuous positions and
existing smoke patterns, but it should not be copied wholesale. Its current scope
includes production, buildings, resources, player commands, and broad RTS systems
that are outside this first DOTA2 lane goal.

Do not copy an unlimited accumulator catch-up loop. Catch-up is allowed only as a
bounded diagnostic path, and every catch-up or debt-drop frame must emit a
warning log.

The active M1 implementation contract is
`docs/design-notes/m1-contract.md`.

## Proposed Directory Ownership

| Directory | Planned responsibility |
|---|---|
| `core/` | `Dota2WorldGameplayInstance`, `Dota2AutoBattleProcedure`, battle events |
| `logic/actors/` | `Dota2BattleActor`, `Dota2UnitActor`, and later hero/tower/building actor variants |
| `logic/attributes/` | DOTA2 battle actor AttributeSet family; M1 may use shared generated config as temporary debt if required |
| `logic/controllers/` | per-unit controllers/brains, persistent current intents, decision scheduling, and intent lifecycle state |
| `logic/config/` | `Dota2UnitTypeConfig`, lane/team constants, skill metadata |
| `logic/ai/` | reusable decision helpers/policies used by controllers, if needed |
| `logic/actions/` | damage, heal, buff, movement-start, attack-start actions |
| `logic/systems/` | lane wave spawner, targeting, combat, death cleanup |
| `logic/movement/` | adapter between battle intent and movement implementation |
| `frontend/` | live visible lane scene and view nodes |
| `tests/` | battle and frontend smoke scenes |

## Milestones

### M0 - Skeleton And Architecture Discussion

Deliverables:

- Create the example directory skeleton.
- Write this development plan.
- Write the M1 implementation contract.
- Write the first tick-model and logic/view contract notes.
- Write the first actor/AttributeSet design note.
- Write the first controller/intent model note.
- Write the first LGF skill-model discussion note.
- Update the example index so the new example is discoverable.

Acceptance:

- No runtime behavior is claimed.
- No `sim-nav-map` policy is moved into LGF core.
- Existing dirty files outside this example are untouched.

### M0.5 - Tick Model And Logic/View Contract

Deliverables:

- `docs/design-notes/tick-model.md`
- `docs/design-notes/logic-view-contract.md`
- Decide frontend-owned logic clock ownership.
- Decide default fixed tick constants.
- Decide the warning-log contract for catch-up and debt drop.

Acceptance:

- Logic uses a fixed timestep.
- Logic and frontend run on one thread.
- Multi-threaded logic is not treated as a planned upgrade path.
- M1 does not introduce a standalone `Dota2SimulationDriver` class.
- The default playable frontend allows only finite catch-up.
- Unlimited catch-up is forbidden.
- Any catch-up frame emits `Log.warning`.
- Any accumulator clamp/drop emits `Log.warning`.
- Frontend receives frames/events and does not mutate logic state.

### M0.6 - Actor Attribute Model

Deliverables:

- `docs/design-notes/actor-attributes.md`
- `logic/attributes/README.md`
- Document the generator ownership debt and the temporary M1 path.

Acceptance:

- DOTA2 runtime stats are modeled through LGF AttributeSet, not raw actor fields.
- `Dota2BattleActor` exposes a common `get_attribute_set()` view.
- Concrete actor subtypes own strong typed `attribute_set` fields.
- The attribute model is a family:
  `Dota2BattleActorAttributeSet` -> unit/tower/building-specific AttributeSets.
- Unit movement stats are not forced onto tower/building AttributeSets.
- Tower/building footprint or identity fields are not forced into unit
  AttributeSets.
- Actor does not grow pure stat forwarding methods.
- DOTA2 may use the shared example attribute generator/config as a temporary M1
  path if that is the current practical generator route.
- DOTA2 generated names are clearly prefixed/namespaced and do not change
  existing hex/rts generated semantics.
- The long-term target remains example-local config/output.
- Existing hex generated AttributeSets are not migrated as part of DOTA2 M1.

### M0.7 - Controller And Intent Model

Deliverables:

- `docs/design-notes/controller-intent-model.md`
- `logic/controllers/README.md`
- Decide the first controller responsibilities, persistent intent lifecycle,
  decision triggers, and decision intervals.

Acceptance:

- M1 does not introduce `Dota2CommandBuffer`, `Dota2CommandSystem`, or
  `Dota2UnitOrder`.
- `WaveSpawner` creates units and attaches controllers; it does not issue
  commands.
- Controllers store persistent current intents; they do not move actors or apply
  damage directly.
- Decision does not run every fixed tick by default.
- Systems advance persistent current intents every fixed tick and report
  running/completed/failed/interrupted status.
- Ordinary lane march and chase are controller behavior/intents, not Abilities.
- Cast intent/request activates an Ability only through `AbilitySet`, not as a
  bypass around condition/cost/cooldown checks.
- Player/debug command queues are future optional work, not M1/M2.

### M1 - Minimal Lane Battle Vertical Slice

Deliverables:

- `Dota2WorldGameplayInstance`
- `Dota2AutoBattleProcedure`
- `Dota2BattleActor`
- `Dota2UnitActor`
- `Dota2UnitController`
- `Dota2LaneCreepController`
- `Dota2DecisionResult`
- `Dota2Intent`
- `Dota2IntentStepResult`
- `Dota2IntentStatus`
- `Dota2BasicAttackAbility`
- `Dota2BattleActorAttributeSet` and `Dota2UnitAttributeSet`
- `Dota2UnitTypeConfig`
- one ARAM-like middle lane definition
- one wave per side
- movement adapter connected to the DOTA2/sim-nav movement path
- first targeting pass with aggro range and target latch
- first basic attack Timeline/Action/Event path
- single-threaded fixed tick loop
- private frontend logic clock block

Acceptance:

- Headless battle smoke can spawn two waves.
- Spawn applies unit type config into AttributeSet, with `max_hp` set before
  `hp`.
- Spawned lane creeps receive a `Dota2LaneCreepController`; no command/order path
  is required for autonomous lane movement.
- Basic attack exists as an Ability from the first battle implementation.
- Targeting is simple but live: creeps can acquire an enemy, keep the target,
  and attack until the target dies or becomes invalid.
- Movement goes through the DOTA2/sim-nav adapter path, not direct position
  mutation.
- M1 does not need towers, but the actor/attribute base shape must not block
  later `Dota2TowerActor` / `Dota2TowerAttributeSet`.
- Units progress toward lane objectives over time.
- Procedure has one clear tick order.
- No frontend-only code mutates logic state.
- Catch-up warning behavior can be tested or manually observed from the
  frontend logic clock block.

### M2 - Targeting And Basic Attack Hardening

Deliverables:

- focused tests for aggro range, target latch, target invalidation, and
  no-jitter target switching,
- focused tests for basic attack legality, cooldown/timeline phase, damage, and
  death events,
- clearer `Dota2IntentStepResult` reasons for blocked movement, cooldown blocked,
  target invalid, completed, and failed states,
- event vocabulary cleanup driven by the logic/view contract.

Acceptance:

- Units acquire enemies only inside aggro range.
- Latest valid target is kept until dead, lost, or out of allowed range.
- Controllers choose/keep/interrupt intents before movement/Ability systems
  mutate state for the tick.
- Current intent completion, failure, and interruption are explicit and
  observable in tests.
- Attack only fires when the basic attack Ability is legal and target is in
  attack range.
- Damage and death are recorded as events.
- M2 does not introduce targeting or basic attack for the first time; it hardens
  the M1 vertical slice.

### M3 - LGF Skill Model

Deliverables:

- Extend the M1 basic attack Ability shape toward future DOTA2 skills.
- Define how DOT/HOT/aura/attack modifier effects avoid hardcoded tick branches.

Acceptance:

- Basic attack remains on the LGF Ability/Timeline/Action/Event path.
- Periodic effects are not hardcoded in the Procedure tick loop.
- Skill execution has a path for future cast point, backswing, projectile, and
  passive reactions.

### M4 - Movement Adapter Hardening

Deliverables:

- Harden the M1 movement adapter boundary.
- Add diagnostics for movement state, path state, blocked reason, and failed
  reason.
- Add tests that prove controller/ability code only talks to the adapter and
  never mutates pathfinding internals.
- Keep the adapter replaceable if the underlying DOTA2 movement lab API changes.

Acceptance:

- AI/skill code never directly mutates pathfinding internals.
- Movement can be replaced without rewriting combat or targeting.
- Hard-block DOTA2 movement feel remains an example-layer policy.
- No push pressure, friendly phasing, formation, destination packing, or group
  pathfinding is introduced through the battle layer.
- M4 does not introduce sim-nav movement for the first time; it hardens and tests
  the M1 adapter path.

### M5 - Visible Frontend Scene

Deliverables:

- `frontend/dota2_lane_battle.tscn`
- live unit views,
- HP bars,
- attack/death visual feedback,
- readable lane camera framing,
- debug panels for actor state, current intent, movement state, ability state,
  tick/catch-up telemetry, and recent battle events.

Acceptance:

- Opening the scene in Godot and pressing F6 shows two sides meeting and fighting.
- Frontend reads state/events; it does not own battle decisions.
- Frontend intentionally shows rich debug data in the first version.
- A frontend smoke verifies the scene loads and creates expected views.

## Open Design Questions

- When future player control exists, should cast requests override autonomous
  controller state, fail while busy, or use a later queued-command model?
- How small should the first basic-attack Timeline be while preserving the
  future attack point / backswing / projectile path?
- How should aura and DOT/HOT effects be represented so they do not become
  special Procedure tick branches?
- When should the temporary shared AttributeSet generator use be replaced by
  example-local config/output?
- Which parts should be promoted to LGF core only after at least two examples need
  the same abstraction?

## Current Validation

No new tests are expected to pass yet because this is a skeleton-only milestone.
The first validation target after implementation starts should be:

```powershell
./tools/run_tests.ps1 dota2autobattle/smoke
```

That test group does not exist yet.
