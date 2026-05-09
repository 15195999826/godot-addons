# 0AD Lab 稳定帧性能诊断计划

这份文档接替已经完成的 short-path visibility 优化文档。

旧文档已归档到：

```text
docs/archive/2026-05-09-short-path-visibility-optimization.md
```

## 当前判断

当前 0AD lab 的稳定体验已经可以接受。

用户实测里，稳定后 `avg_step_usec` 大约在 `500-600us`，也就是每次
simulation step 约 `0.5-0.6ms`。这不是最终理想值，但不是当前必须立刻
阻断体验的性能问题。

需要注意的是：`avg_step_usec` 是从启动以来累计的平均值。它会把首次启动、
初始寻路、偶发慢帧、稳定运行全部混在一起，所以不适合作为唯一指标。

下一阶段目标不是马上继续大改算法，而是先把“平均值为什么是 0.5-0.6ms”
拆清楚。

## 我想先量什么

### `warm_avg`

跳过开头一小段启动期之后的平均耗时。

用途：判断单位都进入正常运行状态后，simulation step 的真实稳定成本。

### `p95` / `p99`

把所有 frame 耗时从小到大排序：

- `p95`：95% 的 frame 都低于这个值。
- `p99`：99% 的 frame 都低于这个值。

用途：比 `max` 更稳定。`max` 只看最慢一帧，可能是偶发；`p95/p99` 能说明
“大多数时候是不是稳定”。

### `idle_avg`

没有单位在移动、没有新 path request 时的平均耗时。

用途：判断 lab 场景本身、diagnostics、UI/export bookkeeping 的基础成本。

### stage cost

每个 step 里已经有一些阶段耗时，例如：

- path request 处理
- path result 应用
- unit movement
- dynamic obstruction refresh
- push / separation
- diagnostics / pair contact 记录

下一步要把这些阶段做成更容易看的统计，不只在单个 slow frame 里看。

## 为什么要这样量

之前 `19ms` 异常帧不是 short-path visibility 问题，而是同一 tick 里处理了
两个较贵的 long path request。

后来通过 request budget / JPS 等改动，明显降低了这个风险。

现在剩下的问题更像是常驻成本：

- 每 tick 都要刷新动态 unit obstruction。
- 有移动单位时要做 movement / push / separation。
- 为了 debug 和 export，会记录 path decision、step profile、pair contact。

这些东西加起来可能让稳定平均值停在 `0.5-0.6ms`。这可以接受，但如果要继续
优化，应该先知道是哪一块贡献最大。

## 下一步计划

已落地：

- export / exploration summary 都记录：
  `warm_avg_step_usec`、`p95_step_usec`、`p99_step_usec`、
  `idle_avg_step_usec`。
- export / exploration summary 都记录 stage average：
  `stage_avg_usec`、`warm_stage_avg_usec`、`idle_stage_avg_usec`。
- slow frame 和 max frame 都记录 stage classification：
  path request、path result、movement、refresh、push、diagnostics、
  bookkeeping。
- exploration 增加 `0_idle_default_scene`，专门测默认场景空闲成本。

## 2026-05-09 实测数据

### 默认交互场景 export

Headless 实例化真实 frontend，按 `60Hz` 跑 720 step 后调用
`export_debug_log()`。

Export:

```text
C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/Inkmon/zero_ad_rts_lab_steady_state_default_export.json
```

| Metric | Value |
|---|---:|
| `tick_count` | 720 |
| `avg_step_usec` | 355.98 |
| `warm_avg_step_usec` | 263.17 |
| `p95_step_usec` | 762 |
| `p99_step_usec` | 820 |
| `idle_avg_step_usec` | 13.26 |
| `idle_sample_count` | 367 |
| `max_step_usec` | 6705 |
| `max_step_stage` | `path_request` |
| `slow_frame_count` | 0 |
| arrived | `6/6` |

Warm stage average in that export:

| Stage | Avg usec |
|---|---:|
| movement | 172.14 |
| refresh | 38.17 |
| diagnostics | 20.48 |
| push | 17.36 |
| path request | 1.01 |

Interpretation: this 720-step export includes a long idle tail after arrival, so
its warm average drops below the moving steady-state cost. It is useful for
confirming idle/export shape, not for claiming active movement is only `0.26ms`.

### Exploration playthrough

Latest log:

```text
.claude/tmp/0ad-steady-state-exploration.log
```

Selected phases:

| Phase | avg | warm avg | p95 | p99 | idle avg | max | max stage | slow |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| `0_idle_default_scene` | 11.73 | 12.17 | 13 | 54 | 11.73 | 54 | bookkeeping | 0 |
| `1_baseline_open_movement` | 715.10 | 675.29 | 780 | 809 | 0.00 | 6233 | path_request | 0 |
| `4_fully_blocked_path` | 676.46 | 646.35 | 751 | 850 | 0.00 | 7273 | path_request | 0 |
| `9_partial_wall_with_gap` | 648.61 | 615.99 | 726 | 828 | 0.00 | 7068 | path_request | 0 |
| `8_rapid_obstacle_thrash` | 2582.27 | 2572.91 | 4139 | 5362 | 0.00 | 6117 | path_request | 0 |
| `12_progressive_seal_all_paths` | 861.92 | 752.75 | 978 | 3038 | 0.00 | 7160 | path_request | 0 |
| `13_seal_behind_unit` | 352.30 | 12.79 | 15 | 20 | 12.68 | 6993 | path_request | 0 |
| `16_alternating_corridor_seal` | 192.46 | 189.46 | 209 | 287 | 0.00 | 634 | refresh | 0 |

Selected warm stage averages:

| Phase | Dominant steady stage | Movement | Refresh | Push | Diagnostics | Path request |
|---|---|---:|---:|---:|---:|---:|
| `1_baseline_open_movement` | movement | 463.17 | 97.28 | 41.17 | 56.92 | 1.18 |
| `4_fully_blocked_path` | movement | 438.06 | 96.13 | 40.50 | 55.08 | 1.15 |
| `14_gap_close_mid_travel` | movement | 479.51 | 93.60 | 42.05 | 56.09 | 1.09 |
| `16_alternating_corridor_seal` | refresh | 20.03 | 91.37 | 48.87 | 8.68 | 3.22 |

## 当前判断

当前 `0.5-0.6ms` 稳定 avg 可以视为健康基线。

理由：

- 默认交互 export 已能分开看 lifetime avg、warm avg、p95/p99、idle avg。
- 默认 idle cost 只有约 `12us`，说明 lab 空转和 export bookkeeping 不是主成本。
- 正常移动期 exploration 的 warm avg 大多在 `0.61-0.68ms`，p99 通常低于
  `1ms`。
- max frame 主要仍是启动/事件附近的同步 path request batch，但当前最高约
  `6-7ms`，没有形成 `8ms` slow frame；这与之前 `19ms` / `200ms+` 异常不是同一类问题。
- active movement steady cost 主要来自 movement loop 本身，其次才是
  refresh / diagnostics / push；path request 对 steady avg 贡献很低，但仍主导 max frame。

下一轮建议：

1. 不进入 async / 多线程。当前 p95/p99 和 slow-frame 数据不支持把 async 作为
   immediate plan。
2. 不优先优化 path request。它主导 max frame，但没有主导 moving warm avg，也没有
   产生当前 slow frames。
3. 如果要继续压稳定 avg，先看 movement loop 内部实际操作，再看 refresh。
   在用户列出的候选项里，`refresh` 是比 `push` / `diagnostics` 更值得下一轮检查的
   常驻成本。
4. `dynamic blocker thrash` 仍是独立 motion-policy 问题；`8_rapid_obstacle_thrash`
   的 warm avg 仍是 `2.57ms`，不能混称为已经解决。

## 暂时不做什么

- 不先引入 async worker / 多线程。
- 不靠调大 cooldown、缩短 search range、降低碰撞半径来压平均值。
- 不让 long path 把密集动态单位当作全局阻挡。
- 不把 dynamic blocker thrash 混称为已经解决。

## async / 多线程的位置

0 A.D. 有异步 path request 和 worker 处理，但这不是下一步的第一刀。

当前判断是：

- 如果 `p95/p99` 主要被 path request 顶起来，async 才值得进入设计。
- 如果 `avg` 主要来自每 tick 常驻成本，async 不能解决根因。

所以 async / 多线程先作为后续候选方案保留，不进入当前 immediate plan。

## 验收标准

- export 能直接回答：稳定后平均值是多少。
- export 能直接回答：95% / 99% 的 step 是否稳定。
- slow frame 能看出主要耗时阶段。
- 首次启动耗时和稳定运行耗时分开看。
- 当前 `0.5-0.6ms` 稳定 avg 被记录为可接受基线，而不是误判为必须立即修复
  的异常。
