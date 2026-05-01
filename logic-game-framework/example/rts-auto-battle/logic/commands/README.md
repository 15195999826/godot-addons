# Commands (P2.6)

玩家命令系统 — RTS 战斗中"玩家发起的离散指令"。

## 模块布局

| 文件 | 角色 |
|---|---|
| `rts_player_command.gd` | 命令基类: `tick_stamp` / `team_id` / `apply(procedure, world) -> Dictionary` 钩子 |
| `rts_place_building_command.gd` | 放置建筑命令 (KIND_CRYSTAL_TOWER / KIND_BARRACKS / KIND_ARCHER_TOWER) |
| `rts_player_command_queue.gd` | 命令队列: 按 `tick_stamp` 升序应用; 已应用 (含失败) 进 history |
| `rts_building_placement.gd` | 放置合法性纯校验函数 (build_zone / 地图边界 / cells / 资源) |

## 怎么用

```gdscript
# 起手装配 procedure
var left_team_cfg := RtsTeamConfig.create(0, "human", 200, Rect2(50, 50, 400, 200))
procedure = world.start_rts_battle(..., {
    "team_configs": { 0: left_team_cfg, 1: right_team_cfg },
    ...
})

# 玩家在 tick 30 放兵营
procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
    30, 0, RtsBuildingConfig.KIND_BARRACKS, Vector2(100, 230),
))

# tick 推进时 procedure step 1.5 自动 apply_due
for i in range(...):
    procedure.tick_once()

# 战斗结束后读 log
var log = procedure.get_player_commands_log()
# log[0] = { command: {...}, result: { success: true, actor_id: "...", footprint: [...], cost: 100 }, applied_tick: 30 }
```

## 添加新命令类型

1. 新建 `rts_<kind>_command.gd` 继承 `RtsPlayerCommand`
2. override `apply(procedure, world) -> Dictionary` (`{ success, reason, ... }`)
3. override `command_type() -> String` 返回唯一 type 字符串
4. override `serialize() -> Dictionary` 加自己的特化字段

## 与 P2.5 production 系统的关系

`PlaceBuildingCommand` 通过 `procedure.add_unit_to_team` 把新建筑加入 team 列表后,
production_system 会在下个 tick 自动开始累积 `_production_progress_ms`。
不需要额外 wiring — 工厂 + production_system + add_unit_to_team 已成闭环。
