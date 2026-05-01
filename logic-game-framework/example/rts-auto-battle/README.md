# RTS Auto Battle Example (M1 / Phase 2 进行中)

LGF 的第二个示例：连续坐标 + 实时 attack_cooldown 节奏的自动战斗，对标 `hex-atb-battle` 的三层结构。

## 与 hex-atb-battle 的差异

| 维度 | hex-atb-battle | rts-auto-battle |
|---|---|---|
| 坐标系 | 离散 HexCoord | 连续 `Vector2`（500×500 px） |
| 节奏 | ATB 累积 → 放技能 | 持续 `attack_cooldown` 实时 tick (30Hz fixed default) |
| 移动 | UGridMap 单格步进 | RtsBattleGrid (ultra-grid-map SQUARE, cell_size=32) + A* + spatial_hash + steering sep/deflection + stuck detection / local repath / abandon_command |
| 兵种 | 6 职业 + 完整技能池 | 2 兵种（melee/ranged）+ basic attack |
| 单位规模 | 6v6（demo）| 4v4（M0/M1 起步） |
| AI | 无状态 AIStrategy | 无状态 RtsAIStrategy + 有状态 RtsUnitController + Activity 链 (P2.1, OpenRA 风) |
| 决定性 | 内置 | RtsRng autoload + light determinism (P1.7); bit-equal replay 完整流式 P2.6+P2.7 待 |

## 目录

| 子目录 | 职责 |
|---|---|
| `core/` | RtsWorldGI / RtsAutoBattleProcedure（连续 tick + movement 三段管线 + 胜负判定）|
| `logic/` | RtsBattleActor (基类) / RtsUnitActor / RtsBuildingActor / activity / ai / controller / movement (spatial_hash + steering) / grid / actions / config |
| `frontend/` | 最简 visualizer（Phase 2 P2.7 接 BattleDirector 流式 events） |
| `tests/` | battle / replay / frontend smoke 入口 |

## 状态

WIP Phase 2 — Phase 1 已完成 9/9 AC; Phase 2 P2.1 + P2.2 + P2.3 完成 (3/8); 详见 `.feature-dev/Progress.md`。
