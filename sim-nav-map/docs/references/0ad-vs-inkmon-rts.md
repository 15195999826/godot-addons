# 我们的 RTS 寻路 vs 0 A.D. 架构 — 差距分析

> 配套文档：[`0ad-pathfinding.md`](./0ad-pathfinding.md)
> 范围：截至 M2.2，针对 `addons/logic-game-framework/example/rts-auto-battle/logic/{grid, components, movement}/` 下的实现。
> 目的：把"我们目前在哪 / 0 A.D. 在哪 / 缺哪些层会导致什么症状"摆清楚，给后续 phase 决策当依据。**不是行动项**——是诊断。

---

## 0. 一句话对比

> 0 A.D. 是 **3 层 pathfinder（hierarchical / long-range / short-range）+ 多 passability class + clearance + 整数 fixed-point + 异步 worker**。
>
> 我们目前是 **1 层 A\*（在固定 cell grid 上，单 layer 区分 GROUND/AIR）+ separation force + stuck detector**，没有 hierarchical、没有 short-range vertex pathfinder、没有 clearance、没有 group filter、不是异步。

我们走的更接近 **Warcraft 3 / 早期 RTS** 的路线（grid A\* + steering），不是 0 A.D. 的工业级三层架构。这不是错——但**少哪些层就会有哪些症状**。下面逐层对照。

---

## 1. 数据结构对比

| 维度 | 0 A.D. | 我们的 RTS | 差距 |
|---|---|---|---|
| 寻路最小单元 | navcell（4×4 / tile） | cell（`cell_size = 32 px`，与单位 `collision_radius = 14` 比是 ~2.3 倍）| 我们的格子**比单位还大**——精度损失明显 |
| 数据类型 | `NavcellData = u16` bitmask | `bool is_blocking` per cell + `MovementLayer` enum | 没有 multi-class，单位类型扩展时只能加分支 |
| 静态障碍存法 | 双表示：rasterize 进 navcell + 保留高精度 shape | 只 rasterize 进 cell（`place_building` → `set_tile_blocking`）| **没有高精度 shape**——后续无法做 vertex pathfinder |
| 动态障碍（单位）| navcell 不写，short-range 按需读 | grid 不写（`register_actor` 只更新反向索引）| 方向一致，但没有"按需读 path"那一步——直接交给 separation 解决 |
| Clearance | 每 class 自带 `m_Clearance`，rasterize 时外扩 | **无** —— grid 标 blocking 是建筑 footprint 的精确格 | 大单位过窄缝可能"A\* 算出来能过、实际卡进去" |
| Passability class | 16-bit mask（infantry/ship/siege/...）| `MovementLayer.Layer.GROUND/AIR` 二选一 | 加新移动类型（如水陆两栖、攻城）需要硬扩 enum + 写多个 callback |
| 数值类型 | fixed-point 整数 | `Vector2` 浮点 + `move_speed: float` | 浮点 cross-platform 一致性靠测试，0 A.D. 直接绕过这个问题 |

**症状映射**：
- `cell_size > 2 * collision_radius` 直接导致**"中心走线过近建筑边角"**——A\* 给的 cell 中心连线可能离建筑只有 4 px，单位贴边走时撞 footprint。
- 没 clearance → 寻路完全不知道单位"占地"，只在 steering 阶段才发现挤不过去 → stuck detector 兜底。

---

## 2. 三层 pathfinder vs 我们的单层

| 层 | 0 A.D. | 我们 |
|---|---|---|
| **可达性（hierarchical）** | chunk 96×96 + region flood-fill + global region ID。`IsReachable` O(1)，`MakeGoalReachable` 给最近可达点 | **完全没有** |
| **长距离 A\***（grid） | navcell 上 A\* + JPS，hierarchical 预筛保证 goal 可达 | `RtsPathfinding.find_path` 每次 `set_target` 都跑全图 A\*；不可达时直接返回空数组让 nav 站住 |
| **短距离精度 / 动态避让**（vertex / POV）| 真实 obstruction edge 上跑可见性图，`avoidMovingUnits=true` 时把单位也当障碍 | **完全没有**——动态避让靠 `RtsUnitSteering` separation force + deflection |

**症状映射**：

1. **目标不可达时表现糟糕**
   - 0 A.D.：`MakeGoalReachable` 替换成最近可达点，单位走过去停下。
   - 我们：`find_path` 返回 `[]` → nav 持空 path → `is_arrived` 返回 true → activity 以为"到了"，单位**站在原地不动**也不报错。
   - **`scenario_pathfind_around_building` 应该会暴露**：玩家点击建筑内部一个 cell 当目标，单位直接放弃。

2. **路径全是 cell 中心连线，转弯硬**
   - 0 A.D. short-range 在 vertex 上跑，路径是任意角度——绕建筑角时贴边走。
   - 我们 waypoint = cell 中心，单位走"L 形 zig-zag"——视觉差，离障碍距离也不一致。

3. **多单位挤窄道时塞死**
   - 0 A.D. short-range 看见前面有移动单位（`avoidMovingUnits`）→ 算一条绕过它的真路径。
   - 我们：A\* 跑完后路径就固定了，路径上有别的单位 → 只能靠 separation push-out + stuck detector 救场。挤一团时常见的症状是**前排卡门、后排无限 sep 推不动**。

4. **大单位过窄缝**
   - 0 A.D. clearance 烧进 grid，A\* 自动绕开过不去的窄缝。
   - 我们没有 clearance，A\* 觉得"两个 1×1 cell 连通就能过"，实际 28 px 单位过 32 px 缝隙左右只剩 2 px——一定卡。

---

## 3. UnitMotion 流程对比

### 0 A.D.

```
UnitMotion 收命令
  ↓ ComputeShortPathAsync(range=small)        ← 先试短程
  ↓ 失败 → ComputePathAsync (long-range)      ← 拿粗略 waypoint
  ↓ 沿 waypoint 走，每段再发 ComputeShortPathAsync(avoidMovingUnits)
  ↓ 收到 CMessagePathResult 才更新自己的 waypoint
（异步，worker 线程，每 turn 限额）
```

### 我们

```
Activity.tick(dt)
  ↓ agent.set_target(target_world_pos)        ← 同步！
  ↓   → RtsPathfinding.find_path 立刻跑 A*
  ↓   → 写入 _path
  ↓ procedure 主循环：
  ↓   compute_desired_velocity (waypoint 方向 × move_speed)
  ↓   RtsUnitSteering.apply  (separation + deflection 改写 velocity)
  ↓   integrate (position += velocity * dt)
  ↓ agent 整合 stuck_detector 检测"想动但动不了"
（同步，单线程，每帧；replay 可重放）
```

**差异点**：

| | 0 A.D. | 我们 |
|---|---|---|
| 异步 | ✅ 永不阻塞 sim | ❌ A\* 在 set_target 同步跑——大地图重定向可能 spike |
| 限流 | ✅ `m_MaxSameTurnMoves` | ❌ 无——重定向风暴时 N 个单位同帧跑 N 次 A\* |
| 重新算 path 频率 | ✅ 每段 short-range 都重算（应对动态环境）| ❌ A\* 一跑定终身，除非 stuck/idle 重新 set_target |
| 并行 | ✅ worker 线程 | ❌ 单线程 |
| 回放友好 | 需要专门处理 | ✅ 同步顺序固定，天然 deterministic（M2.7 已验证 bit-identical）|

我们换异步是要付 determinism + replay 的代价，**当前阶段保持同步是合理的取舍**——但要清楚同步的代价就是"大地图大量单位时单帧抖动"。

---

## 4. 局部避让方案对比

| | 0 A.D. (vertex pathfinder + group filter) | RVO / ORCA (业界另一支) | 我们 (separation + deflection) |
|---|---|---|---|
| 算法本质 | 重新跑短程 path，单位当障碍 | 邻居速度求半平面交集 → 新速度 | 邻居距离求斥力 → 修改 velocity |
| 静态障碍 | 一等公民 | 需外挂 | 寻路阶段已绕开 |
| 视觉 | 转弯硬 | 自然 smooth | 中等——dot 阈值控的 deflection 会触发硬偏，没触发时会贴脸推 |
| 适合密度 | 中低 | 高密度人群 | 中低 |
| Determinism | 难 | 难 | ✅ 我们已做（spatial_hash sort + actor_id parity） |

**我们的方案的内在缺陷**（不是 bug，是方案天花板）：

1. **separation 是"瞬时局部 force"，不预测**——A 朝 B 飞、B 也朝 A 飞，要等真正 overlap 才推；overlap 那一瞬可能已经穿过对方半个 body。`SEPARATION_BUFFER = 0.0` 是为了不破坏接战，代价就是没预防性避让。
2. **deflection 角度固定 28°**——窄道里两个单位都偏 28° 都不够；3 个以上单位互相 deflect 容易陷入"打转 + 抖动"的稳态。
3. **`MAX_SEP_FRACTION = 0.7` 是双刃剑**——cap 高了后排被反推不动，cap 低了 cluster 中心永远穿模。
4. **没有 group / formation 概念**——同一队 5 个单位走同一条路，互相 sep 把队形挤散。0 A.D. `group` 字段同队互不算障碍，我们没有这个豁免。
5. **建筑 footprint 在 grid 标 blocking 但 steering 不读**——单位被 sep 推到 footprint 内，需要 push-out 兜底。push_out smoke 的存在就是这个症状。

---

## 5. 我们独有的层（0 A.D. 没有的）

| 层 | 我们 | 为什么 0 A.D. 不需要 |
|---|---|---|
| `RtsStuckDetector` | 检测"has_target 但 N 帧没移动"→ 重新 set_target | short-range 每段重算就自然不会 stuck |
| `_actor_footprint` 反向索引 | cell → set<actor_id> 给邻域查询 | 0 A.D. 用专门的 spatial query 系统，不和 grid 耦合 |
| `RtsSpatialHash` | 用于 steering 邻居查 | short-range pathfinder 自带 obstruction lookup |

> 这些不是冗余——是因为缺少 short-range 层不得不搭的"安全网"。

---

## 6. 症状 → 根因映射（你说"全是问题"的可能落点）

按 0 A.D. 的分层视角看我们最可能出哪些问题：

| 症状 | 最可能根因 | 0 A.D. 怎么解 |
|---|---|---|
| 单位在建筑墙角抖 | A\* 路径 = cell 中心连线，转角离 footprint < `collision_radius` | short-range vertex 在外扩 clearance 的角点上跑 |
| 多单位走同一条路堵死 | 单层 A\* + 仅 separation；同队没 group filter | short-range `avoidMovingUnits` + group 同队豁免 |
| 单位在不可达目标前站住 | `find_path` 返回空 array，nav 静默放弃 | hierarchical `MakeGoalReachable` 替换成最近可达点 |
| 飞行单位被绕了远路 | 不会——我们 AIR 走 `_direct_path` | 0 A.D. 飞行 class 自己的 navcell 没那些 obstruction |
| 路径穿过建筑 | 大概率不会——`is_passable_for_layer(GROUND)` 看 `is_blocking` | 同 |
| 大单位卡窄缝 | 没 clearance，A\* 觉得能过 | clearance 烧进 grid，A\* 自动避开 |
| 玩家点 hard-to-reach 目标，N 个单位同帧重定向，帧抖 | 同步 A\* + 无限流 | 异步 + `m_MaxSameTurnMoves` 节流 |
| 接战时被 sep 推开破坏接战 | sep_radius = 2r 没 buffer 是为防这个，但 cluster 多人时仍可能 | 0 A.D. group filter + vertex 路径直接绕 |
| 单位永久重叠在目标上 | sep 应用全单位是为防这个 | 同上 |

---

## 7. 演进思路（不行动，仅列优先级感）

**如果未来要补层**，按 ROI 排序大概是：

1. **`MakeGoalReachable` 等价物**（最便宜 / 收益最大）——A\* 失败时往最近可达 cell 走，不要静默站住。不需要 hierarchical，BFS 半径有限即可。
2. **路径 string-pulling / funnel**（中等成本 / 视觉收益大）——把 A\* 给的 cell-中心 waypoint 后处理：能直线相连的相邻 waypoint 合并，转弯贴障碍角。这能消掉一大半"L 形 zig-zag"和"贴墙角抖"。
3. **Group / formation filter**（中等成本 / 玩家命令收益大）——同 player command 出来的一组单位互相不算 sep 邻居（或弱化），队形不散。
4. **Clearance**（结构性改动 / 大单位时收益大）——rasterize 时按 unit_radius 外扩。我们目前所有单位 `collision_radius` 接近 → 一份 grid 即可；以后出大单位（攻城车）时再扩到 multi-grid。
5. **Hierarchical 可达性**（大成本 / 仅大地图收益）——M2.x 当前地图够小，不优先。
6. **Vertex / short-range pathfinder**（最大成本 / 最大视觉收益）——彻底替换"separation 兜底"路线。是否做取决于游戏感最终对"绕物精度"的需求。

— **当前 M2.2 收口阶段不动，先把症状穷举出来再决定哪一档先做。**

---

## 8. 再看一眼当前实现的"已经对了"的地方

为了不被对比框架带跑——我们这套有几处其实跟工业方案路线一致：

- ✅ **建筑写 grid，单位不写 grid**（WC3 风）→ 和 0 A.D. "navcell 忽略动态障碍" 一致。
- ✅ **AIR layer 直接 direct path 跳过 A\***→ 等价于 0 A.D. 飞行 class 有自己的 navcell（没静态障碍）。
- ✅ **Separation 用 sorted spatial_hash + actor_id parity 决定 deflection 方向**→ replay deterministic，是必须做对的细节，我们做了。
- ✅ **位置计算拆 `compute_desired_velocity` / `integrate` 两步**→ 给 steering 留出"在中间改 velocity"的钩子，是和 0 A.D. UnitMotion 解耦思路一致的清晰分层。
- ✅ **A\* 起点 always allowed**（被推进 building 也能走出来）→ 0 A.D. 类似 fallback。

—— 不是"全错"。是"少了几个明确的层，那几个层负责的症状必然会显现"。
