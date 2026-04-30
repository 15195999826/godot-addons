# core — WorldGI + Procedure

RTS 自动战斗的"框架特化"层：纯仿真，不依赖 frontend / 视觉。

- `rts_world_gameplay_instance.gd` extends `WorldGameplayInstance`
- `rts_auto_battle_procedure.gd` extends `BattleProcedure`（连续 tick + cooldown 推进 + `_check_battle_end`）

WIP M0。
