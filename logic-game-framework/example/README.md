# LGF Examples Index

LGF（Logic Game Framework）目前提供两个示例项目，作为框架能力 + 三层架构（core / logic / frontend）的参考实现。新示例放在此目录下，每个示例都对应自己的 README 与 smoke 入口。

| 示例 | 目录 | 节奏 | 坐标系 | 主 smoke |
|---|---|---|---|---|
| **hex-atb-battle** | [hex-atb-battle/](hex-atb-battle/) | 回合制 / ATB 累积 | 离散 HexCoord（UGridMap） | `tests/frontend/smoke_frontend_main.tscn`（demo + replay 链）<br>`tests/battle/smoke_skill_scenarios.tscn`（具体 skill 数值断言） |
| **dota2-auto-battle** | [dota2-auto-battle/](dota2-auto-battle/) | 实时固定 tick (30Hz) / ARAM lane creep auto battle | 连续 `Vector2` + DOTA2 movement adapter（sim-nav `dota2-rts-pathfinding-lab`） | `./tools/run_tests.ps1 dota2autobattle/smoke`（`tests/battle/smoke_lane_wave_engage.tscn` + `tests/frontend/smoke_frontend_main.tscn`）<br>F6: `frontend/scene/dota2_lane_battle.tscn`（M1 垂直切片） |

这些示例都遵循:

- **三层依赖方向**: `core/` ← `logic/` ← `frontend/`，frontend 不被 core/logic 引用
- **WorldGI + Procedure 范式**: `WorldGameplayInstance` 子类持 actor + 系统；战斗是临时 `BattleProcedure`（RefCounted）
- **EventProcessor pre/post 管线**: 给 buff / passive 留 hook 入口，即使 example 暂未挂任何 passive
- **Headless 友好**: smoke 用 `print("SMOKE_TEST_RESULT: PASS|FAIL - <reason>")` + 退出码 0/1 给 CI 解析
- **不修改 LGF core/stdlib 来支撑示例**: 示例缺什么能力时，要么本地写、要么提议升级 core 通用接口

## AttributeSet 边界

每个 example 自持属性配置与产物：`example/<name>/logic/attributes/attributes_config.gd`
（暴露 `const SETS := {...}`），`AttributeSetGeneratorScript` 按此约定自动发现并
生成到同目录 `generated/`——加新 example 无需改 generator。项目级游戏用
`res://logic-game-framework-config/attributes`。set 名决定生成的 class_name
（全局符号），跨 config 必须唯一，generator 生成前做冲突预检。

[attributes/](attributes/) 目录仅承载 generator 演示/自测用的 `Example*` set
（example_hero/tower/derived_demo），不是任何 example 的属性落点，不再往里加 set。

重新生成入口：编辑器菜单 `Tools > LGFramework > 生成属性集`，或 headless
`godot --headless --path . addons/logic-game-framework/scripts/generate_attribute_sets.tscn`。
