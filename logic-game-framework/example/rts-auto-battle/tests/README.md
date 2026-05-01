# tests — Smoke entries

| 目录 | 入口 | 用途 |
|---|---|---|
| `battle/` | `smoke_rts_auto_battle.tscn` | 端到端 4v4 acceptance gate (left_win, melee_max_dist=24, ranged_max_dist≈123) |
| `battle/` | `smoke_skeleton.tscn` | 兵种 stats / cooldown / procedure 收尾 |
| `battle/` | `smoke_navigation.tscn` + `smoke_grid_pathfinding.tscn` | 单位绕障 (grid + A*) |
| `battle/` | `smoke_ai.tscn` + `smoke_attack.tscn` | 1v1 接敌 / Action.BaseAction 三段管线 |
| `battle/` | `smoke_minimal_push_out.tscn` | RtsMinimalPushOut.resolve 静态算法自验证 (procedure 不再调用) |
| `battle/` | `smoke_activity_chain.tscn` (P2.1) | RtsActivity primitive 链顺序 + cancel 传播 + nav cleanup |
| `battle/` | `smoke_steering.tscn` (P2.2) | 8 单位 converging 验证 spatial_hash + steering 散开 (无 pair < 2r-0.5) |
| `battle/` | `smoke_stuck_recovery.tscn` (P2.3) | 3 单位塞中央障碍内, 验证 ≥ 2 abandon_command 降级为 Idle (drift < 5px) |
| `replay/` | `smoke_determinism.tscn` (P1.7) | 同 RtsRng seed 跑 2 次 → 同 winner + 同 ticks (bit-equal, P2.3 后 tick_diff=0) |
| `frontend/` | `smoke_frontend_main.tscn` | 8 visualizer 冒烟 (编辑器 F6 看可视化) |

跑法：`godot --headless --path . <scene.tscn> > /tmp/<name>.txt 2>&1`，然后读文件末尾。退出码 0 = PASS；smoke 输出 `SMOKE_TEST_RESULT: PASS|FAIL - <reason>`。

不要用 pipe (`| grep`)：Windows Git Bash + Godot ObjectDB cleanup 会假卡死 2-3 分钟。
