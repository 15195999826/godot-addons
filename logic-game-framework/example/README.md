# LGF Examples Index

LGF（Logic Game Framework）目前提供三个示例项目，作为框架能力 + 三层架构（core / logic / frontend）的参考实现。新示例放在此目录下，每个示例都对应自己的 README 与 smoke 入口。

| 示例 | 目录 | 节奏 | 坐标系 | 主 smoke |
|---|---|---|---|---|
| **hex-atb-battle** | [hex-atb-battle/](hex-atb-battle/) | 回合制 / ATB 累积 | 离散 HexCoord（UGridMap） | `tests/frontend/smoke_frontend_main.tscn`（demo + replay 链）<br>`tests/battle/smoke_skill_scenarios.tscn`（具体 skill 数值断言） |
| **rts-auto-battle** | [rts-auto-battle/](rts-auto-battle/) | 实时连续 tick / `attack_cooldown` | 连续 `Vector2`（500×500 px + NavigationServer2D） | `tests/battle/smoke_rts_auto_battle.tscn`（4v4 自动战斗 + 兵种行为断言） |
| **dota2-auto-battle** | [dota2-auto-battle/](dota2-auto-battle/) | 实时固定 tick / lane creep auto battle（规划中） | 连续 `Vector2` + DOTA2 movement adapter（规划中） | 暂未注册；见 `docs/development-plan.md` |

这些示例都遵循:

- **三层依赖方向**: `core/` ← `logic/` ← `frontend/`，frontend 不被 core/logic 引用
- **WorldGI + Procedure 范式**: `WorldGameplayInstance` 子类持 actor + 系统；战斗是临时 `BattleProcedure`（RefCounted）
- **EventProcessor pre/post 管线**: 给 buff / passive 留 hook 入口，即使 example 暂未挂任何 passive
- **Headless 友好**: smoke 用 `print("SMOKE_TEST_RESULT: PASS|FAIL - <reason>")` + 退出码 0/1 给 CI 解析
- **不修改 LGF core/stdlib 来支撑示例**: 示例缺什么能力时，要么本地写、要么提议升级 core 通用接口

## AttributeSet 边界

[attributes/](attributes/) 目录提供早期示例共用的 `BaseGeneratedAttributeSet`
子类（hex_battle_*、example_hero/tower/derived_demo），由
`AttributeSetGeneratorScript` 从 `attributes_config.gd` 自动生成。

这个目录现在应视为 legacy/shared demo 区域，而不是新 example 的理想属性
落点。多 example 并行后，把每个项目的属性 schema 都塞进这个共享 config 会造成
不必要耦合和生成产物冲突；但在 generator 尚未支持 per-example output 前，个别
新 example 可以把它作为明确记录的临时债务使用。

新示例应优先拥有自己的 AttributeSet 边界：

- 项目级游戏可用 `res://logic-game-framework-config/attributes`；
- example 级游戏长期应使用 example-local config/output，或在 generator 支持前像
  `rts-auto-battle` 一样直接 extends `BaseGeneratedAttributeSet` 自管
  `_raw.apply_config`；
- `dota2-auto-battle` 如果 M1 暂时使用共享
  `example/attributes/attributes_config.gd`，必须使用清晰的 DOTA2 前缀/命名空间，
  不改变现有 hex/rts 语义，并在本 example 文档里标记为待迁出的技术债。
