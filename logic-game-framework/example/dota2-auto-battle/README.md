# Dota2 Auto Battle Example

Status: design skeleton only. No runtime GDScript implementation yet.

`dota2-auto-battle` is the planned LGF example for a DOTA2/LoL-style lane fight:
two sides spawn lane creeps into an ARAM-like middle lane, units march along the
lane, acquire enemies inside aggro range, chase into attack range, attack, take
damage, and die.

This example is intentionally separate from
`addons/sim-nav-map/examples/dota2-rts-pathfinding-lab`. The sim-nav lab remains
a movement-feel laboratory. This example owns game combat, lane waves, targeting,
skill modeling, frontend visualization, and battle smoke tests.

## Architecture Direction

This example should use `hex-atb-battle` as the architectural reference for LGF
layering:

- `core/`: `WorldGameplayInstance`, `BattleProcedure`, and shared battle events.
- `logic/`: actors, AttributeSet family, unit controllers/brains, unit type
  config, combat actions, lane systems, and movement adapter.
- `frontend/`: live lane battle scene and read-only world views.
- `tests/`: battle and frontend smoke scenes.

It should not inherit the ATB or hex-grid combat model. DOTA2 lane combat uses a
single-threaded fixed real-time tick, continuous positions, persistent
controller intents, LGF Ability-backed basic attacks, and a movement adapter that
uses the DOTA2 movement lab in `sim-nav-map` as reference. Small catch-up is
allowed, but catch-up is diagnostic rather than normal: every catch-up or
debt-drop frame must emit a warning log.

## Planned First Visible Scenario

The first playable scene should show:

- left and right teams spawning one creep wave each,
- both waves marching toward each other on a single lane,
- units acquiring enemies inside aggro range,
- units chasing or stopping based on attack range,
- basic attack Abilities applying HP damage,
- dead units disappearing or entering a visible dead state.
- debug panels showing tick, HP, current intent, movement/ability state, and
  recent battle events.

## Development Docs

- [Development Plan](docs/development-plan.md)
- [M1 Contract](docs/design-notes/m1-contract.md)
- [Tick Model](docs/design-notes/tick-model.md)
- [Logic/View Contract](docs/design-notes/logic-view-contract.md)
- [Actor Attributes](docs/design-notes/actor-attributes.md)
- [Controller And Intent Model](docs/design-notes/controller-intent-model.md)
- [LGF Skill Model Discussion](docs/design-notes/lgf-skill-model.md)

## Non-Goals For The First Version

- Heroes, items, fog of war, economy, towers, last hit, denies, spell targeting UI.
- PlayerController, command queues, replay input, or queued player orders.
- Formation, destination packing, group pathfinding, friendly phasing, or push
  pressure inside the movement layer.
- Moving DOTA2-specific combat policy into LGF core or `sim-nav-map` core.
