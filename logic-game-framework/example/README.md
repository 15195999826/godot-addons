# LGF Examples Index

LGF（Logic Game Framework）目前提供两个示例项目，作为框架能力 + 三层架构（core / logic / frontend）的参考实现。新示例放在此目录下，每个示例都对应自己的 README 与 smoke 入口。

| 示例 | 目录 | 节奏 | 坐标系 | 主 smoke |
|---|---|---|---|---|
| **hex-atb-battle** | [hex-atb-battle/](hex-atb-battle/) | 回合制 / ATB 累积 | 离散 HexCoord（UGridMap） | `tests/frontend/smoke_frontend_main.tscn`（demo + replay 链）<br>`tests/battle/smoke_skill_scenarios.tscn`（具体 skill 数值断言） |
| **rts-auto-battle** | [rts-auto-battle/](rts-auto-battle/) | 实时连续 tick / `attack_cooldown` | 连续 `Vector2`（500×500 px + NavigationServer2D） | `tests/battle/smoke_rts_auto_battle.tscn`（4v4 自动战斗 + 兵种行为断言） |

两个示例都遵循:

- **三层依赖方向**: `core/` ← `logic/` ← `frontend/`，frontend 不被 core/logic 引用
- **WorldGI + Procedure 范式**: `WorldGameplayInstance` 子类持 actor + 系统；战斗是临时 `BattleProcedure`（RefCounted）
- **EventProcessor pre/post 管线**: 给 buff / passive 留 hook 入口，即使 example 暂未挂任何 passive
- **Headless 友好**: smoke 用 `print("SMOKE_TEST_RESULT: PASS|FAIL - <reason>")` + 退出码 0/1 给 CI 解析
- **不修改 LGF core/stdlib 来支撑示例**: 示例缺什么能力时，要么本地写、要么提议升级 core 通用接口

## 共享 attribute_set

[attributes/](attributes/) 目录提供 LGF 自带的 `BaseGeneratedAttributeSet` 子类（hex_battle_*、example_hero/tower/derived_demo），由 `AttributeSetGeneratorScript` 从 `attributes_config.gd` 自动生成。RTS 例子选择**直接 extends `BaseGeneratedAttributeSet`** 自管 `_raw.apply_config`，避免动这块共享代码，彻底解耦。
