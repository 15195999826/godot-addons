# sim-nav-map core 对照 0 A.D. 源码 Review（2026-07-02）

> task-queue 线 1a 产出。范围：`core/ model/ obstruction/ pathfinding/`（~4400 行 GDScript）对照
> `docs/references/0ad-source/source/simulation2/` 的 helpers（Grid / Pathfinding / Rasterize /
> LongPathfinder / VertexPathfinder / HierarchicalPathfinder / PathGoal / PriorityQueue / Spatial /
> Geometry）与 components（CCmpPathfinder / CCmpObstructionManager）。
> 方法：6 个模块并行对照精读（model / long / vertex / hierarchical / obstruction+PathGoal /
> facade+queue），每条结论要求双边 file:line 证据；主会话对 load-bearing 结论抽查复核
> （test_groups.json 005 排除、set_bounds 极性、vertex 起点判死均亲验证实）。
> **约束：只 review 不重写。本文件不改任何代码。**

---

## 总评

**架构站得住，用户满意的部分（地图数据结构 + 基础寻路）经得起对照。** 这是一次有意识的
语义 fork 而非走样复刻：JPS 内核的 forced-neighbour / 对角递归 / 成本常数（65536/92682）与
0ad 逐条等价且最优性更严格（0ad 碰 goal 即 `open.clear()` 放弃最优，本实现等最小 f）；
hierarchical 的增量重算与全量 recompute 逐位一致（0ad 增量后 global ID 会漂，本实现天然支持
replay）；PathGoal 五型含 inverted 与 0ad 逐分支数值等价；spatial index 的记账式 remove 结构性
消除了 0ad「caller 必须记住旧坐标」的坑。多处偏离有注释自证 + repro 锚定（repro_core_001~018
形成行为护栏网），工程纪律少见地好。

**缺陷集中在三类**：
1. **0ad 靠它保正确性的两个保守性机制没带过来**——`CLEARANCE_EXTENSION_RADIUS`（保长程严于
   短程 → 单位不卡墙）与「impassable→passable 允许离开」逃逸规则（保卡进阻挡的单位能自己走
   出来）。两条都有本仓 repro/issue 佐证不是臆测，且与用户抱怨的「单位卡住/僵死」手感直接相关。
2. **0ad 没有的自加特性带的债**——queue 的 worker/cancel 路径 4 个确认缺陷（生产未用，潜伏）；
   immediate/result 双入口复制后单边漂移（3 处）。
3. **一个统一的性能根因**——主 dirty 层 O(W×H) 全扫（obstruction 侧已有 O(dirty) 列表先例，
   主层是没做完的对称），4 个模块的性能红旗都汇聚到它。

---

## 一、确认缺陷（按严重度）

### C1. `CLEARANCE_EXTENSION_RADIUS` 缺失——「长程严于短程」不变量断裂 ⭐已知未修

- **现象**：长程栅格化只用 `config.clearance`，无 +1 navcell 扩展
  （`model/sim_nav_map.gd:486-495`、`obstruction/sim_nav_obstruction_shape_static.gd:46`）。
- **0ad**：`Pathfinding.h:156-160` 定义 `CLEARANCE_EXTENSION_RADIUS = 1`，
  `Rasterize.cpp:48` `rasterClearance = clearance + CLEARANCE_EXTENSION_RADIUS`；
  `Rasterize.cpp:33-46` 注释明说这是修「长程给路、短程拒绝 → 单位穿墙/卡死」的 2015 老 bug。
- **实证**：`repro_core_005_clearance_extension.tscn` **HEAD 现 FAIL**（exit=1）；
  `tests/test_groups.json:25-41` 收录 repro 001-004、006-018，**唯独排除 005**——已知开放缺口，
  `repro_core_011` 头注也再次引用。
- **叠加因素**：cell 采样用 center 一点（0ad 是四角全含才 block，
  `CCmpObstructionManager.cpp:1125-1126`），双向 ±半 cell 抖动进一步恶化长短程错配；example
  层还存在栅格 clearance(10) < LOS clearance(11) 的倒挂
  （`examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_pathfinder.gd:24,54` vs
  repro/stress 用 RADIUS=11），方向与 0ad 的严格序完全相反。
- **后果**：长路径合法穿过、短程走不动的振荡（CORE-011 的成因形态，靠 best-vertex fallback
  兜底）。这是 0ad 拿来保「不卡单位」的机制。

### C2. vertex/facade 线段检查缺「impassable→passable 允许离开」逃逸规则

- **现象**：`pathfinding/sim_nav_vertex_pathfinder.gd:545-546` 起点 navcell 不可通行整段判死；
  `pathfinding/sim_nav_pathfinder_facade.gd:238-240` 同型。
- **0ad**：`Pathfinding.cpp:46-48, 61-75` 明文注释 + `currentlyOnImpassable` 状态机——允许从
  impassable 走向 passable（不允许反向）；vertex 侧 terrain 边是单向边
  （`VertexPathfinder.h:121-122`），从阻挡区内向外的线段放行。
- **后果链**：push 会把单位刷进 static 的 clearance 环（CORE-020 实测 0.77px 侵入）。栅格是
  clearance-baked 的，单位中心 cell 一旦翻 impassable，`pass_mask != 0` 的短径所有出边被 DDA
  拒绝 → 连 best-vertex fallback 都无顶点可用 → `no_route`；movement line 验证同样全拒 →
  **单位僵死，只能靠 push 震荡把它带出去**。0ad 同型状态下按设计能自行走出。
  CORE-020 的 fix option E（LOS boundary 显式化）与此同域。

### C3. `set_bounds` 极性与自身声明的 0ad 镜像相反：界外=自由（0ad 界外=封死）

- **双 agent 独立发现，交叉验证成立；主会话亲验 `model/sim_nav_map.gd:486-488`。**
- **现象**：`_blocked_mask_for_point` 对 playable bounds 外的点返回 0 = 不被任何 obstruction
  阻挡；`is_passable_navcell` 不查 bounds（`:362-365`）；long pathfinder 仅 query 级校验
  start 与 POINT goal（`sim_nav_long_pathfinder.gd:58,71`）。注释自称
  "Mirrors 0 A.D. ICmpObstructionManager::SetBounds"（`sim_nav_map.gd:36`）——不符。
- **0ad**：`ICmpObstructionManager.h:110-111` "Any point outside the bounds is considered
  obstructed"；界外封锁由 `TerrainUpdateHelper` 给边缘带对所有 class 上 edgeMask 保证
  （`CCmpPathfinder.cpp:700-744`）。
- **后果**：bounds 收紧后路径可合法绕出 playable 区（甚至穿跨界建筑的界外半截再绕回）。
  `repro_core_004:76-84` 还把「跨界 OBB 的界外 cell 必须 passable」锚成了契约——修复需连
  repro 契约一起改。
- **现役影响=0**：两个 lab 都没用 `set_bounds`，各自在 adapter 层手涂界外 cell
  （`zero_ad_rts_lab_pathfinder.gd:268-275`、`dota2_lab_pathfinder_wrapper.gd:41`）——等于
  每个 adapter 手动补回 0ad 机制。

### C4. queue 的 worker / cancel 路径 4 个缺陷（0ad 没有的自加特性；生产未用，潜伏）

均在 `pathfinding/sim_nav_path_request_queue.gd`：

1. **`start_worker` 覆写已结束未 collect 的 Thread，整批结果静默丢失**：`is_worker_running()`
   = `is_alive()`（`:145-146`），worker 跑完后为 false，轮询式
   `if not is_worker_running(): start_worker()` 直接覆写未 join 的旧 Thread（`:132`）——旧
   batch 结果永不 resolve。0ad 用 `SendRequestedPaths` 强制 join 屏障 + `ENSURE`
   （`CCmpPathfinder.cpp:819-861`）。
2. **`cancel()` 预毒未来 ticket**：第一步无条件 `_cancelled[ticket_id] = true`（`:70`）再查
   容器；对从未签发的 id 返回 false 却留永久标记，新 ticket 增长到该值时被静默跳过
   （`:100-101, :323-324`）。且 `_cancelled` 只在 `clear()` 清空（`:263`），无界增长。
   0ad 根本没有 cancel API（调用方比对 expected ticket 丢弃过期结果）。
3. **worker 无并发契约**：`_compute_worker_batch`（`:330-346`）在 Thread 上调
   `facade.compute_path_result`，而该链路会写共享状态（JPS cache 懒构建写
   `_jump_point_caches` Dictionary，`sim_nav_long_pathfinder.gd:612-621`）；主线程并发
   `process_budget` / `recompute_dirty` 即未同步跨线程读写。0ad 三重防护（每线程独立
   pathfinder 实例、worker 只在 turn 间跑且 grid 冻结、cache 线程安全声明）全部缺席，
   `public-api.md` 只字未提约束。
4. **`start_worker` 失败回滚不清 `_in_worker` 标记**（`:136-137` vs `:325`），污染诊断。

缓解：两个 lab 生产路径都只用 `process_budget`（dota2 设计文档明说不用 worker），worker 仅
smoke 覆盖。**短期修法各约 5 行，或至少在 public-api.md 钉死并发契约。**

### C5. 每次寻路无条件 O(W×H) dirty 轮询（性能契约级）

- `sim_nav_long_pathfinder.gd:618` 每次取 cache 都调 `invalidate_dirty_navcells` →
  `has_dirty_navcells()`（`sim_nav_map.gd:438-442`）= 全网格线性扫。256×256 图 = 每条路径
  65536 次迭代，直接抵消 JPS 亚线性优势。
- 更糟：`cache.reset()` 不清 nav_map 的 dirty flags；**不走 facade `recompute_dirty` 循环的
  调用方**（smoke 支持的合法用法）一次地形变更后 dirty flags 永驻 → cache 每次 reset →
  永久空转还多付轮询成本。
- 0ad 失效是事件驱动（`Reload()/Update()` 时清 cache，`LongPathfinder.h:189-205`），查询路径
  零轮询。正确性不受影响（保守失效方向），修法：dirty 版本号/计数器 O(1) 查询，或失效全交
  facade 事件通道。

---

## 二、疑似问题（需跟进，非现役事故）

**契约型（扩展即雷）**：

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| S1 | hierarchical `recompute_dirty` 传 mask 子集时其余 mask 静默陈旧 | `sim_nav_hierarchical_pathfinder.gd:59-69` | 0ad 把 class 集合存 `m_PassClassMasks` 结构性杜绝；引入第二个 passability class（flying/naval）时必踩。建议 recompute 时记住 mask 集 |
| S2 | 查询未注册 mask 静默返回「不可达」 | 同上 `:103-107` | 与真不可达不可区分；0ad 是 `.at()` 直接抛。低层 API 应 fail-fast |
| S3 | INVERTED goal 环扫边界紧 + 兜底不查 goal containment | 同上 `:567-579, :420-432` | 可把目标 canonicalize 到 inverted 区内部（单位想逃离的地方）；上 flee/min-range 行为前必修 |
| S4 | `moving` bool 与 `flags & MOVING` 双份状态可单向失步 | `sim_nav_obstruction_shape_unit.gd:6` + filter `:46` | 绕过 manager 直改 flags 后 filter OR 合并两源 → 永久当 moving。0ad 单一事实源（只有 flags）。建议删字段或改只读 getter |
| S5 | `required_flags` 是 ALL-of，0ad 同位语义 ANY-of | `sim_nav_obstruction_filter.gd:64` vs `ICmpObstructionManager.h:477` | 单 bit 等价；照 0ad 习惯传组合 mask 会静默变严。至少 docstring 注明 |
| S6 | static shape 几何字段裸 public 可变但 mutation 无 dirty 传播 | `sim_nav_obstruction_shape_static.gd:5-7` | 只有 `flags` 有 weakref dirty setter；直改 `width` 后 grid 不更新，改小后连 `rebuild_dirty` 都修不回。需定夺：全字段 setter 化 or 学 0ad 收私有 |
| S7 | `validate_unit_line` 缺越界失败分支 | `sim_nav_pathfinder_facade.gd:205` | 0ad `TestUnitLine` 第一步查 `IsInWorld`（`CCmpObstructionManager.cpp:940-941`）；unit_only 时整段 navcell 检查被跳过，出界也返回 clear |
| S8 | `take_long/short_path_result` 类型不匹配先删后判，结果静默销毁 | `sim_nav_path_request_queue.gd:190-207` | 与「还没算完」不可区分。不匹配时不 erase + push_error |
| S9 | `FAILURE_NOT_RECOMPUTED` 被映射成 `FAILURE_NAV_MAP_MISSING` | `sim_nav_pathfinder_facade.gd:183-185` | nav map 在场却报 missing，误导排障。DTO 里现成有 `FAILURE_PASS_MASK_MISSING` 可用 |
| S10 | `move_obstruction` 默认参数把旋转过的 static 悄悄归零 | `sim_nav_map.gd:170-183` | `rotation_rad = 0.0` 默认值，只想平移漏传第三参 → 旋转静默丢。0ad `MoveShape` 四参必填 |
| S11 | unit shape 挂 `BLOCK_PATHFINDING` 静默无效 | `sim_nav_map.gd:672` + shape flags setter | 「单位不进 grid」是文档化设计，但无警告。建议 push_warning |
| S12 | `get_navcell_terrain_data` 负坐标返回第 0 列数据而非 0 | `sim_nav_terrain_tile_map.gd:19-24` | 整除向零截断；内部调用点已被挡，public API 面裸露 |

**双入口漂移型**（同一模式三处，建议一并收敛）：

| # | 问题 | 位置 |
|---|---|---|
| S13 | long：`compute_path_immediate` JPS 失败回退 A*（理论死代码，掩盖潜在 JPS bug），`compute_path_result` 无 fallback——同 query 两入口不同答案，且 fallback `_astar` 是 4 向而 excluded-region `_astar_cells` 是 8 向 | `sim_nav_long_pathfinder.gd:144-147` vs `:100-102` |
| S14 | vertex：`compute_short_path_result` 拒绝超程 goal（OUT_OF_RANGE），`compute_short_path_immediate` 径向 clamp 出部分路径；0ad 从不拒绝（搜索盒向 goal 平移 3/5·range，`VertexPathfinder.cpp:576-585`） | `sim_nav_vertex_pathfinder.gd:54-56` vs `:20-37` |
| S15 | facade：`compute_path_immediate` 原位改写调用方 goal（已在 public-api.md 声明），与 `compute_path_result` 的 clone 纪律不一致 | `sim_nav_pathfinder_facade.gd:108-109` |

**行为语义型**：

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| S16 | 无 0ad 的 iBest best-effort 兜底：open 耗尽返回空（0ad 永远给一条到最近可达点的路，`LongPathfinder.cpp:894-906`）；无 hierarchical 时 CIRCLE/SQUARE goal 不可达会全域泛洪后空手 | `sim_nav_long_pathfinder.gd:575` | 调用方必须处理空路径；契约应写死 |
| S17 | vertex 覆盖剔除半径比 0ad 大 δ，比自身 LOS 更激进；且缺 0ad「start 在 shape 内 → 该 shape 不剔除顶点」例外（`VertexPathfinder.cpp:720-725`） | `sim_nav_vertex_pathfinder.gd:511-517, :506-519` | 各一行级修正 |
| S18 | DDA `max_steps` 耗尽 fail-open（判通行） | `sim_nav_vertex_pathfinder.gd:575-586`、facade `:269-281` | 安全阀方向反了，应 fail-closed |
| S19 | `static_vertex_extra_outset` 默认 0 是 footgun：`pass_mask != 0` 且没设该参的调用方会得到「切边被 DDA 拒 → 绕远/no_route」 | `sim_nav_short_path_request.gd:13`（lab 自己记得设 `cell_size*0.5`） | 建议默认值 addon 内推导 |
| S20 | excluded_regions 与 canonicalization 互不知情：start 恢复/goal 改写可能落进 excluded 圈 → 假失败 | `sim_nav_pathfinder_facade.gd:77-82` | 小众特性，低危 |
| S21 | queue 积压无界：0ad 每 turn 末尾有不限量全量处理保证延迟 ≤1 turn（`Simulation2.cpp:593`）；本实现只有每 tick `process_budget(2)`，50 单位齐发 repath 尾部等 25 tick。确定性无损 | `zero_ad_rts_lab_world.gd:8,118` | 至少给 `pending_count` 设水位告警 |
| S22 | queue smoke 全部以 `hierarchical=null` 组 facade——canonicalization 管线没有任何 queue 级覆盖，被测 wiring 与生产不同构 | `smoke_sim_nav_path_request_queue.gd:258` | 补一个带 hierarchical 的用例 |

---

## 三、与 0ad 设计差异裁决

### 判合理（正当性成立，部分优于 0ad）

- **hierarchical dirty 重算 = chunk 重建 + 边/global 全量重导出**（vs 0ad 手术式增量）：增量
  结果与全量逐位一致，对 replay 是比 0ad 更强的性质；0ad 增量在「dirty chunk 重建后 region
  集为空」角例下疑似留陈旧 global ID（源码推理），本实现天然免疫。
- **可达的面 goal 不预归约为 POINT 直接交 JPS**（0ad `MakeGoalReachable` 强制 POINT）：JPS
  原生以 containment 终止，逼近质量不劣于 0ad 且启发式仍 admissible。
- **excluded regions 走 query 级 8 向 A***（vs 0ad 写 SPECIAL_PASS_CLASS 第 16 bit 再 JPS）：
  不污染 grid、不征用 bit；GDScript 里 0ad 方式要全图写两遍位未必更快。
- **goal 终止等最小 f**（0ad 碰 goal 即清 open 放弃最优）：更慢但保证最优。
- **栅格化 gather**（逐 dirty cell 查 index 重算，vs 0ad scatter 逐 shape 重画 + 邻居 dirty
  传播）：天然处理重叠 shape，正确性好推理。
- **逐 tile 地形增量重建自带 clearance padding**（0ad `MinimalTerrainUpdate` 不做扩张等下轮
  全图重建）：真局部增量，padding 数学核过足够，优于 0ad。
- **地形 clearance 用欧氏 point-to-rect**（0ad 滑窗 Chebyshev 方角，且 0ad 注释自认想改
  Euclidean）：实现了 0ad 的 TODO。
- **单位圆模型**（0ad unit = AA square）：与 lab 的 push/碰撞物理自洽，几何正确；代价是 0ad
  的 clearance 数值不能直接移植（对角松 √2）。顶点仍取外接方角，保守恒可达。
- **gap-midpoint 顶点（CORE-018 修复）**：0ad 没有，靠 formation/长径不激进简化/run
  multiplier 三层掩盖同一限制；lab 直接几何构造，文档化的正向偏离。
- **无 quadrant 剪枝**：纯剪枝，去掉不损路径质量还免掉 0ad 为 start-inside 打的 hack；性能账
  见下节。
- **pull 结果模型、FIFO 处理序、long/short 混编单队列、queue 不序列化、单 worker**：与 lab
  规模匹配的合理简化，各自内洽。
- **DTO 契约比 0ad 裸 waypoints 丰富**（status/failure/canonicalization 元数据/诊断计数）：
  每类字段有真实消费者（smoke 断言、lab last_report、issue 排障），**非过度设计**。
- **BOUNDARY hit 显式建模、start 不可通先恢复最近可通格、waypoint 逆序契约、成本常数、
  tie-breaking 确定性**：与 0ad 等价或更通用。

### 判存疑（记录在案，出问题先查这里）

| 差异 | 说明 |
|---|---|
| **cell 采样 center 一点 vs 0ad 四角全含** | 双向 ±半 cell 抖动；丢掉 0ad「shape 几何边界永远可达」保证（贴墙目标可能落 blocked cell）。与 C1 叠加是长短程错配的两大来源 |
| **flag 门槛重划**：statics 看 BLOCK_PATHFINDING、units 看 BLOCK_MOVEMENT，gate 散在消费端 | 0ad 短程 filter 对两类统一要求 BLOCK_MOVEMENT 且收在 filter 里。自洽但需文档钉死，新增消费者易忘 gate |
| **unit-unit 系统性放宽 −1/2 缺失** | 0ad 短径图对 unit 减半格 clearance + 运动 TestLine 同减（`VertexPathfinder.cpp:630-631`、`CCmpPathfinder.cpp:975-979` "makes movement smoother"）≈62% 放宽；lab 只有 0.5px band ≈2.3%。**密集群通过性天然更紧，正是需要 gap-midpoint/band 规则去补的根源**。若再出 dense-cluster 绕圈，0ad 的原生答案是这个 −1/2 |
| **短径通行性走组合栅格 vs 0ad terrain-only grid** | statics 被检查两遍（栅格量化 + LOS 精确），缝靠 `static_vertex_extra_outset` 手工弥合（S19）。0ad 分工干净：static=精确几何一遍、terrain=栅格一遍 |
| **LOS band 规则（lab 自创）** | 运动候选可合法切入碰撞环最深 0.5px，靠 push 清账；有 repro 护栏但需持续盯 CORE-020 类演化 |
| **同一 static 三种几何模型并存** | 栅格方角 Chebyshev / LOS 圆角 Minkowski / 顶点方角外扩；`pass_mask=0` 的请求只剩圆角语义与图顶点方角假设有 √2 缝，目前无 repro 打中 |
| **JumpPointCache 无 0ad 的行区间压缩/共享** | 0ad 全图预计算 O(1) 查表；本实现 per-(cell,dir) 懒 memo，(5,3) 向右的扫描不惠及 (6,3)。至少可把扫描沿途各 cell 一并填 key |
| **global region ID 跨重算不稳定 + 跨 mask 各自从 1 起** | 隐式契约「仅同代快照内可比」，建议类头注释钉死 |
| **CHUNK_SIZE=96 照抄** | 0ad 自己标 TODO 待调；lab 地图（200×100）下仅 1-6 个 chunk，层级近乎退化。32/48 更可能是 GDScript 甜点，值得跑参数对比 |
| **无 globallyDirty 短路** | set_bounds/register_class 全图级变更也逐 cell append 列表 |
| **cancel API 本身** | 0ad 没有；pull 模型下有正当性但引来 C4.2 两个 wart，「结果照发、调用方丢弃」其实更简单且自动有界 |

---

## 四、架构评价

- **分层优于 0ad**：0ad `CCmpObstructionManager` 是 1410 行单体（序列化+栅格+测距+调试渲染），
  本实现拆 shape/manager/map/filter/index 职责单一；JPS 内核不背 hierarchical 依赖（0ad
  `ComputeJPSPath` 硬引用 hierPath）；canonicalization 集中 facade 且有结构化 Result 契约。
- **确定性做得扎实**：sorted rid、固定扫描序、五键 tie-break、enqueue 即 clone、双跑确定性
  smoke——core-019 修复后确定性路径是双层默认值，wall-clock 只能显式 opt-in 且有大写 WARNING，
  隔离干净。
- **主要架构债**：① worker 这条「为对齐 0ad 线程模型预留、但没配齐 0ad 三件安全护具」的路径
  （C4）；② 双入口复制是 drift 温床（S13-S15）；③ flag 门槛散在消费端；④ `SimNavMap` 合并
  0ad 两个组件职责后，playable-bounds 语义裂在两处（map 裁栅格 + long 查 start/goal），C3 正
  是裂缝产物。
- **死代码四件**（`sim_nav_map.gd` `_rasterize_static_obstruction:464-483` /
  `_clear_obstruction_navcell_data:528-530` / `_mark_rebuild_changes_dirty:653-657` /
  `_compose_navcell_data:660-665`，首个还是与现役 gather 相悖的 scatter 语义）+ vertex
  `_path_length:607-614` 全仓零调用。建议删。
- **`rebuild_dirty` 与 `rasterize_dirty_obstructions` 双入口**名义契约相同，实际前者额外全量
  扫所有 shape AABB（顺带兜住 S6 的未跟踪 mutation，后者不兜）；public-api.md 并列不作区分。
  要么合并、要么写清语义差。
- **public-api.md 尾部仍引用已删除的 rts-auto-battle**——文档陈旧点。

---

## 五、性能红旗（按规模化炸点排序；lab 当前规模均不致命）

1. **主 dirty 层 O(W×H) 全扫**（= C5 的根）：`collect/has/clear_dirty_navcells` 全线性；
   `facade.recompute_dirty` 每 tick 3 次全扫，零变更也扫；long 每次寻路再扫一次。obstruction
   侧已有 O(dirty) 列表（`sim_nav_map.gd:18-23`），主层照抄即可。**四个模块的红旗汇聚于此，
   修一处全收益。**
2. **vertex A* 主循环 O(V²·(S+U))**：无 quadrant 剪枝、每条 LOS 顺序扫全部 shapes 无早退无
   排序。U=40、S=10 时单查询 ~200 万次距离运算。最便宜的两刀：shapes 按到 start 距离排一次
   （近的先测早退）+ 恢复 quadrant 剪枝。gap-midpoint 生成另有 O(U³)，可用 spatial index 限
   pair 枚举邻域。
3. **全图地形重建无滑窗**：O(W·H·classes·(2·pad+1)²) vs 0ad O(W·H·classes)；且
   `register_passability_class` 每注册全跑一遍。init-only 可忍，别进运行时。
4. **open list 是有序数组非真堆**：insert O(n) memmove、pop `remove_at(0)` O(n) 前移、五元素
   Variant Array key 逐元素比较。open 数百无感，数千平方级。
5. **JPS cache 常数**：String key（格式化+哈希+分配）、每 hit 一个 RefCounted、命中后 goal
   线性扫（POINT goal 可预转 cell 整数比较，0ad 是 O(1) 区间判定）。
6. **spatial index `move` 无同桶 early-out**（0ad 有，`Spatial.h:222-230`）+ 每操作分配 cell
   数组；每 tick 每单位一次，单位上百后首个热点。
7. 次要：`process_path_budget` 每次深拷贝诊断进 last_report（lab 侧）、result 滞留期间持有整
   条 raw_navcell_path、`_pending` 头部 O(n) 操作、static 索引 AABB 用外接圆（45° 大 OBB 假
   阳 ~5×，保守无漏）、`_build_chunk` 不裁剪出图部分（320×16 图 ~83% 浪费，一行 clamp）。

---

## 六、建议行动清单（1a 只 review 不动手；供后续排期）

**P0——直接对应「单位卡住」类手感，两条都有 repro/issue 实证**：
1. ✅ **已修（2026-07-02，同日）** C1：栅格化补 `CLEARANCE_EXTENSION_RADIUS`（+1 navcell），
   005 已回归 smoke 组。example 层「倒挂」实为等 +1 落地的前置补偿（0ad 把默认 clearance 降
   0.8 的同款），不再单独校。
2. ✅ **已修（2026-07-02，同日）** C2：vertex + facade 两处 DDA 补 `currently_on_impassable`
   状态机（照 `Pathfinding.cpp:61-75`），并把 step-budget 耗尽改为 fail-closed（顺修 S18）。
   配套：core 测试按新带宽校准（005/002/dirty/obstruction/vertex-tangent 两段式）；0ad lab
   默认走廊 42→74px（有效通道与旧世界逐像素一致）、logged-offset-opposing 冻结回放期几何、
   0ad_budget fixture 自建几何；dota2 lab cell 16→8 + outset 配平。**cell 8 在 0ad lab 的
   实验被回滚**——所有 logged-* 锚都是 16px 时代 export，重锚归 1b 契约重做。四组 smoke
   50/50 全绿。

**P1——契约止血（各 ~5 行或纯文档）**：
3. C4.1/C4.2 两个 queue bug + worker 并发契约写进 public-api.md + S22 补带 hierarchical 的
   queue smoke。
4. C3 定夺方向：要么按 0ad 语义修（界外全 class 封死 + 改 repro_core_004 契约），要么删
   「Mirrors 0 A.D.」注释接受现状（lab 反正 adapter 手涂）。
5. S1/S2（hierarchical mask 契约）、S4（moving 双份状态）、S10（move_obstruction 必填参）。

**P2——性能与卫生（出现帧预算问题再动算法，卫生可随手）**：
6. 主 dirty 层列表化（红旗 1，修一处四模块收益）。
7. 双入口收敛（S13-S15）+ 死代码五件清理。
8. vertex 剪枝两刀（红旗 2）——单位数上 50 前不急。

**观察项**：unit-unit −1/2 放宽（dense-cluster 再出问题时的 0ad 原生答案）、CHUNK_SIZE 参数
对比、LOS band 规则盯 CORE-020 演化。
