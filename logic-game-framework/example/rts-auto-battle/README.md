# RTS Auto Battle Example (M0)

LGF 的第二个示例：连续坐标 + 实时 attack_cooldown 节奏的自动战斗，对标 `hex-atb-battle` 的三层结构。

## 与 hex-atb-battle 的差异

| 维度 | hex-atb-battle | rts-auto-battle |
|---|---|---|
| 坐标系 | 离散 HexCoord | 连续 `Vector2`（500×500 px） |
| 节奏 | ATB 累积 → 放技能 | 持续 `attack_cooldown` 实时 tick |
| 移动 | UGridMap 单格步进 | NavigationServer2D + NavigationAgent2D |
| 兵种 | 6 职业 + 完整技能池 | 2 兵种（melee/ranged）+ basic attack |
| 单位规模 | 6v6（demo）| 4v4（M0 起步） |

## 目录

| 子目录 | 职责 |
|---|---|
| `core/` | RtsWorldGI / RtsAutoBattleProcedure（连续 tick + 胜负判定）|
| `logic/` | RtsBattleActor / RtsCharacterActor / AI / actions / config |
| `frontend/` | 最简 visualizer（M0.8 之后） |
| `tests/` | smoke 入口（M0.7 之后） |

## 状态

WIP M0 —— 见 `.feature-dev/Progress.md`。
