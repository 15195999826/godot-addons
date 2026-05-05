# Sim Nav Map Feature Roadmap

本文记录 `sim-nav-map` 在 `sim-nav-map-v1.0.0` baseline 之后的 feature
开发路线。它不是 V1 补完清单，而是未来 `/goals` 会话的执行顺序。

目标是学习并迁移 0 A.D. 的 pathfinding / navigation system 层能力，不是迁移
完整 RTS gameplay。`examples/rts-pathfinding-lab` 是 adapter consumer 和
playable regression，用来验证 core navigation 能力是否足够；它可以做
formation / crowd / movement policy 实验，但这些 policy 默认不进入 core addon。

## 当前状态

`sim-nav-map` 已是 V1 baseline：

- public API / internal helper 边界已收口，见 [`public-api.md`](public-api.md)。
- core addon smoke 和 lab smoke 已形成稳定入口，见 [`smoke-matrix.md`](smoke-matrix.md)。
- `examples/rts-pathfinding-lab` 已是 plugin-local adapter consumer / playable regression。
- `sim-nav-map-v1.0.0` tag 标记当前 `addons` submodule commit。

V1 已具备：

- navcell map、terrain tile data、passability class、static/dynamic obstruction projection。
- dirty lifecycle、hierarchical reachability、long pathfinder、vertex short pathfinder。
- path request queue 和 lab adapter smoke。

Feature 1 已补齐：

- `SimNavMap.set_terrain_tile_data()` 会把 terrain tile data 派生成 navcell
  passability，并 mark changed navcells dirty。
- `SimNavPassabilityClassConfig.terrain_mask` 按 class 解释 terrain bits，让同一
  terrain surface 对 ground / ship / unrestricted 等 class 有不同 passability。
- `rts-pathfinding-lab` 只新增 terrain preset adapter smoke，不把 ship gameplay、
  terrain edit UI 或 movement policy 上提到 core。

Feature 2 已补齐：

- `SimNavPassabilityClassConfig.clearance` 参与 terrain-derived passability 和
  static obstruction rasterization。
- 同一 blocked terrain / static obstruction 可以对 small / large class 产生不同
  passability mask，long path 会按各自 mask 判断窄缝能否通过。
- `rts-pathfinding-lab` 只新增 small / large clearance adapter smoke，不把 unit
  type、movement、selection、command、formation policy 上提到 core。

V1 不承诺：

- 完整 RTS movement system。
- formation controller / selection / unit command system。
- combat、UnitAI、economy、resource gathering。
- game-specific push/yield/stuck/deadlock policy。
- 大规模地图和高单位数性能保证。

## Core Addon / Example Boundary

`sim-nav-map` 是 navigation infrastructure，不是 game entity model，也不是 movement
system。

```text
game unit / building / terrain source
  -> project adapter
  -> SimNavMap terrain / passability / obstruction projection
  -> reachability / long path / short path / queue
  -> SimNavWaypointPath or query result
  -> project movement code
```

Core addon 可以增加：

- terrain-derived passability data。
- passability class、clearance、terrain mask 和 obstruction rasterization。
- obstruction shape database、spatial query、dirty/cache lifecycle。
- filtered obstruction queries and movement-line validation。
- hierarchical reachability 和 goal canonicalization。
- long-range navcell path search。
- short-range vertex / line-of-sight path search。
- budgeted / worker-style request queue。
- navigation diagnostics data needed to verify those mechanisms。

Core addon 不上提：

- unit movement integration、speed、acceleration、turning、arrival policy。
- selection、command queue、UnitAI、combat、resource、build rules。
- formation slot assignment、formation controller、rank ordering。
- push/yield、unit priority、deadlock resolution、stuck policy。
- HUD、editor workflow、playable controls。

`rts-pathfinding-lab` 可以实现这些应用层行为，用来证明 adapter 能消费 core
navigation primitives。只有当某个机制满足以下条件时，才考虑从 lab 提升到 core：

- 至少两个 example / game adapter 都需要。
- 只依赖 navigation data，不依赖玩家命令、单位职业、阵营、选择框、HUD 或玩法意图。
- 已有 `simnav/smoke` 或 `rtslab/smoke` 证明行为稳定。
- 可以用小而清晰的 DTO / method 表达，不把 gameplay policy 包进 API。

`docs/references/0ad-source/` 是本地参考源码目录，不进 git，不复制 GPL 源码实现。
本文可以引用其中的文件路径作为设计参考，但 roadmap item 的实现必须重新设计成
`sim-nav-map` 自己的 GDScript API 和 smoke contract。

## Roadmap References

0 A.D. 源码索引、gap audit 吸收结论、deferred items 和 explicit non-gaps 放在：

```text
addons/sim-nav-map/docs/roadmap-refs/0ad-navigation-source-map.md
```

主 roadmap 只保留执行顺序、边界和验收。需要源码证据时先读 refs，再回到对应 feature。

## Recommended Feature Order

| Order | Feature | Core addon capability | 0 A.D. idea | Requires previous feature? |
|---|---|---|---|---|
| 0 | Baseline guard | 保持 V1 public API / smoke / docs 一致。 | engine / game boundary 清晰。 | 否，持续维护。 |
| 1 | Terrain-derived passability | 从 terrain data 派生 navcell passability。 | Terrain tile grid 只提供输入，Navcell grid 才服务寻路。 | 否，但应先于多 class scale 工作。 |
| 2 | Class-aware clearance rasterization | 按 passability class / clearance rasterize terrain + static obstruction。 | passability mask + clearance baked into grid。 | 建议紧跟 Feature 1。 |
| 3 | Dirty edit and cache lifecycle | 统一 terrain / obstruction edit 的 dirty recompute 和 cache invalidation。 | dirtinessGrid + incremental raster / hierarchical update。 | 依赖 Feature 1-2，必须连续完成。 |
| 4 | Reachability and goal canonicalization | 显式 `IsReachable` / nearest reachable goal query。 | Hierarchical `IsReachable` / `MakeGoalReachable`。 | 依赖 Feature 3。 |
| 5 | Long-path query/result contract | 更清晰的 query input、path status、cost、raw/refined waypoint contract。 | Long-range path 是粗路线，给 short-range 和 motion 消费。 | 依赖 Feature 4。 |
| 6 | Filtered short query and line validation | obstruction filter、movement-line validation、dynamic obstruction / LOS 边界更稳定。 | Vertex pathfinder + filter-aware `CheckMovement`。 | 依赖 Feature 2-3。 |
| 7 | Request queue budget / worker contract | 长短路径统一排队、取消、收集、预算和诊断。 | ticket queue + per-turn path budget。 | 依赖 Feature 4-6。 |
| 8 | Scale diagnostics and perf scenarios | core navigation 性能边界和诊断数据。 | 大地图 / 多单位下用分层和队列控成本。 | 依赖 Feature 3 和 7。 |

Feature 1-4 是地图 / passability / reachability 基础链，建议连续推进。Feature 5-7
是 path query 质量和调度链，可以分开做，但不要在没有前置 smoke 的情况下进入 scale
tuning。Feature 8 只在核心行为稳定后做，否则 benchmark 没有可比较意义。

## Feature 0: Baseline Guard

### 增加什么插件能力

不增加新能力。目标是保持 V1 baseline 可继续作为其它 example / adapter 的稳定依赖。

### 0 A.D. 对应思想

0 A.D. 把 engine-side pathfinding 和 JS game rules 分开；这里对应的是继续保持
`sim-nav-map` core 与 `rts-pathfinding-lab` application 的边界清晰。

### 完成后获得什么能力

- 新 feature 可以在稳定 public API 上迭代。
- 文档、smoke、example 不会互相漂移。

### 依赖和连续性

- 无前置依赖。
- 每次修改 public API、smoke group、example boundary 都要同步文档。

### Example 需要配合什么验证

- `rts-pathfinding-lab` 保持 adapter consumer 身份。
- lab 里的 movement / HUD / formation offset 不应被写进 `public-api.md`。

### 用户可以在 lab 手动验证什么

打开：

```text
addons/sim-nav-map/examples/rts-pathfinding-lab/frontend/rts_pathfinding_lab.tscn
```

验证：

- 默认场景能加载。
- 单位能移动、放置 / 删除障碍后还能重新寻路。
- `G` / `D` 等 lab-only policy toggle 不被描述成 core API。

### 自动验证命令

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

### Feature 1 入口条件

进入 Feature 1 前必须先确认：

- `./tools/run_tests.ps1 simnav/smoke rtslab/smoke` 通过。
- `git -C addons diff --check` 通过。
- `docs/public-api.md`、`docs/smoke-matrix.md` 和本 roadmap 仍描述同一条
  core addon / `rts-pathfinding-lab` 边界。
- `addons/sim-nav-map/docs/references/0ad-source/` 没有被 track 或 stage。
- 下一步改动只围绕 terrain-derived passability；如果需要碰
  `core/model/obstruction/pathfinding` runtime code，先明确受影响文件和新增 smoke。

## Feature 1: Terrain-Derived Passability

### 增加什么插件能力

把 terrain / map data 变成 first-class navigation input。`SimNavTerrainTileMap`
不只存测试用 tile data，而要能稳定派生 navcell passability：

- terrain tile -> navcell 的 projection 规则。
- terrain mask / terrain type 对 passability class 的影响。
- 可选的 height / slope / water depth / shore distance 这类 terrain-derived
  constraint 的扩展点。
- terrain edit 后标记受影响 navcell dirty。

这里仍然不做地图渲染，也不定义游戏地形美术；只定义 navigation 需要的 terrain
数据和派生规则。

### 0 A.D. 对应思想

0 A.D. 的 Terrain Tile Grid 主要服务地图 / 渲染数据，Navcell Grid 才是寻路数据。
pathfinder 会从 terrain 的高度、水深、坡度、shore 等信息预计算每个 passability
class 的 navcell mask。地图 / terrain 是寻路基础能力的一部分，但不是游戏玩法本身。

主要参考源码：`source/simulation2/helpers/Pathfinding.h` 和
`source/simulation2/components/CCmpPathfinder.cpp`。

### 完成后获得什么能力

- 地图可以表达 land / water / slope / shore / material 这类 navigation surface。
- ground / ship / large / unrestricted 等 passability class 可以看到不同的可通行区域。
- 后续 large map 和 multi-class pathfinding 不需要在 adapter 里硬编码 terrain 判断。

### 依赖和连续性

- 无硬前置依赖。
- 应和 Feature 2 连续规划：terrain-derived mask 和 obstruction/clearance raster 最终要写进同一张 navcell passability 数据。
- 如果先只实现 terrain type mask，也要保留 height/slope/depth 扩展点，不要把 API 锁死成单一 enum。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 需要增加一个 terrain preset 或轻量 terrain edit mode：

- 用 adapter 把 lab terrain 投影进 `SimNavMap`。
- 至少验证两种 passability class 看到不同 terrain mask。
- 不实现 ship gameplay；可以用测试单位 / debug command 验证不同 class 的路径结果。

### 用户可以在 lab 手动验证什么

- 切到 terrain preset 后，ground unit 会绕开 water / blocked terrain。
- 用另一个 passability class 查询时，同一片 terrain 可以变为可通行。
- 修改 terrain 后，不 reset scene 也能让新 path query 读到变化。
- 这只是 navigation surface 验证，不是完整海军 / 水陆单位玩法。

### 自动验证命令

新增 core smoke 应注册进 `simnav/smoke`；新增 lab terrain smoke 应注册进
`rtslab/smoke`。统一入口：

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

### 完成记录

Feature 1 的当前完成契约：

- core terrain contract 在 `smoke_sim_nav_terrain_tile_map.tscn` 和
  `smoke_sim_nav_public_api_contract.tscn` 中覆盖。
- lab adapter contract 在
  `smoke_rts_pathfinding_lab_terrain_adapter.tscn` 中覆盖。
- terrain-derived passability 只写入 core navigation data；lab movement、
  selection、command、formation、ship gameplay、HUD policy 仍是 non-scope。

### Feature 2 入口条件

进入 Feature 2 前必须先确认：

- `./tools/run_tests.ps1 simnav/smoke rtslab/smoke` 通过。
- `git -C addons diff --check` 通过。
- `git -C addons status --short -- sim-nav-map/docs/references/0ad-source` 无输出。
- Feature 2 只围绕 passability class / clearance rasterization，不把 lab gameplay
  policy、dirty cache lifecycle 扩展或 request/result DTO 一并带入。

## Feature 2: Class-Aware Clearance Rasterization

### 增加什么插件能力

强化 passability class 与 static obstruction rasterization 的契约：

- 每个 `SimNavPassabilityClassConfig.clearance` 都参与 terrain / obstruction passability。
- static obstruction rasterize 时按 passability class 外扩。
- long-range grid 对同一 obstruction 可以按不同 class 得到不同 passability mask。
- long-range passability 应比 short-range precision query 更保守，避免 long path 给出
  short path 实际过不去的窄缝。

这不是单位碰撞系统。core 只回答“这个半径 / class 的 path center 能否通过这些
navigation obstacle”。

### 0 A.D. 对应思想

0 A.D. 的 passability class 用 bit mask 表达多类单位；clearance 是单位半径，
在 rasterize 阶段烧进 navcell grid。`CLEARANCE_EXTENSION_RADIUS` 让 long-range
比 short-range 更保守，避免粗路径和精确路径语义冲突。

主要参考源码：`source/simulation2/helpers/Pathfinding.h` 和
`source/simulation2/components/ICmpObstructionManager.h`。

### 完成后获得什么能力

- 小单位可过、大单位不可过的窄缝可以由 core pathfinding 正确表达。
- 不同单位类型不需要多套地图或 adapter-side if/else。
- 未来 terrain、建筑、墙、rock blocker 都能用同一套 passability mask 查询。

### 依赖和连续性

- 建议紧跟 Feature 1 完成。
- 必须连续覆盖：passability config -> raster write -> dirty update -> long path query -> vertex/LOS consistency。
- 如果改 prepared data layout，必须同步 `public-api.md` 和 `simnav/smoke`。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 需要提供小 / 大两种 query radius 或 debug unit type：

- app layer 决定单位半径和 class。
- adapter 把半径写入 passability / short request。
- 不把“单位类型、职业、速度、阵营”上提到 core。

### 用户可以在 lab 手动验证什么

- 放置两块障碍形成窄缝。
- 小 radius / small class 可以通过，large class 会绕路或判定不可达并 canonicalize。
- 动态单位避让开关不影响 static clearance 的基本结论。

### 自动验证命令

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

### 完成记录

Feature 2 的当前完成契约：

- core clearance contract 在 `smoke_sim_nav_clearance_rasterization.tscn` 中覆盖。
- terrain blocked navcell 会按 class `clearance` 外扩到相邻 navcell；清除 terrain
  时也会重算 clearance-expanded 影响范围并 mark changed navcells dirty。
- static obstruction rasterization 继续使用
  `SimNavObstructionShapeStatic.contains_point_with_clearance(point,
  config.clearance)`，同一 obstruction 可以得到 small / large 不同 mask。
- lab adapter contract 在
  `smoke_rts_pathfinding_lab_clearance_adapter.tscn` 中覆盖。
- 未实现 Feature 3+ 的 dirty cache lifecycle、reachability result DTO、long path
  result contract、short path filter、line validation、request queue expansion 或
  scale diagnostics；也未实现 ship gameplay、formation、push/yield、HUD policy 或
  game-specific movement policy。

### Feature 3 入口条件

进入 Feature 3 前必须先确认：

- `./tools/run_tests.ps1 simnav/smoke rtslab/smoke` 通过。
- `git -C addons diff --check` 通过。
- `git -C addons status --short -- sim-nav-map/docs/references/0ad-source` 无输出。
- Feature 3 只围绕 terrain/static obstruction edit 后的 dirty recompute 和 cache
  invalidation lifecycle；不要同时引入 reachability result DTO、long path result
  contract、short path filter、line validation、request queue expansion、scale
  diagnostics 或 lab gameplay policy。

## Feature 3: Dirty Edit And Cache Lifecycle

### 增加什么插件能力

把 terrain edit、static obstruction edit、dynamic obstruction replacement、hierarchical
dirty recompute、long-path cache invalidation 收敛成可推理的 lifecycle：

- 明确哪些 edit 会 mark dirty。
- 明确 dirty navcell / dirty obstruction navcell 的来源和清理时机。
- terrain/static obstruction edit 后，只重算受影响范围。
- hierarchical regions 和 jump-point cache 随 dirty lifecycle 自动失效或增量更新。
- 提供 batch edit 语义或明确的 update order，避免 adapter 每次手写 invalidation。
- 提供 per-tag incremental update：移动 / 旋转 shape、切换 active、更新 flags、
  更新 `control_group` / `control_group_2`，不要求 adapter 每次全量替换 dynamic list。

### 0 A.D. 对应思想

0 A.D. 的 ObstructionManager 是 shape 真相；grid、global region、JPS cache 都是派生缓存。
`dirtinessGrid` 串起 static map 变化后的增量 raster 和 hierarchical update，避免每次全图重建。
`ICmpObstructionManager` 还提供 `MoveShape()`、`SetUnitMovingFlag()`、
`SetUnitControlGroup()`、`SetStaticControlGroup()`，说明 shape lifecycle 是
navigation core primitive，不是 movement policy。

主要参考源码：`source/simulation2/components/CCmpPathfinder.cpp`、
`source/simulation2/components/ICmpObstructionManager.h`、
`source/simulation2/helpers/HierarchicalPathfinder.h`。

### 完成后获得什么能力

- 建筑 / 墙 / terrain 被放置、删除、移动后，pathfinder 能稳定更新。
- 大地图上局部编辑不会触发不必要的全图重算。
- cache correctness 有文档和 smoke 兜底，后续性能优化不会破坏正确性。

### 依赖和连续性

- 依赖 Feature 1-2。
- 必须连续完成 edit API、per-tag update、dirty collection、raster rebuild、hierarchical
  recompute、JPS cache invalidation、smoke。
- 不要只加 debug counter；如果 lifecycle 不自动保持正确，feature 没完成。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 保持 obstacle / blocker edit 在 app layer：

- app layer 负责玩家放置 / 删除对象。
- adapter 负责把对象投影成 `SimNavObstructionShapeStatic` 或 terrain edit。
- core 负责 dirty/cache lifecycle。

### 用户可以在 lab 手动验证什么

- 单位移动中放置 static obstacle，后续 replan 会绕开新障碍。
- 删除 obstacle 后，后续 path query 能重新穿过原区域。
- 连续快速编辑多个 obstacle 后，scene 不需要 reset 才恢复正确。
- 切换 blocker 的 moving / active / control group 状态后，下一次 query 使用新状态。
- HUD / debug overlay 可以显示 dirty/cache 状态，但它们不是 feature 的主体。

### 自动验证命令

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

## Feature 4: Reachability And Goal Canonicalization

### 增加什么插件能力

把 reachability 从 facade 内部行为提升成明确的 navigation query capability：

- 显式查询起点 / 目标是否在同一 reachable region。
- 对 `POINT`、`CIRCLE`、`SQUARE`、inverted goal 提供一致的 nearest reachable
  canonicalization 语义。
- 返回 canonical goal、是否改写、失败原因、passability class / mask 信息。
- 保持“goal 不可达时先 canonicalize，再跑 expensive long path”的调用路径。

这仍然不是移动失败策略。core 可以告诉 adapter 最近可达点；adapter 决定是否移动、
提示玩家、重试、取消命令。

### 0 A.D. 对应思想

0 A.D. 的 Hierarchical Pathfinder 用 global region 做 `IsReachable`，再用
`MakeGoalReachable` 把不可达目标替换成最近可达 navcell，避免 A* 在不可达目标上扫完整图。

主要参考源码：`source/simulation2/helpers/HierarchicalPathfinder.h` 和
`source/simulation2/helpers/HierarchicalPathfinder.cpp`。

### 完成后获得什么能力

- 点击建筑内部、孤岛、water/land 不匹配区域时，adapter 可以拿到稳定 fallback。
- 大多数不可达目标可以在 long path search 前快速处理。
- lab 和未来 game 可以用同一套 reachability result，而不是各自猜 path empty 的含义。

### 依赖和连续性

- 依赖 Feature 3 的 dirty/hierarchical correctness。
- 必须连续覆盖 goal types、passability classes、dirty 后 region 变化。
- 如果 API 返回新 result DTO，需要同步 `public-api.md` 和 `usage.md`。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 需要让 target marker / unit target 同步 canonical goal：

- 点击不可达点时，lab 显示原始 command target 和 core 返回的 reachable target。
- 单位移动到 reachable target 后由 lab movement policy 判断 arrival。
- 不把“不可达时是否报错 / 是否播放音效 / 是否取消命令”上提到 core。

### 用户可以在 lab 手动验证什么

- 右键点击建筑内部，单位移动到建筑边缘附近的可达点。
- 右键点击 blocked terrain / island，unit 不会原地静默成功。
- terrain 或 obstacle 改动后，同一点击位置的 canonical target 会随地图变化。

### 自动验证命令

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

## Feature 5: Long-Path Query/Result Contract

### 增加什么插件能力

把 long path 从“只有 waypoints”扩展为更可验证的 query / result contract：

- query status：success、canonicalized、unreachable、invalid start、empty path 等。
- query input：passability mask、goal、optional excluded regions、optional waypoint
  spacing / post-processing preferences。
- raw navcell path / refined waypoint path 的边界。
- path cost、path length、waypoint count、canonical goal metadata。
- 可选 path post-processing primitive：raw、line-of-sight compression / string-pulling
  风格的 waypoint cleanup、max-spacing-clamped waypoint output。

core 只提供 path planning result；不负责单位如何沿路径转向、减速、停住。

### 0 A.D. 对应思想

0 A.D. 的 long-range pathfinder 负责全局粗路线，short-range pathfinder 负责局部精度。
两层之间要有清晰 path result 边界，UnitMotion 才能判断何时复用 long path、何时重算
short path。
0 A.D. 还在 `PathGoal` / `LongPathfinder` 中保留 `maxdist` / waypoint spacing
约束，并支持 excluded circular regions 作为单次 query input。

主要参考源码：`source/simulation2/helpers/LongPathfinder.h`、
`source/simulation2/helpers/LongPathfinder.cpp` 和
`source/simulation2/components/CCmpUnitMotion.h`。

### 完成后获得什么能力

- adapter 不再用 `path.is_empty()` 猜所有失败原因。
- adapter 可以显式要求 raw / compressed / max-spacing-clamped path。
- adapter 可以把“本次 query 避开这些 navigation 区域”作为 input 传给 core，而不是
  修改全局地图。
- lab 可以比较 raw / refined path，不把 metrics 写成纯 HUD 逻辑。
- 后续 short-range 和 queue 可以消费更明确的 long-path metadata。

### 依赖和连续性

- 依赖 Feature 4。
- 如果引入 result DTO，必须一起更新 facade、queue、public API、usage example、smoke。
- path post-processing 必须证明不穿过 static obstruction，不改变 reachability 语义。
- excluded regions 是 path query input，不带 game meaning；adapter 决定为何避开某区域。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 需要显示或记录 core result metadata：

- raw waypoint count vs refined waypoint count。
- max waypoint spacing 是否生效，且不制造穿墙段。
- excluded region query 是否只影响本次 path，不污染后续 query。
- canonicalized / unreachable status。
- path length / detour ratio 可以作为 lab metric，但 metric 本身不是 core policy。

### 用户可以在 lab 手动验证什么

- 绕建筑移动时，raw / refined path 可以切换或显示差异。
- refined path waypoint 更少，但不会穿过障碍。
- 开启 max-spacing clamp 后，长直线路径被切成更密 waypoint。
- 标记一个临时 excluded circle 后，本次 path 会绕开该区域；关闭后恢复正常。
- 点击不可达点时 HUD 显示 canonicalized / unreachable，而不是只看单位有没有动。

### 自动验证命令

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

## Feature 6: Filtered Short Query And Line Validation

### 增加什么插件能力

强化 `SimNavVertexPathfinder`、obstruction filter 和 movement-line validation 作为
local precision query primitives：

- 定义 `SimNavObstructionFilter` 契约或等价的 named factory / callable filter
  contract，用于按 tag、flags、control group、moving state 过滤 obstruction shapes。
- `avoid_moving_units`、`control_group`、`control_group_2`、target/self ignore 的语义
  从 short-path special fields 收敛为 filter protocol。
- `get_obstruction_shapes_in_range()`、short path query、line validation 都能使用同一套 filter。
- 增加 movement-line validation primitive：检查一段 movement line / swept radius 是否
  穿过 impassable navcell 或 filtered obstruction shape。
- static OBB、unit circle、blocked navcell、line-of-sight edge case 统一覆盖。
- range-limited query 失败时返回明确 status，而不是让 adapter 猜。
- long path segment -> short path target 的消费方式写清楚。

这里不实现 steering、push/yield、unit priority 或 deadlock resolution。line validation
只回答“这一步是否合法”；失败后 retry、stop、stuck、push 都是 consumer policy。

### 0 A.D. 对应思想

0 A.D. 的 short-range / vertex pathfinder 在 obstruction edges 上跑可见性图，用
`avoidMovingUnits=true` 把动态单位纳入局部路径，用 group filter 跳过同 formation /
同控制组单位。它不是独立 steering force，也不是 formation controller。
0 A.D. 还把 `CheckLineMovement()` / `CheckMovement()` 作为 UnitMotion step 前的
navigation query，并用 `IObstructionTestFilter` 统一表达哪些 shape 参与查询。

主要参考源码：`source/simulation2/helpers/VertexPathfinder.h`、
`source/simulation2/helpers/VertexPathfinder.cpp` 和
`source/simulation2/components/ICmpObstructionManager.h`。
movement-line validation 另见 `source/simulation2/helpers/Pathfinding.cpp` 和
`source/simulation2/components/ICmpPathfinder.h`。

### 完成后获得什么能力

- core 可以回答“在当前局部动态障碍快照下，是否存在一条短路径”。
- core 可以回答“这段 movement line 在当前 map/filter 下是否合法”。
- adapter 可以复用同一套 filter contract，而不是每个 query 增加新的 bool 字段。
- adapter 可以用同一套 short-path primitive 实现动态避让、贴边绕角、接近目标。
- lab 的 `D` / `G` toggle 可以验证 query filter，而不是隐藏在 movement policy 里。

### 依赖和连续性

- 依赖 Feature 2 的 clearance / obstruction raster 语义。
- 依赖 Feature 3 的 obstruction lifecycle。
- 可以与 Feature 5 并行，但 queue 集成应等 Feature 5 result contract 稳定后再做。
- filter contract 和 line validation 应连续完成；否则 short path、shape query 和 step
  validation 会继续各自发明过滤语义。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 需要维持 application policy 边界：

- lab 决定何时重算 short path、多久重算一次、是否 fallback long path。
- lab 可以实现 formation slot / group command，但 core 只接收 filter input。
- lab 的 overlap resolution / push behavior 不进入 core。
- lab 可以在 step 前调用 line validation；如果失败，lab 自己决定 retry、stop、push 或 stuck。

### 用户可以在 lab 手动验证什么

- `D` 开关 dynamic unit avoidance 后，同一命令的 short path 结果有可解释变化。
- `G` 开关 group filter 后，同组单位是否互相当成动态 obstruction 有可解释变化。
- 同一组 shape query、short path query、line validation 使用相同 filter 时结果一致。
- 靠近 static obstacle corner 移动时，short path 能给出真实角度 waypoint。
- 手动拖出一段穿墙 movement line 时，line validation 返回 blocked；沿空旷区域移动时返回 pass。
- 两个单位窄路相向时，如果仍然 deadlock，HUD 应暴露这是 lab movement policy 问题，不是 core query 结果缺失。

### 自动验证命令

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

## Feature 7: Request Queue Budget / Worker Contract

### 增加什么插件能力

把 path request queue 发展成稳定调度层：

- long / short request ticket lifecycle 一致。
- enqueue 时 clone request data，caller 后续 mutation 不影响队列。
- cancellation、result collection、pending/result count 语义稳定。
- frame-budgeted processing 和 worker batch 的结果顺序可预测。
- queue diagnostics 能暴露每 tick 处理数、pending、cancelled、stale result。

core 只负责 request scheduling，不负责“某个单位什么时候应该重算 path”。

### 0 A.D. 对应思想

0 A.D. 的 UnitMotion 发 long / short path async ticket，pathfinder 每 turn 有处理预算，
worker 算完后按 ticket 回传结果。这样大量单位同 turn 下命令不会阻塞主线程。

主要参考源码：`source/simulation2/helpers/Pathfinding.h`、
`source/simulation2/components/CCmpPathfinder.cpp` 和
`source/simulation2/components/CCmpUnitMotion.h`。

### 完成后获得什么能力

- adapter 可以把 N 个单位的 path query 分摊到多个 tick。
- lab 高单位数命令不会因为同步算完所有路径而长帧。
- cancellation 和 stale result 有明确 contract，避免单位目标改变后吃到旧 path。

### 依赖和连续性

- 依赖 Feature 4-6 的 query/result contract。
- 必须连续覆盖 enqueue、clone、cancel、budget process、worker start/collect、stale result。
- 不要把 lab replan cadence 上提；queue 只提供预算执行机制。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 需要通过 adapter 使用 queue：

- lab 负责每 tick 允许多少 request。
- lab 负责目标改变时取消旧 request。
- lab HUD 可以显示 pending / processed / cancelled，但不定义 core policy。

### 用户可以在 lab 手动验证什么

- 框选全部单位右键移动时，pending queue 会逐步下降。
- 快速连续下多个目标命令时，旧 ticket 不会覆盖新目标。
- 高单位数场景中输入仍可交互，没有明显单帧卡死。

### 自动验证命令

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

## Feature 8: Scale Diagnostics And Perf Scenarios

### 增加什么插件能力

在 core 层提供 navigation diagnostics 和 scale evidence，而不是只加 lab HUD：

- map size、navcell count、terrain/static/dynamic obstruction count。
- dirty recompute scope、hierarchical recompute cost、JPS cache hit/miss。
- long / short query count、expanded nodes、path length、queue latency。
- external read-only exports：connectivity grid per passability class、accumulated
  dirtiness payload / flush API。
- benchmark-only scene 和 correctness smoke 分开标记。

diagnostics 只描述 navigation 机制，不描述 game-specific movement policy 是否“手感好”。

### 0 A.D. 对应思想

0 A.D. 的 pathfinding 能支撑大地图和数百单位，靠的是分层数据、增量更新和 async budget。
scale 工作必须知道成本落在 terrain raster、hierarchical、long path、short path 还是 queue。
0 A.D. 还把 pathfinder dirtiness information 和 hierarchical connectivity grid 作为
只读数据导出给外部 consumer。

主要参考源码：`source/simulation2/components/CCmpPathfinder.cpp`、
`source/simulation2/helpers/LongPathfinder.h` 和
`source/simulation2/helpers/VertexPathfinder.h`。

### 完成后获得什么能力

- 知道当前 addon 可以安全支持的地图尺寸、obstruction 数量、单位 query 数量。
- 后续优化有 baseline，而不是凭肉眼判断“好像更顺”。
- 可以区分 core pathfinding 性能瓶颈和 lab movement policy 问题。
- AI、debug tools 或 future examples 可以读取 connectivity / dirtiness 数据，而不依赖
  internal helper implementation。

### 依赖和连续性

- 依赖 Feature 3 的 dirty/cache lifecycle。
- 依赖 Feature 7 的 request queue contract。
- benchmark-only scene 不应作为 correctness gate；正确性仍走 `simnav/smoke` / `rtslab/smoke`。
- read-only exports 必须返回 DTO / snapshot，不允许外部直接修改 core internal grids。

### Example 需要配合什么应用层验证

`rts-pathfinding-lab` 可以提供 larger-map / higher-unit-count preset：

- app layer 负责生成 playable scenario。
- core diagnostics 负责暴露 navigation cost。
- lab 可以显示 connectivity / dirty export，但不能把显示逻辑做成 core API。
- formation、push/yield、deadlock policy 仍只作为 lab behavior 观察项。

### 用户可以在 lab 手动验证什么

- 切换大地图 / 高单位数 preset 后，HUD 显示 query、queue、cache、dirty 指标。
- 大量单位重规划时 pending queue 可观察，scene 不长时间冻结。
- 添加 / 删除障碍后，dirty scope 和 path 更新可解释。
- 切换 passability class 后，connectivity view / region count 有可解释变化。

### 自动验证命令

correctness gate：

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

如果新增 benchmark-only scene，应在对应 docs 中标清运行方式和判读标准，不把它混进
必须稳定为 0/1 的 correctness smoke，除非阈值已经足够稳定。

## Example Application Policy Track

这些任务可以在 `rts-pathfinding-lab` 做，但默认不是 core addon feature：

| Lab capability | Why useful | Why not core |
|---|---|---|
| Formation slot assignment | 验证 multi-unit command 是否能消费 core path / group filter。 | slot shape、rank、priority 是玩法策略。 |
| Push / yield policy | 验证 dynamic avoidance 不足时应用层如何兜底。 | 谁让谁、推多远、何时放弃是游戏规则。 |
| Stuck / deadlock handling | 验证 core query 失败或局部阻塞时 app 如何恢复。 | retry cadence、failure behavior 是 movement policy。 |
| Selection / command system | 让 lab 可玩、方便手动回归。 | 与 navigation data structure 无关。 |
| Combat / resource / build rules | 未来可验证接近目标的用例。 | 属于 RTS gameplay，不属于 pathfinding addon。 |

如果未来做 formation，推荐只作为 lab validation goal：

- core 可以提供 `control_group` / query filter primitive。
- lab 负责 formation controller、slot assignment、rank ordering、final stopping layout。
- 手动验证应看“core navigation primitives 是否足够支撑应用层编队”，而不是把
  formation controller 做成 `sim-nav-map` API。

## Recommended `/goals` Split

不要用一个 goal 做完整 roadmap。推荐拆分：

1. `sim-nav-map-terrain-passability`
2. `sim-nav-map-clearance-rasterization`
3. `sim-nav-map-dirty-cache-lifecycle`
4. `sim-nav-map-reachability-goals`
5. `sim-nav-map-path-result-contract`
6. `sim-nav-map-filtered-short-query-line-validation`
7. `sim-nav-map-request-queue-contract`
8. `sim-nav-map-scale-diagnostics`
9. `rts-pathfinding-lab-formation-validation`（example-only，可选）

每个 goal 都应写清：

- 是否允许修改 `addons/sim-nav-map/{core,model,obstruction,pathfinding}`。
- 是否允许修改 `addons/sim-nav-map/examples/rts-pathfinding-lab`。
- 新 smoke 应注册到 `simnav/smoke` 还是 `rtslab/smoke`。
- 是否需要用户在 Godot editor 中手动验证 lab scene。
- `addons/sim-nav-map/docs/references/0ad-source/` 不提交。

## Final Checklist For Any Roadmap Item

- Core addon 增长的是 navigation mechanism，不是 game policy。
- Terrain / map data 被当成 pathfinding 基础输入，而不是 debug-only 数据。
- 0 A.D. 参考的是分层思想和数据流，不复制 GPL source。
- 源码证据和 deferred item 先写进 [`roadmap-refs/`](roadmap-refs/)，不要塞进主路线。
- `rts-pathfinding-lab` 是 adapter consumer / playable regression。
- Formation 可以做 example validation，但不是 core plugin target。
- 完成后至少跑：

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
git -C addons diff --check
```
