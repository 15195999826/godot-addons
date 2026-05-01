# buildings/ — RTS 建筑工厂(Phase 2 填)

Phase 1 此目录仅占位; Phase 2 P2.5 在此填充工厂方法与具体建筑配置。

## 计划文件(Phase 2 P2.5)

| 文件 | 职责 |
|---|---|
| `rts_buildings.gd` | 工厂入口: `RtsBuildings.create_crystal_tower()` / `create_barracks()` 等 |
| `rts_building_kind_config.gd` | 建筑数值表(类比 `RtsUnitClassConfig`): max_hp / footprint_cells / production_recipe |

## 决策来源

- architecture-baseline.md §4 (子类家族, 决策 E)
- 照抄 hex `environment/` 模式: `EnvironmentActor + environment_kind: String + CollisionProfile` 数据驱动。

## Phase 1 行为

调方暂不创建 building 实例(没有玩家命令 / spawn 入口); RtsBuildingActor 仅作 Actor 注册时的类型骨架。
