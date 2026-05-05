# 0 A.D. 阅读笔记 / 疑问与自答

> 配套深度文档:
> - [`0ad-architecture-overview.md`](./0ad-architecture-overview.md)
> - [`0ad-data-flow.md`](./0ad-data-flow.md) ← 详细数据结构和数据流在这
> - [`0ad-pathfinding.md`](./0ad-pathfinding.md)
> - [`0ad-vs-inkmon-rts.md`](./0ad-vs-inkmon-rts.md)

---

## Q1. Terrain Tile Grid

> 地图渲染层,材质球 + 高度贴图 (shader 在不同高度使用不同的贴图的意思),是吗?

**部分对,但不完全是 shader-driven**。

实际是这样:

```
Terrain Tile Grid 是一个 2D 数组,每个 tile 存:
  - 高度值 (vertex height,用于 mesh 顶点位置)
  - 一个 texture index (指向某张 texture 资源)
  - mini-patch 信息 (相邻 tile 之间的 blend)
```

跟你想的"一个 shader 按高度切贴图"**不一样**。0 A.D. 的做法是:

1. **每个 tile 显式记录用哪张材质** (草 / 沙 / 雪 / 泥...) —— 这是地图作者在编辑器里手刷的,不是 shader 自动算的
2. **mesh 顶点高度** 来自 tile 的 height 值,渲染时插值
3. **相邻 tile 之间的 blend** 由 patch 系统在 shader 里做 alpha 混合,让两种材质过渡自然

所以"高度贴图 + shader"的部分**只是渲染细节**,真正存数据的是 `Grid<TerrainTile>` —— 高度 + 材质 index + ... 都在 CPU 端 grid 里。

**关键认知**: Terrain Tile Grid **不参与寻路**。它只管渲染。寻路用 Navcell Grid (4× 分辨率,见 Q2)。两者唯一交集是: 生成 Navcell Grid 时,会读 Terrain 的高度 / 水深 / 材质 来判定每 navcell 对每 class 是否可通行 (比如水 tile 上的 navcell 对 ship class 通,对 infantry class 不通)。

---

## Q2. Navcell Grid

### 2a. "4× 上层分辨率"是什么意思?

```
  Terrain Tile (粗,渲染用)        Navcell (细,寻路用)
  ┌──────────────┐                ┌──┬──┬──┬──┐
  │              │                │  │  │  │  │
  │              │                ├──┼──┼──┼──┤
  │   1 个 tile  │   ====>        │  │  │  │  │
  │              │                ├──┼──┼──┼──┤
  │              │                │  │  │  │  │
  │              │                ├──┼──┼──┼──┤
  └──────────────┘                │  │  │  │  │
                                  └──┴──┴──┴──┘
                                  4×4 = 16 个 navcell
```

代码 (`helpers/Pathfinding.h`):

```cpp
inline constexpr int NAVCELLS_PER_TERRAIN_TILE = TERRAIN_TILE_SIZE / NAVCELL_SIZE_INT;
// 默认 TERRAIN_TILE_SIZE=4, NAVCELL_SIZE_INT=1 → NAVCELLS_PER_TERRAIN_TILE = 4
```

意思是: **一个渲染 tile 边长 = 4 个寻路 navcell 边长**。一个 tile 内部包含 4×4 = 16 个 navcell。

**为什么要分两套分辨率?**

- **渲染 tile 粗**: 因为渲染是按 mesh patch 来的,mesh 顶点不需要太密 (太密 GPU 顶点处理爆炸),256×256 个 mesh 顶点已经够大地图。
- **navcell 细**: 因为单位很小 (clearance 0.8 navcell),如果寻路 grid 太粗,小的窄道根本绕不出去 (1 个 tile 宽的缝隙 navcell 看是 4 cell 宽,完全够过)。

类比: 渲染 = "地图大概什么样"; navcell = "单位脚印精确到哪一寸"。

### 2b. 16-bit 真的够吗? 加新类型咋办?

**够,而且这是设计选择,不是语言限制**。

**16 个 class 在 RTS 里非常多**。0 A.D. 默认游戏配置只用了 ~6-8 个 class:

```xml
<!-- pathfinder.xml 实际配置示意 -->
<default>          <!-- bit 0: 普通步兵 -->
<infantry>         <!-- 通常等价 default -->
<large>            <!-- bit 1: 大型陆战 (战象/弩车) -->
<ship-small>       <!-- bit 2: 小船 -->
<ship-medium>      <!-- bit 3: 中船 -->
<ship-large>       <!-- bit 4: 大船 -->
<ship-warship>     <!-- bit 5: 战船 -->
<unrestricted>     <!-- bit 6: 无视一切 (用于 builder 校验等) -->
```

剩下 8-10 bit 留给 mod / 特殊 case (两栖 / 攻城 / 飞行 / 隐形 / ...)。

**加新类型的两种情况**:

| 情况 | 怎么办 |
|---|---|
| ≤ 16 类总数 | **直接加配置**: 在 `pathfinder.xml` 里加一个 `<my-new-class>...</my-new-class>` 段,引擎自动分配下一个 bit。**不改任何代码**。 |
| > 16 类 | **改宏 + 重编**: `PASS_CLASS_BITS = 16` 改成 32 (`u16` → `u32`),整张 grid 内存翻倍,所有按位操作不变。**~5 行改动**。 |

**16 不是硬性限制,是性能与简洁的平衡**:
- `u16` 一张 1024×1024 grid = 2 MB,缓存友好
- `u32` 同样大小 = 4 MB,仍可接受
- `u64` = 8 MB,也行
- 但 16 个 class 已经覆盖 99% 真实需求,扩到 32 没必要

**对我们的启示**:

我们当前 `MovementLayer.GROUND/AIR` 二选一 enum 是 **"用语言枚举表达类型"**,扩展要改 enum + 改所有 switch。0 A.D. 是 **"用 bit 位表达类型"**,扩展只改 XML。

迁移时我们 GDScript 没有 `u16`,但 `int` 64-bit 完全够用,可以直接照搬位掩码方案,扩展性一步到位。

### 2c. NavcellData 的精彩之处

回到本质 —— 这个设计的真正优雅在 **判定算法**:

```cpp
#define IS_PASSABLE(navcell, class_mask) (((navcell) & (class_mask)) == 0)
```

**1 次按位与 + 1 次比较 = 判定一个单位能不能过这格**。无 if-else,无字典查询,无 enum 比较。CPU 一个 cycle。

A* 跑全图 1024² ≈ 100 万 navcell × 8 邻居 = 800 万次 IS_PASSABLE 调用,**全部走这个 1-cycle 操作**。这是 LongPathfinder 几毫秒跑完全图的根本。

我们如果用 `if (cell.movement_layer == MovementLayer.GROUND and cell.is_blocking)` 这种 GDScript 写法 → 每次判定要走 method call + property get + branch,慢 50-100×。**位掩码不是为了省内存,是为了把判定塞进 1 个 cycle**。

---

## Q3. Clearance

### 3a. 语义是什么?

**Clearance = 单位的"半径",但单位不是像素或米,是 navcell 数**。

```xml
<default>
  <Clearance>0.8</Clearance>     <!-- 普通步兵半径 = 0.8 个 navcell -->
</default>
<large>
  <Clearance>2.5</Clearance>     <!-- 战象半径 = 2.5 个 navcell -->
</large>
```

NAVCELL_SIZE = 1 米 (默认配置),所以 0.8 navcell = 0.8 米半径,2.5 navcell = 2.5 米半径。

物理意义:**单位身体能占的最大半径**,寻路时要保证这个半径范围内不撞障碍。

### 3b. "外扩"是干嘛的?

**核心思想**: A* 算的是"路径几何中心" (cell 中心连线),但单位有体积,身体会向两侧凸出。如果 grid 上某 cell 在障碍紧贴的位置标 "可通行",A* 会选它,但单位走过去身体会半个伸进障碍 → 视觉撞墙。

**解法:把"单位会撞"的事先算到 grid 里**。

```
A. 真实地图:                B. 朴素 grid (无 clearance):    C. 外扩 clearance=2 后:

                            障碍标 X,可通行标 .              障碍 + 周围 2 cell 都标 X

   ░░░░░░                    . . . . . .                    . X X X X .
   ░░██░░  (建筑 1 cell)     . . X . . .                    . X X X X .
   ░░░░░░                    . . . . . .                    . X X X X .
                             . . . . . .                    . X X X X .
```

- 在 B 上 A* 找路: 路径会贴着障碍 cell 旁边走,单位身体半个穿建筑 → 视觉撞墙
- 在 C 上 A* 找路: 路径离障碍至少 2 cell,单位半径 2 cell 走过去刚好不碰 → 视觉干净

**外扩 = 在生成 grid 时把每个障碍的 footprint 向外扩 `clearance` 个 navcell 标成不可通行,这样 A* 即使走 cell 中心连线,单位身体也不会撞**。

### 3c. 跟实际体积有啥关系?

直接关系: **clearance 就是单位的物理半径** (按 navcell 算)。

实际单位有 collision radius (碰撞圆),0 A.D. 的设计是: **collision radius = clearance** —— 寻路用的"我的大小"和碰撞用的"我的大小"是同一个数,不会出现"寻路觉得能过但碰撞觉得撞"这种 mismatch。

我们当前的问题就是 mismatch:
- A* 用 cell 中心 (默认半径 = 0)
- collision radius = 14 px
- 所以 A* 找的路对单位身体来说太挤 → 单位需要 separation force 兜底 → 一旦 sep 推不开就卡

把"单位半径"统一**进**寻路 grid (= clearance 设计) 是结构性解。

### 3d. 什么叫 passability grid?

**Passability grid = 每个 class 一份的 `Grid<NavcellData>`,记录"对这个 class 来说每 navcell 能不能过"**。

更准确说:

```cpp
// 启动时一次性预计算:
for each navcell (i, j):
  for each pass_class (例: infantry, large, ship-medium, ...):
    can_pass = check_terrain(i, j, passClass)         // 高度/水深合适?
            && !any_static_obstacle_in_clearance(i, j, passClass.clearance)  // 外扩后没静态障碍
    if !can_pass:
      grid[i][j] |= PASS_CLASS_MASK_FROM_INDEX(passClass.bit)  // 这个 class 不能过这格
```

**结果**: 单一一张 `Grid<NavcellData>` 同时包含所有 class 的可通行信息。查询任何 class 走 1 个按位与。

**注意**: "passability grid" 和 "navcell grid" 在 0 A.D. 语境里**是同一个东西**。叫法不同侧重点不同:
- Navcell grid → 强调"这是个细分辨率寻路网格"
- Passability grid → 强调"它存的是通行性信息"
- 实际数据结构都是 `Grid<NavcellData>` (= `Grid<u16>`)

每个 pass_class 各自有一份逻辑视图 (通过位掩码筛出来),但物理上共享同一张 grid。

---

## "数据结构很高级很有智慧"——确实是,但智慧在哪?

不是某一个结构本身高级,**是组合方式高级**。把每条单看都很朴素:

| 单看 | 朴素吗? |
|---|---|
| 二维数组 grid | 朴素 |
| 位掩码 | 朴素 |
| flood-fill | 朴素 |
| A* | 朴素 |
| visibility graph | 朴素 |
| OBB / 圆形 shape | 朴素 |

**真正的智慧在它们的关系**:

1. **同一份数据,多种视图** —— 一张 navcell grid,16 个 class 各自看到自己的可通行性。一份 ObstructionManager,既给寻路 rasterize 用,又给精确碰撞用。
2. **粗细分层匹配各自用途** —— 渲染粗 (256²),寻路细 (1024²),可达性查询粗 (11×11 chunks)。每层的分辨率精确匹配它的访问模式。
3. **一处真相,多处缓存** —— ObstructionManager 是 shape 的真相,grid 是它的缓存,GlobalRegion 是 grid 的缓存。dirtinessGrid 串起增量更新,缓存自动失效。
4. **静态预计算 + 动态增量** —— passability 启动时全图刷一次,以后只刷脏区。承担一次性的高代价换运行时近零代价。
5. **物理意义深嵌结构** —— Clearance 不是 runtime 检查,是嵌进 grid 的"我已经替你考虑了半径"。MoveRequest 的 minRange/maxRange 不是 caller 自己判,是 motion 系统的一等公民。

**这些设计原则不是 0 A.D. 独有的**,是 game engine 工业界几十年沉淀:
- "数据驱动" (data-driven design)
- "缓存友好" (cache-coherent layout)
- "AoS vs SoA" 的取舍
- "粗细分层" (level-of-detail)
- "静态预计算 + 动态增量"
- "single source of truth"

**这些原则我们 inkmon 也能 / 应该用**。语言不同 (GDScript vs C++) 不影响原则,只影响常数。GDScript 里 `Dictionary[Vector2i]` 和 C++ `Grid<u16>` 性能差 10-100 倍,但**算法复杂度同级,用同样的设计原则照样跑得过来**。

我们当前 RTS 用的是"面向对象 + 直觉" (RtsBattleGrid 是个 Dictionary,RtsBuildingActor 是个有方法的对象,寻路是个调用) —— 这种风格在小规模时直观,但每加一个能力 (multi-class / clearance / hierarchical / group filter) 都得改既有数据结构,会越来越难加。0 A.D. 那种"数据 + 算法分离 + 多视图共享同一份数据" 的风格,前期要多想一步,但每加一个能力是"加配置 + 加一段算法",不动既有数据结构。

**这就是为什么觉得"高级"** —— 它把"未来要加什么能力"提前用数据结构留好接口,扩展时只动算法不动数据 → 看起来像"早就想到了"。

---

## Q4. Long + Short 两层路径是不是"动态避障"? 是不是同 tick 共同协商?

> 所以它是通过长距离+短距离频繁计算来实现了类似动态避障的效果的?
> 这个好像需要所有单位由同一个 tick 共同控制才能做到吧?
> 就类似,我在这一小个区域内,大家重新计算一次短途路径,防止各自冲撞,我的理解对吗?

**方向对,但要校正一个关键概念**:

❌ **不是** "大家在小区域内协商一次,防止冲撞"
✅ **是** "每个单位独立地、按自己节奏地、基于此刻其他人的位置快照,重算自己的 short path 来绕开当下障碍"

### 4a. 实际机制 (一个 turn 的内部时序)

```
Turn N 开始:
  ↓
所有 unit shape 当前位置已经写在 ObstructionManager 里 (上 turn 末更新)
  ↓
Update_MotionUnit 消息 dispatch (按 entity 顺序逐个处理):
  unit_A.HandleMessage():
    判定: 我需要 short path 重算吗?
      条件 = (long path 段还没完 + 离当前 short path 终点近 + ...)
      → 一般每隔几 turn 重算一次,不是每 turn
    如果需要:
      ComputeShortPathAsync:
        读 ObstructionManager 周围 56 navcell 内所有 shape
        (包括其他单位,但同 group 跳过)
        → 算出绕开他们的 short path
  unit_B.HandleMessage():  # 同上,但 B 看到的"周围单位"包括 A 当前位置
  unit_C.HandleMessage():
  ...
  ↓
有 short path 的单位走一步:
  step = ...
  ICmpPosition::MoveTo(new_pos)
  ICmpObstructionManager::MoveShape(my_shape, new_pos)  ← 立刻更新 shape 位置
  ↓
Turn N 结束
  ↓
Turn N+1: 重复
```

### 4b. 三个关键点

**(1) 不是"协商",是"读快照"**

每个单位重算 short path 时,读的是 ObstructionManager **此刻的快照**。它不知道 unit_B 下一秒打算往哪走 —— 它只看 unit_B 现在在哪。

所以严格说不是"避免冲撞" (互相协商一致),而是 **"基于此刻其他人的位置,我绕开他们当前占的格子"**。如果两人面对面冲过来,A 重算时 B 在某位置,B 重算时 A 在另一位置,**两人各自基于对方的"当前快照"绕开,可能仍然撞** —— 然后 `m_FailedMovements++`,触发再次重算 + backup hack。

这就是为什么需要 `m_FailedMovements` 兜底 + `ALTERNATE_PATH_TYPE_DELAY` (long/short 互相切换试探) —— 单纯的 short path 重算不能完全避免冲撞,需要"卡住后再跳出来"的反馈机制。

**(2) "同 tick 共同控制" 是必要前提,但不是充分条件**

是的,所有单位在同一个 sim tick 内被处理,共享同一份世界状态 —— 这是 **必要条件**。如果不同步 (各客户端独立异步推进),不同 client 看到的 ObstructionManager 状态会发散,确定性完蛋。

但同 tick **不保证不撞**:
- 同 tick 内 A 先跑 → 看 B 在 (10, 10) → A 决定绕 (10, 10) → A 走到 (10, 11)
- 同 tick 内 B 后跑 → 看 A 已经在 (10, 11) (因为 A 先动) → B 决定绕 (10, 11) → B 走到 (10, 9)
- 大概率成功,但万一两人都试图占同一格,后跑的 CheckMovement 失败,`m_FailedMovements++`

**真正避免冲撞的是 5 个机制叠加**:
- ✅ 共享 sim 状态 (基础)
- ✅ Group filter (同队不互相绕,转用 push 力)
- ✅ Push (`UnitMotionManager` 在 turn 末有一个 push pass,把重叠的 unit 互相推开)
- ✅ `m_FailedMovements` 反馈 + backup hack (兜底)
- ✅ short path 频繁重算 (主动绕)

**(3) 为什么"同区域协商"那种设计不存在 —— 因为那是 RVO**

你描述的 **"我在这一小区域内,大家重新计算一次短途路径,防止各自冲撞"** —— 这其实是 **RVO / ORCA** (Reciprocal Velocity Obstacles) 那一类算法的思路,Unity / UE 的 crowd 系统底层用的就是这个。

RVO 的核心: **每个 agent 算出"我希望的速度",但同时考虑"我邻居希望的速度",通过几何方法算出"既能让我朝目标走又不会撞邻居的速度"**。这是真正的"同区域协商"。

0 A.D. **没用** RVO,选了更朴素的 short path 重算方案。

| 方案 | 流畅度 | 高密度表现 | 实现难度 | determinism 友好 |
|---|---|---|---|---|
| **0 A.D. short path 重算** | 中等 (离散路径替换) | 易卡 (一群挤窄缝时各自 short path 互相干涉) | 中 | ✅ 整数运算友好 |
| **RVO / ORCA** | 高 (连续速度调整) | 流畅 | 高 (几何复杂) | ❌ 浮点跨平台问题 |
| **SC2 / WC3 Reforged** | 极高 | 流畅 | 极高 | 闭源,推测是 short path + RVO 两层叠加 |

### 4c. 对我们的启示

我们当前 **separation force** 的思路 **比** 0 A.D. 的 short path 重算 **更接近 RVO 简化版** (各自算斥力)。如果重构走 0 A.D. 路线,我们会:
- **失去** "实时连续避让"那种丝滑感 (sep force 是每帧调整)
- **得到** "更精确的路径绕障" (主动绕大障碍而不是被动被推)
- **得到** "高密度卡顿" (一群单位挤窄缝时容易僵住)
- **得到** "兜底机制" (FailedMovements / push 末尾 pass)

更现代的方案是 **两者结合**: short path 管"绕大障碍",RVO 风格管"最后几像素的微调避让"。0 A.D. 用的是工业 RTS 里偏"老派"那套,稳定但视觉上不如 SC2 流畅。

**重构决策点**: 我们重写 steering / avoidance 时,要明确选 0 A.D. 路线还是混合路线。0 A.D. 路线 deterministic + 简单,但视觉效果天花板存在;混合路线天花板更高,但需要把 RVO 那一层也设计好,工程量翻倍。

**已决策 (2026-05-03)**: 走 **0 A.D. short path + 保留简化 sep force 微调** 的混合方案。理由: 我们密度不高 (50-100 单位 vs 0 A.D. 的 200-500),不需要跨平台 (Godot WASM 浮点 OK),已有 sep force 实现。既享受 short path 主动绕障,又保留 sep force 最后几像素流畅微调。

---

## Q5. Clearance / Obstruction / Footprint —— 三个概念,各自一句话

| 概念 | 是什么 | 给谁用 | UE 类比 |
|---|---|---|---|
| **Footprint** | UI 形状 | 鼠标点选 + 选择圈渲染 | 仅 UI 选择框 |
| **Obstruction** | 物理形状 (单位=圆 / 建筑=OBB) | 寻路 + 碰撞检查 | `CapsuleComponent` |
| **Clearance** | 单位"半径"的数 | A* 寻路 + CheckMovement | `CharacterMovementComponent.NavAgentRadius` |

### 5a. 单位身上 Obstruction 半径 = Motion.Clearance,源码绑死

```cpp
// CCmpObstruction.cpp:228
case UNIT:
    m_Clearance = cmpUnitMotion->GetUnitClearance();   // 直接从 motion 读
```

**单位**: `obstruction.radius` 和 `motion.clearance` 永远是同一个数。
**建筑**: 没有 motion,obstruction 是独立的 OBB (`m_Size0 × m_Size1`)。

UE 的 `NavAgentRadius` 和 `CapsuleRadius` 也是默认相等(`Update Nav Agent with Owner's Collision` 开关控制),原则一样。

### 5b. 寻路算法实际用什么

```
单位 A 寻路 →
  读: 别人的 Obstruction shape (OBB / 圆)
  外扩: 按 A 自己的 Clearance
  A* 在外扩 grid 上找路
  CheckMovement 走线段时也用 A 的 Clearance
  ↑
  Footprint 一次都没出现
```

### 5c. Footprint 只在哪用

```
玩家鼠标点击
  ↓
GuiInterface 遍历 entity → if entity.Footprint.contains(x, y) → 选中
  ↓
画选择圈 (大小来自 Footprint)
```

**纯 UI**。从不参与寻路 / 碰撞 / 命中判定。

### 5d. 0 A.D. 的"碰撞"

**没有 UE 那种持续物理引擎**。撞的判定就 2 处:
1. **CheckMovement** —— 走一步前,这段线会不会穿别人 Obstruction。撞 = 拒绝走 + `m_FailedMovements++`
2. **Push pass** —— turn 末,两个单位 obstruction 圆重叠 → 互相推开

### 5e. Footprint 跟 Obstruction 真的可以不同 (建筑场景)

我们当前 Bug 1 的根因: `position_2d` (渲染) 和 `footprint_cells` 几何中心 (寻路) 偏 12-42 px。

0 A.D. 的解法是把 Position / Obstruction shape / Footprint shape **拆成 3 个独立数据**,各自定义自己的中心,**允许偏移就是设计**。

```
建筑:
  Position           (300, 250)  ← 渲染锚点
  Footprint shape    以 (300, 250) 为中心,矩形随意
  Obstruction OBB    以 (288, 224) 为中心,4×4
  → 三者各自定中心,不要求重合
```

### 5f. 一句话压缩

> Footprint 给 UI,Obstruction 给寻路+碰撞,Clearance 是单位寻路时它自己的半径数。
> 单位身上 Obstruction 半径 ≡ Motion.Clearance,源码绑死,永远相等。
> 真正可以不同的是 "Footprint vs Obstruction" 和 "Position vs Obstruction 中心" —— 这是修我们 Bug 1 的关键。

---

## Q6. 0 A.D. 没物理引擎,把 Motion 和 Obstruction 拆成两个 component 的价值大吗?

> 用户洞察: UE 拆 NavAgent / Capsule 是因为 **物理引擎需要真实 capsule + navmesh 需要简化抽象** → 两套数据天然不同。
> 0 A.D. 没物理引擎,所有寻路 / 碰撞都用同一份 Obstruction → 拆 Motion / Obstruction 还有意义吗?

### 6a. 老实承认: 对我们当前的可见需求,价值不大

UE 拆开的强动机里,物理引擎占大半。0 A.D. 拆开的动机更弱:
- 不是所有 entity 都同时有两个职责 (建筑没 motion,弹道没 obstruction) → 真理由,但代码组织级别
- Motion 内部状态高频变,Obstruction 几乎不变 → 真理由,但性能影响小
- ECS 风格的 "owner / reader" 分离 → 设计美感,边际收益小

**纯按当前可见需求**,0 A.D. 这层拆分确实可以合并成"一个组件 + 一个字段",对小项目没区别。

### 6b. 但 —— 我看不到的"未来需求"才是关键

0 A.D. 是 23 年沉淀的开源项目,这层拆分大概率沉淀了**当前看不到但未来会用上**的能力:

- 加载 / 序列化 时机不同 (Obstruction 出生注册,Motion 状态可暂时 detach)
- 编队 controller 是个虚拟 entity,有 Motion 但没 Obstruction (它不挡路)
- 受 Pack / Garrison / 变身机制影响时,Motion 可临时禁用,Obstruction 仍存在
- mod 想加"会动的建筑"或"不会动的炮塔",需要灵活组合
- ......(我列不出来的还有很多)

我连 0 A.D. 的全部代码都没看完,凭什么断言"这层不需要"?

### 6c. 工程铁律 —— 简化是单向操作

```
原样复刻 (拆开) → 后期发现没必要 → 合并 (易,改几个字段)
提前简化 (合并) → 后期发现需要拆 → 拆 (地狱,所有调用方都要改)
```

**默认选 "易拆难合" 的方向 = 先复刻,事后再决定**。

### 6d. 决策

**采纳用户策略**:
1. **先原样复刻 0 A.D. 的拆分** (Position / Obstruction / Footprint / Motion 四个独立 component)
2. **迁移到 Godot 跑起来后**,实际用一段时间,观察哪些拆分确实没用上
3. **再决定**是否合并 Motion + Obstruction (或其他简化)

**对我们的实际重构方案**:

| 重构后组件 | 对应 0 A.D. | 是否拆分 |
|---|---|---|
| Position | ICmpPosition | ✅ 拆 (渲染锚点独立) |
| Obstruction shape | ICmpObstruction | ✅ 拆 (寻路 + 碰撞 数据) |
| Footprint shape | ICmpFootprint | ✅ 拆 (UI 数据,可与 Obstruction 偏移 — 修 Bug 1) |
| Motion (单位) | ICmpUnitMotion | ✅ 拆 (拥有 clearance + 移动状态) |

四个 component 全保留,跟 0 A.D. 一样。**Motion.clearance 和 Obstruction.radius 数值绑死同步,但住在两个 component 里**。

### 6e. 这次我学到的

我之前两次给"简化合并"建议 —— 都是把 **"我现在看不出价值" 等同于 "没价值"**。这是 premature optimization 的典型: 拿不完整理解去否定成熟设计。

**正确姿态**:
- 看到成熟设计中"我看不出必要"的部分 → 默认假设它有理由,我没看到
- 想要简化它 → 必须举出**具体可以删的代码** + **删了不会触发什么场景**
- 举不出来 → 原样复刻,事后再说

