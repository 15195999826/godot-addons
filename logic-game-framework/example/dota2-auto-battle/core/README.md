# Core (M1 implemented)

> M1 已落地：`dota2_world_gameplay_instance.gd` / `dota2_auto_battle_procedure.gd`
> / `dota2_logic_frame.gd` / `events/dota2_battle_events.gd`。变更见
> [../CHANGELOG.md](../CHANGELOG.md)。下列为原始规划，保留作设计追溯。

Planned contents:

- `dota2_world_gameplay_instance.gd`
- `dota2_auto_battle_procedure.gd`
- `events/dota2_battle_events.gd`

Core owns the battle world, fixed tick procedure, and shared events. It should not
own frontend rendering or DOTA2-specific movement policy internals.

Tick execution is single-threaded. The first frontend scene owns the small
accumulator/catch-up clock block; the Procedure owns exactly one fixed logic
tick per call. Any catch-up or accumulator debt drop must be logged as a
warning. Do not introduce a standalone simulation-driver class until more than
one runtime path needs to share that clock behavior.
