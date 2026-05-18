# Controllers (M1 implemented)

> M1 已落地：`dota2_unit_controller.gd` / `dota2_lane_creep_controller.gd` /
> `dota2_decision_result.gd` / `dota2_intent.gd` / `dota2_intent_step_result.gd`
> / `dota2_intent_status.gd`。变更见 [../../CHANGELOG.md](../../CHANGELOG.md)。
> 下列为原始规划，保留作设计追溯。

Planned contents:

- `Dota2UnitController`: per-unit runtime behavior owner.
- `Dota2LaneCreepController`: first concrete controller for lane march, aggro,
  chase, attack, and return-to-lane behavior.
- `Dota2DecisionResult`: decision output used to create, keep, interrupt, or
  clear the current intent.
- `Dota2Intent`: persistent current intent selected by controller decision.
- `Dota2IntentStepResult`: per-tick execution result returned by systems.
- `Dota2IntentStatus`: `RUNNING`, `COMPLETED`, `FAILED`, or `INTERRUPTED`.
- small controller state helpers, such as `last_decision_result` and
  `next_decision_tick`.

Controllers read world/actor state and decide only when the current intent needs
to be created, replaced, completed, failed, interrupted, or reconsidered.
Systems advance the persistent current intent every fixed tick and report facts
back through `Dota2IntentStepResult`. Controllers own the final lifecycle
transition: keep, complete, fail, interrupt, or replace.

Controllers do not directly mutate position, HP, cooldowns, death state, or
Ability execution state.

No command/order layer is planned for M1/M2. Player/debug command or request
objects can be introduced later when there is a real player-control or replay
requirement.
