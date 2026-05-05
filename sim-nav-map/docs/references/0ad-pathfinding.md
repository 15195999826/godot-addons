# 0 A.D. 寻路架构参考

> 来源：
> - 官方源码 [`Pathfinding.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/helpers/Pathfinding.h)
> - 官方源码 [`HierarchicalPathfinder.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/helpers/HierarchicalPathfinder.h)
> - 官方源码 [`CCmpPathfinder.cpp`](https://github.com/0ad/0ad/blob/master/source/simulation2/components/CCmpPathfinder.cpp)
> - Wildfire Games trac ticket [#1756 — Long/Tile Pathfinder Rewrite](https://trac.wildfiregames.com/ticket/1756)
> - ModDB design write-ups: [Pathfinding Saga Continues](https://www.moddb.com/games/0-ad/news/the-pathfinding-saga-continues), [Pathfinding Update 2012](https://www.moddb.com/games/0-ad/news/pathfinding-update-24-january-2012)
> - 维护意图：作为我们 RTS 例子寻路演进的参考蓝本（不是要照搬，是要在做关键决策时知道工业级方案怎么分层）。

---

## 1. 设计目标（为什么三层）

0 A.D. 是开源 RTS（古代/中世纪文明，类 AoE）。寻路要同时满足：

1. **大地图、几百单位** —— 不能每帧全图 A\*。
2. **任意角度移动** —— 单位看起来不能"沿格子走 zig-zag"。
3. **静态阻挡（建筑、地形）+ 动态阻挡（其他单位）混合**。
4. **可达性快速查询** —— "能不能到 X" 比 "怎么到 X" 更频繁。

它没有用单一算法解决全部问题，而是分了**三个独立的 pathfinder**，各自只解决一类问题：

| 层 | 名字 | 解决的问题 | 算法 |
|---|---|---|---|
| 全局可达性 | **Hierarchical Pathfinder** | "A 能到 B 吗？" / "目标不可达时给我最近的可达点" | chunk 内 flood-fill region + region 图上跑连通分量 |
| 长距离路径 | **Long-Range Pathfinder** | "走过去的格子序列" | 在 navcell 网格上跑 A\* + JPS |
| 短距离避让 | **Short-Range Pathfinder** ("Vertex" / POV) | "穿过几个建筑/单位之间的真实角度路径" | 高精度 obstruction edge 上跑 vertex-based 可见性图 |

三个都是**异步队列 + 多线程**处理，主线程只发请求和收 ticket 回调。

---

## 2. 数据结构：navcell vs tile vs obstruction

### 2.1 Navcell

- **navcell = 寻路最小单元**，比地形 tile 小（`NAVCELLS_PER_TERRAIN_TILE = 4`，即 1 tile = 4×4 navcell）。
- `NAVCELL_SIZE = 1`（fixed-point 单位）。
- 每个 navcell 是 **boolean passable / impassable**，按 passability class 存。

```cpp
inline constexpr fixed NAVCELL_SIZE = fixed::FromInt(1);
inline constexpr int NAVCELL_SIZE_LOG2 = 0;
inline constexpr int NAVCELLS_PER_TERRAIN_TILE = TERRAIN_TILE_SIZE / NAVCELL_SIZE_INT;
```

**为什么不直接用 tile？** Tile 太粗（一个 tile 装得下一栋小房子），会导致 "门口可走但 tile 标了 blocking" 的精度损失。Navcell = 4×4 细分，提供"格子化的同时不丢精度"。

### 2.2 Passability Class

```cpp
inline constexpr int PASS_CLASS_BITS = 16;
typedef u16 NavcellData;  // 1 bit per passability class
#define IS_PASSABLE(item, classmask) (((item) & (classmask)) == 0)
#define PASS_CLASS_MASK_FROM_INDEX(id) ((pass_class_t)(1u << id))
```

- 每个 navcell 是一个 16-bit mask，每位代表一个 class（infantry / cavalry / ship / siege / ...）。
- 单位声明自己属于哪个 class，pathfinder 用 `mask & navcell == 0` 判 passable。
- 一格可同时对 infantry 可走、对 ship 不可走，无需多张 grid。

### 2.3 PathfinderPassability（class 定义）

```cpp
class PathfinderPassability {
    pass_class_t m_Mask;
    fixed m_Clearance;        // min distance from static obstructions
    fixed m_MinDepth, m_MaxDepth, m_MaxSlope, m_MinShore, m_MaxShore;
    enum ObstructionHandling { NONE, PATHFINDING, FOUNDATION };
    ObstructionHandling m_Obstructions;
};
```

每个 class 自己声明：
- 能在多深的水里走（`m_MinDepth` / `m_MaxDepth`）。
- 最大坡度（`m_MaxSlope`）。
- 离岸距离（`m_MinShore` / `m_MaxShore`）。
- **`m_Clearance`** —— **单位的"半径"**：rasterize 障碍物时把障碍向外扩 clearance，让长寻路自动处理"大单位过窄缝过不去"。

### 2.4 Obstruction（与 navcell 解耦）

- **静态障碍 = 高精度形状**（square footprint with W/H/orientation, 或 circular with radius），**不是格子化的**。
- 静态障碍**会**被 rasterize 进 navcell grid（供 long-range 用），**同时也**保留高精度形状（供 short-range vertex pathfinder 用）。
- **动态障碍（其他单位）**：navcell grid 完全忽略；只有 short-range pathfinder 在请求时按需读。

> 关键设计：long-range 看 grid（rasterized），short-range 看真实 obstruction edges。两个表示同一份障碍数据，分别服务两类 query。

### 2.5 CLEARANCE_EXTENSION_RADIUS

```cpp
inline constexpr entity_pos_t CLEARANCE_EXTENSION_RADIUS = fixed::FromInt(1);
```

> "make sure the long-range pathfinder is more strict than the short-range one"

Long-range rasterize 时多扩 1，等于 long-range 永远比 short-range 更保守。**这避免了 long-range 给出一条理论可走的路径，short-range 实际过不去**（因为 short-range 看的是真实精度边）。

---

## 3. Long-Range Pathfinder

### 3.1 接口

```cpp
struct LongPathRequest {
    u32 ticket;
    entity_pos_t x0, z0;
    PathGoal goal;
    pass_class_t passClass;
    entity_id_t notify;
};
```

### 3.2 算法

- 在 navcell 网格上跑 A\*（horizontal/vertical 邻接，不走斜对角）。
- 后期加入 **JPS (Jump Point Search)**：在均匀代价的 grid 上跳过中间点，只在"必须转向"的 jump point 入 frontier。开放地图节点数减少 100×+。
- 配合 **Hierarchical** 做"可达性预筛"——A\* 之前先确认 goal 可达，否则 `MakeGoalReachable()` 把目标替换成最近可达 navcell。

### 3.3 PathCost（带 √2）

```cpp
struct PathCost {
    PathCost(u16 hv, u16 d) : data(hv * 65536 + d * 92682) {}  // 92682 ≈ 65536*sqrt(2)
};
```

整数代价里同时记 horiz/vert 步数和 diag 步数，用 `92682/65536` 近似 √2，**完全避免浮点**——这对 deterministic 仿真至关重要。

---

## 4. Short-Range Pathfinder（Vertex / POV）

### 4.1 接口

```cpp
struct ShortPathRequest {
    u32 ticket;
    entity_pos_t x0, z0;
    entity_pos_t clearance, range;
    PathGoal goal;
    pass_class_t passClass;
    bool avoidMovingUnits;        // 关键：动态避让开关
    entity_id_t group, notify;
};
```

### 4.2 算法

- 不在格子上跑——在**真实的 obstruction edges 上**跑可见性图（Points of Visibility）。
- 节点 = 障碍物的角点（按 clearance 外扩后的角）。
- 边 = 任意两个角点之间，若线段不穿其他障碍，则可走。
- 跑 A\* 找最短路径——**任意角度，不沿格子**。

### 4.3 何时用

不是每条路径都跑 short-range。典型流程：

1. UnitMotion 收到 "去 X" 命令。
2. 先发 short-range 请求（小范围 = `range`），看能不能直接走过去。
3. 如果 short-range 失败 → 发 long-range 请求拿粗略 waypoint。
4. 沿 waypoint 走的过程中，每段都用 short-range 解决"动态避让别的单位 + 走真实角度"。

### 4.4 obstruction filter（接战识别）

> "ignores all obstruction shapes that have one of the two control groups equal to the target entity"

—— short-range 跑路时**忽略目标自己的 obstruction**，否则单位贴近目标时会把目标当墙绕开。`group` 字段也用于"同 formation 的兄弟单位互相不算障碍"。

---

## 5. Hierarchical Pathfinder（连通性 / 可达性）

### 5.1 结构

- navcell grid 切成 **96×96 的 chunk**。
- chunk 内：相邻可走 navcell flood-fill 成一个 **region**。
- region 在跨 chunk 边界相邻 → 加一条 edge（**chunk 内不连边** —— 这是关键约束，让 region 图保持稀疏）。
- region 图上做连通分量 → **global region ID**。

### 5.2 用途

- **`IsReachable(A, B)`**：O(1)——比较两点 global region ID。
- **`MakeGoalReachable(goal)`**：goal 不在可达 region → 取 BFS 最近的可达 navcell 替换。
- 给 long-range A\* 当前置：先用 hierarchical 确保 goal 可达，再让 A\* 跑细节。否则 A\* 会把整张地图都遍历完才确认"过不去"。

### 5.3 增量更新

地形 / 建筑改变时只重新 flood-fill 受影响 chunk，再修补 region 图边——不全图重建。

---

## 6. UnitMotion 与 Pathfinder 的协作

```
UnitMotion (entity)
  ├─ ComputePathAsync()  → m_LongPathRequests queue   ─┐
  └─ ComputeShortPathAsync() → m_ShortPathRequests   ─┤
                                                       │
              StartProcessingMoves (每 turn)           │
                  ├─ batch (m_MaxSameTurnMoves cap)    │
                  ├─ TaskManager 分发到 worker 线程   ◄┘
                  └─ 每个 request:
                      ├─ LongPathfinder::ComputePath  (with hierarchical 预筛)
                      └─ VertexPathfinder::ComputeShortPath  (with avoid moving units)

              SendRequestedPaths
                  └─ 给请求 entity 发 CMessagePathResult (按 ticket)
```

关键属性：
- **完全异步**：UnitMotion 永不阻塞主线程等 path。
- **可中断 / 可重发**：单位每 turn 重新算 short-range（动态环境变化），long-range 有效则复用。
- **每 turn 限额 `m_MaxSameTurnMoves`**：一 turn 内能服务的请求数有上限——超出排到下一 turn，避免单 turn 卡死。
- **Worker 线程并行**：多核摊算力。

---

## 7. 局部避让 = short-range pathfinder，不是 steering force

⚠️ 0 A.D. **没有**单独的 separation / boids steering 层。

它的"动态避让"完全由 **short-range pathfinder + `avoidMovingUnits=true`** 实现：每段重新跑 vertex pathfinder，把当前所有移动单位也当成障碍参与可见性图。

这跟 RTS 工业界另一条路线（**RVO / ORCA**：每帧根据邻居速度求半平面交集找新速度）不同。两条路线的取舍：

| | Vertex pathfinder + avoid | RVO / ORCA |
|---|---|---|
| 适合 | 中低单位密度 + 大量静态障碍 | 高密度人群（数千 agent 互相穿插） |
| 计算 | 频繁重新跑 short-range（缓存 path） | 每帧 per-agent 求 LP |
| 视觉 | 路径硬切，转弯角度大；没"擦肩而过"的微调 | 自然 smooth；细粒度 yield |
| 静态障碍 | 一等公民（vertex 上跑） | 需要外挂处理（RVO 本身只管 agent） |
| Determinism | 整数 + 顺序固定 → easy | 浮点 LP，需仔细 → hard |

0 A.D. 选第一条是因为它的瓶颈是"几百单位 + 很多建筑"，而不是"几千农民人挤人"。

---

## 8. 关键设计原则总结

1. **三层职责分离**：可达性 / 全局路径 / 局部精度 —— 每层只解决一类问题，互相不耦合。
2. **数据双表示**：障碍同时存 navcell（rasterized）+ 高精度 shape（vertex），long-range 走前者，short-range 走后者。
3. **Long-range 比 short-range 更保守**（`CLEARANCE_EXTENSION_RADIUS`）—— 永远不会"long 给的路 short 走不通"。
4. **passability 是 16-bit mask**，多类单位共享一张 grid，按位筛选。
5. **clearance 烧进 grid**：rasterize 时按 class 的 clearance 外扩，让 A\* 自动尊重单位半径，不在 query 时算。
6. **整数 + fixed-point**：deterministic simulation 保命。
7. **异步 + worker 多线程**：path 永不阻塞 sim turn。
8. **hierarchical 做"可达性"，不做"路径"**：避免 A\* 在不可达目标上爆炸。
9. **JPS 应用在均匀代价的 navcell grid 上**：开放地图大幅减节点。
10. **动态避让走 short-range pathfinder + group filter**，不是独立 steering。
