# Logic/View Contract For Dota2 Auto Battle

Status: design contract draft. No runtime implementation exists yet.

## Ownership

The logic layer is authoritative.

It owns:

- unit HP and death state,
- team and lane state,
- position and facing used by combat decisions,
- aggro target and attack target,
- controller current intent and lifecycle state,
- movement state used by the adapter,
- basic attack Ability/cooldown/timeline state,
- event emission,
- logic tick index and simulation time.

The frontend is read-only with respect to battle state.

It owns:

- Godot nodes,
- camera and screen layout,
- interpolation between logic snapshots,
- HP bar visuals,
- attack/death VFX,
- debug display controls.

The first version has no runtime player command path. The frontend may request
scene-level setup, restart, pause, or speed changes through explicit scene or
Procedure entry points, but it must not directly edit actors, systems, movement
state, HP, cooldowns, targets, controller state, or Procedure internals.

## Logic To View

Each fixed logic tick should produce or update a frame that can be consumed by
the frontend:

```gdscript
class_name Dota2LogicFrame

var tick_index: int
var logic_time_ms: float
var actor_snapshots: Dictionary
var events: Array
```

Snapshot data should be stable data, not live actor references. The first
version can keep this lightweight, but the contract should stay clear:

- snapshot = current observable state;
- event = something that happened during this logic tick;
- view = consumer only.

Expected snapshot fields for lane creeps:

- actor id,
- unit type id,
- team id,
- position,
- facing or move direction,
- current HP and max HP,
- alive/dead state,
- optional debug target mirror if exposed, derived from the current intent,
- current intent kind/status/target id,
- next decision tick,
- movement state, including destination/path status/block or failure reason when
  available,
- basic attack Ability state, cooldown/timeline phase, and active target when
  available.

Expected first event vocabulary:

- `unit_spawned`,
- `intent_started`,
- `intent_completed`,
- `intent_failed`,
- `target_acquired`,
- `attack_started`,
- `attack_landed`,
- `damage_applied`,
- `unit_died`,
- `unit_removed`.

This document is the canonical event vocabulary for M1/M2. Other design notes
should refer to these names rather than inventing local aliases.

Catch-up and debt-drop warnings are telemetry from the frontend logic clock
block. They may appear in the debug panel, but they should not be modeled as
battle events that drive gameplay.

## View To Logic

View-to-logic communication must go through explicit entry points.

Allowed first-version requests:

- scene setup request,
- reset/restart request,
- debug pause/resume,
- debug speed setting if implemented at the frontend logic-clock level.

These requests should not call movement, combat, controller, or AbilitySet
internals directly.

Future player control can introduce a `PlayerController` request/command queue,
but that is outside M1/M2 and should not be used by lane creep AI or
`WaveSpawner`.

Not allowed:

- directly setting actor position from a view node,
- directly applying HP damage from a VFX node,
- directly changing cooldown from animation callbacks,
- directly swapping target because a sprite clicked another sprite,
- directly changing a unit controller's behavior mode,
- directly removing logic actors when a death animation ends.

Death animation may outlive the logic actor, but that is frontend lifetime only.
The logic removal event decides when the actor leaves simulation.

## Interpolation

The frontend may interpolate between previous and current snapshots:

```gdscript
_world_view.render_interpolated(alpha)
```

`alpha` is render-only. It must not be fed back into logic systems.

Interpolation can move view nodes smoothly between two authoritative logic
positions, but combat range, attack timing, aggro decisions, and death checks all
use fixed-tick logic state only.

## Tick Clock Boundary

The render-facing scene owns the small logic clock block that consumes elapsed
real time. The clock block advances zero or more fixed ticks according to the
tick model contract, then exposes the latest frames/events to the frontend.

The first version should keep this as private scene code, not as a dedicated
`Dota2SimulationDriver` class. Extraction is allowed later only if several
callers need to share the same clock behavior.

The Procedure should not know about render frames. It receives a fixed
`LOGIC_DT_MS` and advances exactly one logic tick per call.

This means:

- `_process(delta)` is allowed to call `_advance_logic_clock(real_delta_ms)`;
- `_advance_logic_clock(...)` is allowed to call
  `procedure.tick_once(LOGIC_DT_MS)`;
- view nodes are allowed to consume frames/events after advancement;
- view nodes are not allowed to call logic systems directly.

## Acceptance Criteria

- Logic frames use snapshot data, not live actor references.
- Frontend reads frames/events and does not mutate logic state.
- Render interpolation never affects combat decisions.
- Death/removal visual timing is separate from logic lifetime.
- Debug setup/reset/pause inputs use explicit scene-level or Procedure APIs.
- Runtime player command/request queues are future optional work, not M1/M2.
- First frontend exposes rich debug data for actor, intent, movement, Ability,
  tick/catch-up, and recent event state.
- Catch-up warnings belong to the frontend logic clock block, not to view nodes
  or battle systems.
