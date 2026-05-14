# tests/diagnostics — dump 工具

跟 `tests/battle/`、`tests/frontend/` 等 PASS/FAIL smoke 不同,这里的入口是**数据 dump 工具** — 跑完打印 trace / 统计数据让人读,不出 PASS/FAIL 退出码,不进 `test_groups.json`,不进 CI gate。

## 用途

记录某个特定场景下系统的可观测行为(轨迹 / overlap / jitter / perf 计数等),作为基线快照。后续 milestone 推进时复测同一入口,对比数据看是否有改善 / 退化。

## 跑法

直接 `godot --headless --path . <scene.tscn>` 或编辑器 F6。退出码恒为 0(只要不崩),数据在 stdout。

## 当前入口

| 入口 | 测什么 | M5 baseline 数据 |
|---|---|---|
| `trace_pathfinding_8units.tscn` | 8 melee 走到 3 barracks 中央凹槽的视觉穿模 / 互推现象 | 389 overlap events, max=9.45 px (~39% diameter), 终点 0 events |
| `diag_pathfinding_trace.tscn` | 编队走向紧贴建筑后侧目标时的路径 / footprint / blocking cell trace | 按需手跑 |
| `diag_demo_frontend_trace.tscn` | 复刻 demo_rts_frontend AI vs AI,输出单位徘徊 / path change / cluster jam trace | 按需手跑 |
| `diag_castle_attack_trace.tscn` | melee 攻击 crystal_tower 时的 distance / path / attack trace | 按需手跑 |
| `perf_hierarchical_realistic.tscn` | HierarchicalPathfinder.recompute 在 96² + 16 building 块 demo 规模下 perf(从 smoke_hierarchical_perf 移过来,M4c gate 决策已 CANCEL 改 info-only) | M4 末态 single-run p99=28 ms;M5 末态 5x parallel p99=31 ms |
| `perf_hierarchical_synthetic.tscn` | HierarchicalPathfinder.recompute 在 192/384/768² + 10% scattered obstacle 下 perf | 768² × 100 iter ≈ 24-47s GDScript 算法成本(单跑 30-90s);"未来预警面板" |

## 何时新增

- 用户跑 demo 报告"看着不对"但又不是硬 bug(穿模 / 抖动 / 微卡顿)
- 算法改造前需要捕获基线行为以便后续对比
- 不要把这里当 smoke 写 — PASS/FAIL 断言的入口去 `tests/battle/`
