# logic — Game rules

RTS 自动战斗的游戏规则层：Actor / Activity / AI / Controller / Movement / Action / config。仅依赖 LGF core + rts/core，不引用 frontend。

## 子目录速查

| 子目录 | 职责 |
|---|---|
| `activity/` | RtsActivity 链 (OpenRA 风, P2.1): idle / move_to / attack / attack_move + supervisor advance driver |
| `ai/` | RtsAIStrategy 无状态 (P2.1: decide 返回 RtsActivity) + RtsBasicAttackStrategy + Factory |
| `controller/` | RtsUnitController 有状态 (P2.1: current_activity + reconcile + advance; P2.3: abandon_command API) |
| `movement/` | RtsSpatialHash (P2.2 桶索引) + RtsUnitSteering (P2.2 sep+deflection) + RtsStuckDetector (P2.3 local repath + abandon 升级) + RtsMinimalPushOut (P1.2 自验证算法, procedure 不再调用) |
| `grid/` | RtsBattleGrid (wrap ultra-grid-map SQUARE) + RtsPathfinding (A*) |
| `components/` | RtsNavAgent (P2.2 拆 movement: compute_desired_velocity + integrate + tick backwards-compat) |
| `actions/` | RtsBasicAttackAction (extends Action.BaseAction, P1.4) |
| `buildings/` | 占位, P2.5 填工厂 |
| `config/` | UnitClassConfig (melee/ranged stats) + UnitAttributeSet (hp/atk/def/move_speed/attack_speed/attack_range) |
| `logger/` | RtsBattleLogger (smoke 用事件捕获器) |

## Phase 2 当前状态

P2.1 + P2.2 + P2.3 完成 (Activity 系统 + Spatial Hash + Steering + Stuck Recovery); P2.4-P2.8 待启动。
