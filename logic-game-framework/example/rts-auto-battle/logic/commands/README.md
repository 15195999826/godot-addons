# Commands (P2.6)

玩家命令系统 — RTS 战斗中"玩家发起的离散指令"。

## 模块布局

| 文件 | 角色 |
|---|---|
| `rts_player_command.gd` | 命令基类: `tick_stamp` / `team_id` / `apply(procedure, world) -> Dictionary` 钩子 |
| `rts_place_building_command.gd` | 放置建筑命令 (KIND_CRYSTAL_TOWER / KIND_BARRACKS / KIND_ARCHER_TOWER) |
| `rts_move_units_command.gd` | **P3.2** — 玩家移动多单位命令; 走 RtsGroupFormation 拆 target_pos 为 N 个 offset, override_strategy=true 让 strategy.decide 不替换 |
| `rts_player_command_queue.gd` | 命令队列: 按 `tick_stamp` 升序应用; 已应用 (含失败) 进 history |
| `rts_building_placement.gd` | 放置合法性纯校验函数 (build_zone / 地图边界 / cells / 资源) |

## 怎么用

```gdscript
# 起手装配 procedure (M2.1 Phase A — starting_resources 改 Dictionary[String, int])
var left_team_cfg := RtsTeamConfig.create(
    0, "human", {"gold": 200, "wood": 0}, Rect2(50, 50, 400, 200),
)
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

# 战斗结束后读 log; M2.1 Phase A — result.cost 是 Dictionary[String, int]
var log = procedure.get_player_commands_log()
# log[0] = { command: {...}, result: { success: true, actor_id: "...", footprint: [...], cost: {"gold": 100} }, applied_tick: 30 }
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

## P3.2 — RtsMoveUnitsCommand 用法

```gdscript
# 玩家选中 N 个 team 0 单位, 右键远端 → 单条命令 N 个 unit 排成方阵走过去
procedure.enqueue_player_command(RtsMoveUnitsCommand.new(
    current_tick,
    0,                              # team_id
    [unit_id_1, unit_id_2, ...],    # 选中顺序; offset 按此顺序展开
    Vector2(550, 250),              # 目标 (formation 几何中心)
))
```

apply 流程:
1. 过滤 team_id 不匹配 / 已死的 → 进 rejected_ids
2. 调 `RtsGroupFormation.assign_offsets(N)` 拿 N 个相对 target 的 offset
3. 对每 unit: `controller.set_activity_chain(RtsMoveToActivity.new(target + offset[i]), override_strategy=true)`
4. 返回 `{ success, accepted_ids, rejected_ids, target_pos, offsets_count }`

`override_strategy=true` 让 strategy.decide 不在玩家命令链跑完前替换 — 即使附近有敌人, 也不会被
AI auto-attack 抢走。链跑完 (current_activity == null) 自动清 flag, 让 AI 接管下个 tick。
