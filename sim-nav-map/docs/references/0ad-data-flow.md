# 0 A.D. 地图 / Agent 数据结构 + 完整数据流

> 来源:
> - [`source/simulation2/helpers/Pathfinding.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/helpers/Pathfinding.h)
> - [`source/simulation2/helpers/Grid.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/helpers/Grid.h)
> - [`source/simulation2/helpers/HierarchicalPathfinder.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/helpers/HierarchicalPathfinder.h)
> - [`source/simulation2/helpers/PathGoal.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/helpers/PathGoal.h)
> - [`source/simulation2/components/ICmpPathfinder.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/components/ICmpPathfinder.h)
> - [`source/simulation2/components/ICmpObstructionManager.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/components/ICmpObstructionManager.h)
> - [`source/simulation2/components/CCmpUnitMotion.h`](https://github.com/0ad/0ad/blob/master/source/simulation2/components/CCmpUnitMotion.h)
>
> 配套文档:
> - [`0ad-architecture-overview.md`](./0ad-architecture-overview.md) — 整体引擎架构
> - [`0ad-pathfinding.md`](./0ad-pathfinding.md) — 寻路子系统综述
> - [`0ad-vs-inkmon-rts.md`](./0ad-vs-inkmon-rts.md) — 与 inkmon RTS 的差距对比
> - [`0ad-learnings.md`](./0ad-learnings.md) — 阅读笔记 / 疑问 / 自答

---

## 0. 摘要

0 A.D. 的"地图"不是单一数据结构,而是 **三层不同分辨率的网格 + 一个独立的 shape 数据库** 的金字塔:

```
┌─────────────────────────────────────────────────────────┐
│ Terrain Tile Grid     (粗) ← 美术/高度图层               │
│ Navcell Grid          (细) ← 寻路位掩码图层              │
│ Hierarchical Chunk    (粗) ← 可达性查询图层              │
└─────────────────────────────────────────────────────────┘
   + ObstructionManager (非网格,真实 shape 数据库)
```

agent (会移动的单位) 持有 `CCmpUnitMotion` 组件,**同时存 long path 和 short path 两条路径**,通过 ticket 机制异步等寻路结果。

完整数据流: 玩家点击 → CommandQueue → UnitAI FSM → MoveRequest → Hierarchical 可达性 → LongPath A* → ShortPath visibility graph → step + CheckMovement → ICmpPosition::MoveTo。

---

## 1. 地图数据结构

### 1.1 三层网格金字塔

| 层 | 类型 | 分辨率 (典型) | 作用 | 谁更新 |
|---|---|---|---|---|
| **Terrain Tile Grid** | `CTerrain` (顶点高度数组 + texture index) | 256×256 tiles | 地形材质 / 高度图 / 地形类型 (草/沙/雪/水) | 地图加载时 + 编辑器 |
| **Navcell Grid** | `Grid<NavcellData>` 即 `Grid<u16>` | 1024×1024 navcells (4× tile) | 寻路位掩码,16 个 passability class 共存 | 启动时全图刷一次,之后增量 (按 dirtinessGrid) |
| **Hierarchical Chunk Grid** | `std::map<pass_class_t, std::vector<Chunk>>` | ~11×11 chunks (1024/96) | 可达性 O(1) 查询 (region + GlobalRegion) | 跟 Navcell 同步增量 |
| **ObstructionManager** | shape 列表 (`StaticShape` OBB / `UnitShape` 圆) | 数百~数千 entry | 真实形状,给 short pathfinder + 碰撞检测 + 建筑摆放检查 | entity 创建/移动/销毁时 |

### 1.2 NavcellData —— 16-bit 位掩码

```cpp
// helpers/Pathfinding.h:127-145
inline constexpr int PASS_CLASS_BITS = 16;
typedef u16 NavcellData;   // 1 bit per passability class (up to 16)

#define IS_PASSABLE(item, classmask) (((item) & (classmask)) == 0)
#define PASS_CLASS_MASK_FROM_INDEX(id) ((pass_class_t)(1u << id))
```

**一个 navcell 16 bit,每 bit 代表一个 class 不能通过**:

```
NavcellData (16 bits):
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ 0 │ 0 │ 0 │ 1 │ 0 │ 0 │ 1 │ 0 │ 0 │ 0 │ 0 │ 0 │ 0 │ 0 │ 0 │ 0 │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                  ↑               ↑
                 ship          large_infantry
                 不能过          不能过
```

判定 "infantry 能过这格?" = `(navcell & infantry_mask) == 0`,**一次按位与,O(1)**。

### 1.3 Passability Class —— 单位分类机制

每个 unit template (XML) 写自己的 `<PassabilityClass>infantry</PassabilityClass>`,引擎启动时从 `simulation/data/pathfinder.xml` 读所有 class 定义,按出现顺序分配 bit 位:

```xml
<PassabilityClasses>
  <default>
    <Clearance>0.8</Clearance>           <!-- 单位"半径",单位 = navcell 数 -->
    <MaxWaterDepth>0</MaxWaterDepth>     <!-- 不能下水 -->
    <MinShoreDistance>0</MinShoreDistance>
  </default>
  <large>
    <Clearance>2.5</Clearance>           <!-- 大单位,绕得更远 -->
    <MaxWaterDepth>0</MaxWaterDepth>
  </large>
  <ship-medium>
    <Clearance>3</Clearance>
    <MinWaterDepth>1</MinWaterDepth>     <!-- 反过来,必须在水里 -->
  </ship-medium>
</PassabilityClasses>
```

启动时 **预计算** `Grid<NavcellData>`: 对每 navcell,枚举所有 class,根据地形 / 高度 / 水深 / 障碍判定能否通过,把 16 个 class 的答案合成同一个 u16 写进格子。

**关键**: **同一张 grid 同时服务所有 class**,16 个 class 各自看到不同障碍 (丛林挡步兵不挡飞行,水挡陆战不挡船),存储成本只有一份 `Grid<u16>`。

### 1.4 Clearance —— 把单位半径"嵌进"网格

Clearance = 单位半径 (单位 = navcell 数,比如 `0.8` 表示 0.8 个 navcell)。

生成 passability grid 时,**对每个静态障碍向外扩 `Clearance` 个 navcell** 再写进 grid:

```
原始障碍 (1 个 navcell):       large class clearance=2 后:

. . . . . . .                  . X X X X X .
. . . X . . .                  . X X X X X .
. . . . . . .       →          . X X X X X .
. . . . . . .                  . X X X X X .
. . . . . . .                  . X X X X X .
. . . . . . .                  . . . . . . .
```

效果: A* 在这张 "已外扩" 的 grid 上找路 → 走出来的 navcell 中心连线**天然不会让单位骑在障碍上**。

每 class 一份 grid (因为 clearance 不同) → ObstructionManager 的 `Rasterize()` 负责为每 class 算各自的 grid。

### 1.5 ObstructionManager —— 形状数据库 (与 grid 平行)

```cpp
// components/ICmpObstructionManager.h:55-68
struct ObstructionSquare {
  entity_pos_t x, z;          // 中心
  CFixedVector2D u, v;        // 旋转 (两个正交单位向量)
  entity_pos_t hw, hh;        // 半宽 / 半高
};

// 静态 shape (建筑) - OBB,有旋转
tag_t AddStaticShape(entity_id_t ent, x, z, angle, w, h, flags, group);

// 单位 shape - 圆,无旋转,只有半径
tag_t AddUnitShape(entity_id_t ent, x, z, clearance, flags, group);
```

**双表示**:

| 数据 | 谁用 | 为什么 |
|---|---|---|
| `Grid<NavcellData>` | LongPathfinder (全图 A*) | 整数索引 + 位运算极快,1024² 全图 A* 几毫秒 |
| `ObstructionManager` shapes | VertexPathfinder + 碰撞 + 建筑摆放检查 | 真实 OBB / 圆,亚 navcell 精度,允许任意角度路径 |

ObstructionManager 顺便提供 `Rasterize(passClass, grid, dirtyOnly)` —— 把当前 shape 列表按 dirtinessGrid 增量写进 navcell grid,不每帧全图刷。

### 1.6 Hierarchical: Chunk + Region + GlobalRegion

```cpp
// helpers/HierarchicalPathfinder.h:60-90
typedef u32 GlobalRegionID;

struct RegionID {
  u8 ci, cj;   // 哪个 chunk
  u16 r;       // 此 chunk 内第几个 region
};

static const u8 CHUNK_SIZE = 96;  // 每 chunk 96×96 navcells

struct Chunk {
  u8 m_ChunkI, m_ChunkJ;
  std::vector<u16> m_RegionsID;
  u16 m_Regions[CHUNK_SIZE][CHUNK_SIZE];    // 每 navcell 属于哪个 region (0=不可通行)
};
```

**三步构造**:

1. **Per-chunk flood-fill**: 每个 chunk 内,把"连通的可通行 navcell"flood-fill 成一个 region。一个 chunk 内可能有多 region (被斜墙分开的两块草地)。
2. **Edge between chunks**: 相邻 chunk 接壤的 navcell 都可通行 → 在两个 region 之间加一条 edge。设计上**同 chunk 内的 region 之间永远没 edge** (连通的话早就同 region 了)。
3. **GlobalRegion flood-fill**: 把所有 region 当节点跑一遍 flood-fill,合并成 `GlobalRegionID`。**同 GlobalRegion = 一定可达,不同 GlobalRegion = 一定不可达**。

```cpp
// 查询变成 O(1)
bool IsReachable(navcell A, navcell B, passClass) {
  return GetGlobalRegion(A, passClass) == GetGlobalRegion(B, passClass);
}

// 真正的核心 API: 把"可能不可达的目标"修正成"最近可达点"
bool MakeGoalReachable(u16 i0, u16 j0, PathGoal& goal, passClass);
```

`MakeGoalReachable` 的工作流:
- 检查 goal 是否包含可达 navcell → 是,什么都不动,返回 true
- 不是 → 在 goal 周围 BFS 找最近的可达 navcell → 把 goal 替换成 POINT 类型的那一个 → 返回 false

**这就是 0 A.D. 玩家点击不可达点 (建筑里 / 孤岛上) 时单位"知道它去不了,走到最近能去的地方"的根本机制**。

### 1.7 Grid 类本身

```cpp
// helpers/Grid.h:33-65
template<typename T>
class Grid {
  u16 m_W, m_H;
  T* m_Data;     // m_Data[j*m_W + i]
  // ...
};
```

朴素的 2D 数组,模板化 cell 类型,支持序列化。`NavcellData (= u16)` 时是寻路 grid; `u8` 时是 dirtinessGrid; `u16` 也用作 `ConnectivityGrid` (每 navcell 标 GlobalRegionID)。

### 1.8 增量更新机制

```cpp
// HierarchicalPathfinder::Update(grid, dirtinessGrid)
// 只重算 dirtiness 不为 0 的 chunk
```

任何 `ObstructionManager::AddShape / MoveShape / RemoveShape` 都把受影响 navcell 标到 `dirtinessGrid` 里。下次 `Pathfinder::UpdateGrid()` 时:
- LongPathfinder 看 dirtiness 决定 grid 是否需要重 rasterize
- HierarchicalPathfinder 看 dirtiness 决定哪些 chunk 重算 region

**性能关键**: 每 turn 只动 1-2 个建筑时,只刷几个 navcell + 1 个 chunk,不重刷整图。

---

## 2. Agent 数据结构 (CCmpUnitMotion)

来源: `components/CCmpUnitMotion.h:130-260`

精简后字段:

```cpp
class CCmpUnitMotion {
  // === 静态模板 (从 XML 读,不变) ===
  fixed m_TemplateWalkSpeed;
  fixed m_TemplateRunMultiplier;
  fixed m_TemplateAcceleration;
  pass_class_t m_PassClass;            // 我属于哪个 passability class (16 选 1)
  std::string m_PassClassName;
  bool m_IsFormationController;        // 我是不是"虚拟队长" entity

  // === 动态身体属性 ===
  entity_pos_t m_Clearance;
  fixed m_WalkSpeed, m_RunMultiplier;  // 当前实际值 (可被 buff 改)
  bool m_FacePointAfterMove;
  bool m_Pushing;                      // 是否参与互相推开
  bool m_BlockMovement;                // 是否阻挡其他单位

  // === 反馈计数 (防卡死) ===
  u8 m_FailedMovements = 0;            // 连续多少 turn 移动失败,达到 35 → 报告 stuck
  u8 m_FollowKnownImperfectPathCountdown = 0;  // "我知道这条路不完美但先走着" 倒计时

  // === 速度状态 ===
  fixed m_SpeedMultiplier, m_Speed;
  fixed m_LastTurnSpeed, m_CurrentSpeed;
  fixed m_InstantTurnAngle, m_Acceleration;

  // === 编队归属 ===
  entity_id_t m_FormationController = INVALID_ENTITY;

  // === 当前移动请求 ===
  struct MoveRequest {
    enum Type { NONE, POINT, ENTITY, OFFSET } m_Type;
    entity_id_t m_Entity;               // 跟随哪个 entity
    CFixedVector2D m_Position;          // 目标点 / 偏移
    entity_pos_t m_MinRange, m_MaxRange; // 距离区间 (0~24 = 近战, 0~30 = 远程)
  } m_MoveRequest;

  // === 异步寻路 ticket ===
  struct Ticket {
    u32 m_Ticket = 0;                  // 0 = 没在等
    enum Type { SHORT_PATH, LONG_PATH } m_Type;
  } m_ExpectedPathTicket;

  // === 持有的两条路径 (反向存储, back() = 下一步) ===
  WaypointPath m_LongPath;             // 长程,cell-level
  WaypointPath m_ShortPath;            // 短程,任意角度 (绕动态单位)
};
```

### 2.1 关键设计决策对照

| 字段 | 0 A.D. | inkmon (RtsNavAgent) |
|---|---|---|
| 目标描述 | `MoveRequest` 4 种 (POINT/ENTITY/OFFSET/NONE) + min/max range | `final_target: Vector2` |
| 路径存储 | **two paths** (long + short) | 单条 `_path` |
| 异步等待 | `Ticket` 异步 ID | 同步,无 |
| 失败反馈 | `m_FailedMovements` 阈值 | `RtsStuckDetector` 平行系统 |
| "知道路不完美" | `m_FollowKnownImperfectPathCountdown` | 无 |
| 编队 | `m_FormationController` | 无 |
| passability | 16-bit class | 2 选 1 enum |
| 半径 | `m_Clearance` 嵌进寻路 | 仅用于 separation |

### 2.2 MoveRequest —— "去到 / 接近 / 跟随" 的统一抽象

```cpp
struct MoveRequest {
  enum Type { NONE, POINT, ENTITY, OFFSET };
  // ...
};

// 三种构造:
MoveRequest(pos, minRange, maxRange);              // 走到点附近 (距离在 [min,max])
MoveRequest(targetEntity, minRange, maxRange);     // 接近某 entity 到指定距离
MoveRequest(targetEntity, offset);                 // 跟随某 entity,保持 offset (编队 slot)
```

`MinRange / MaxRange` 把"接近目标后做事" (攻击 / 治疗 / 采集 / 修建) 统一成 range query,UnitMotion 不需要知道你接近后要干嘛 —— 只负责把单位送到 range 内,通知 UnitAI:"我到了"。

### 2.3 WaypointPath —— 反向数组

```cpp
struct WaypointPath {
  std::vector<Waypoint> m_Waypoints;   // 反向存储,m_Waypoints.back() = 下一个目标
};
```

**反向存的好处**: 单位走完一段就 `pop_back()`,O(1),不用 erase begin。

---

## 3. 完整数据流 —— 一次命令的生命周期

### 3.1 阶段 0: 命令进入 (跨 turn 边界)

```
玩家鼠标点击
   ↓
GuiInterface.js 把点击转成 SimulationCommand 入队
   ↓ (lockstep gate: 单机直接执行,网络等所有客户端同 turn 收到)
TurnManager 在下一 turn 开始时 dispatch command
   ↓
UnitAI.js 收到命令,根据当前 stance + 当前 order 决定要不要接受
   ↓
UnitAI 调用 ICmpUnitMotion::MoveTo(pos, minRange, maxRange)
```

### 3.2 阶段 1: MoveRequest 写入 (单 turn 内)

```cpp
m_MoveRequest = MoveRequest(target_pos, minRange, maxRange);
// 这一步只是"记下来",不立刻寻路
```

### 3.3 阶段 2: 寻路触发 (Update_MotionUnit 消息)

```
判定: 是否需要重新规划?
  - m_LongPath 空 → 必须规划
  - m_LongPath 末端不在目标附近 (target 移动了) → 必须重新规划
  - m_FollowKnownImperfectPathCountdown 到 0 → 重新规划
  ↓
先问 Hierarchical:
  bool ok = HierarchicalPathfinder::MakeGoalReachable(start, &goal, passClass);
  // 如不可达,会就地把 goal 替换成最近可达 navcell (变成 POINT goal)
  ↓
异步发起 LongPath 请求:
  ticket = ICmpPathfinder::ComputePathAsync(start, goal, passClass, my_entity);
  m_ExpectedPathTicket = {ticket, LONG_PATH};
```

异步 worker 在线程池跑 A*,算完发 `MT_PathResult` 消息回调:

```cpp
void HandleMessage(MT_PathResult& msg) {
  if (msg.ticket == m_ExpectedPathTicket.m_Ticket) {
    m_LongPath = msg.path;
    m_ExpectedPathTicket.clear();
  }
}
```

### 3.4 阶段 3: 执行移动 (每 turn Update_MotionUnit)

```
有 m_LongPath 后,每 turn 执行:
  ↓
取 long path 当前段 (back() = 下一个 cell-level waypoint)
  ↓
判定: 我离 long path 段太远 / 中间有新单位挡 → 需要 ShortPath
  ↓
异步请求 ShortPath:
  ticket = ICmpPathfinder::ComputeShortPathAsync(
    start, clearance, range,
    goal = long path 下一段 waypoint (近距离 SHORT_PATH_LONG_WAYPOINT_RANGE 圈内),
    passClass,
    avoidMovingUnits = true,
    group = m_FormationController,    // 同 formation 互不当障碍 (group filter!)
    notify = my_entity
  )
  ↓
ShortPath 算完后:
  m_ShortPath = msg.path;
  ↓
有 short path 时,实际"走":
  next_wp = m_ShortPath.back();
  step = (next_wp - cur_pos).normalize() * m_Speed * turnLength;
  new_pos = cur_pos + step;
  ↓
CheckMovement(cur_pos, new_pos):  # 验证这一小段是否可行
  能过 → ICmpPosition::MoveTo(new_pos);
        ICmpObstructionManager::MoveShape(my_unit_shape, new_pos);
  不能过 → m_FailedMovements++;
          重新申请 ShortPath
```

### 3.5 阶段 4: ShortPath 内部 (Vertex Pathfinder)

```
搜集当前周围 SHORT_PATH_MAX_SEARCH_RANGE (= 56 navcells) 内的:
  - 静态 obstruction shapes (建筑 OBB)
  - 动态 unit shapes (其他单位的圆),group != my_group 才算
  ↓
所有 shape 的角点,各自向外扩 my_clearance,取扩后顶点
  ↓
顶点之间能直线相连 (line-of-sight,不穿任何 shape) → 建 edge
  ↓
A* 跑这张 visibility graph
  ↓
得到一组任意角度 waypoints (不再是 cell 中心!)
```

**这就是 0 A.D. 转角能贴墙绕角而不 zig-zag 的根本原因**: short path 的 waypoints 是 **obstruction 外扩后的角点**,不是 cell 中心。

### 3.6 阶段 5: 抵达 / 失败

```
m_ShortPath 走完 + 离 final goal 在 minRange ~ maxRange 内 → 抵达
  ↓
通知 UnitAI 当前 order 完成 (CMessage MotionUpdate(success))
  ↓
UnitAI 切下一个 order (例: "抵达后开始攻击" → 进入 ATTACK 状态)

或者:
m_FailedMovements >= 35 → 报告 OBSTRUCTED
  ↓
UnitAI 决定: 放弃命令 / 重试 / 换目标
```

### 3.7 阶段 6: 编队的特殊处理

如果单位是 formation member, **它的 MoveRequest 不是来自玩家,是来自 Formation controller (虚拟 entity)**:

```
玩家点击 (选中编队)
   ↓
Formation entity 收到 MoveTo
   ↓
Update_MotionFormation 消息 (优先于 Update_MotionUnit):
   Formation 自己跑 long+short pathfinder → 算出整队整体路径
   Formation 给每个 member 算 slot offset (wedge / column / phalanx 队形)
   ↓
   每个 member 收到 MoveRequest(target=Formation, offset=slot_offset)
   ↓
Update_MotionUnit (在 formation update 之后):
   member 执行自己的 short path 跟随 slot,group=formation_id
```

**分阶段消息保证 formation 永远先于 member 一步**;member 永远跟着 formation 当前位置算 slot;short pathfinder 用 group filter 跳过同队成员;**所以队形不散**。

---

## 4. 完整数据流图

```
┌─────────────────────────────────────────────────────────────────┐
│ 玩家点击                                                          │
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ GuiInterface → CommandQueue → TurnManager (lockstep gate)       │
└──────────────────┬──────────────────────────────────────────────┘
                   ↓ (next turn)
┌─────────────────────────────────────────────────────────────────┐
│ UnitAI.js (FSM, stance) — 决定接受命令、转 MoveRequest          │
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ CCmpUnitMotion::MoveTo                                          │
│   写入 m_MoveRequest                                             │
└──────────────────┬──────────────────────────────────────────────┘
                   ↓ (Update_MotionUnit msg, every turn)
┌─────────────────────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ HierarchicalPathfinder::MakeGoalReachable                │  │
│  │   读: Chunk + Region + GlobalRegion 图                   │  │
│  │   写: 修改 PathGoal (替换不可达点)                        │  │
│  └────────────────────────┬─────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ LongPathfinder::ComputePathAsync (异步 worker thread)    │  │
│  │   读: Grid<NavcellData> (16-bit 位掩码) + clearance       │  │
│  │   算: A* + JPS                                            │  │
│  │   写: WaypointPath (cell-level)                           │  │
│  └────────────────────────┬─────────────────────────────────┘  │
│                           ↓ (MT_PathResult msg, 异步回调)        │
│  m_LongPath ← path                                              │
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ VertexPathfinder::ComputeShortPathAsync                  │  │
│  │   读: ObstructionManager 周围 56 navcell 内 shapes       │  │
│  │       + group filter (同 formation 不算障碍)              │  │
│  │       + clearance                                         │  │
│  │   算: visibility graph A*                                 │  │
│  │   写: WaypointPath (任意角度)                             │  │
│  └────────────────────────┬─────────────────────────────────┘  │
│                           ↓                                     │
│  m_ShortPath ← path                                             │
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ 每 turn step:                                                    │
│   next_wp = m_ShortPath.back()                                   │
│   step = (next_wp - pos).norm() * m_Speed * turnLength           │
│   if CheckMovement(pos → pos+step) ok:                           │
│     ICmpPosition::MoveTo(pos + step)  ← 真正改位置                │
│     ICmpObstructionManager::MoveShape(my_unit_shape, new_pos)    │
│   else:                                                          │
│     m_FailedMovements++                                          │
│     重新申请 ShortPath                                            │
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│ Renderer 在两 turn 间用 InterpolatedPosition 平滑                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. 最值得借鉴的 8 个设计决策

1. **NavcellData 16-bit 位掩码** —— 一张 grid 同时服务 16 种单位类型,O(1) 判定。多 layer 扩展定型方案。
2. **Hierarchical = chunk + region + GlobalRegionID 三层 ID** —— 复杂但思路简洁。`IsReachable` 比 A* 跑完才知道便宜 1000×。
3. **Long + Short 两条路径并存,Short 频繁重算 Long 不动** —— 既保性能又能动态避让。
4. **MoveRequest 4 种类型 + min/max range** —— 不只是"去这个点",而是"接近 entity 到 0~24 米范围内"。攻击 / 治疗 / 采集 / 修建全是 range-based,不是 point-based。RTS 一切"接近目标后做事"行为的统一抽象。
5. **m_FollowKnownImperfectPathCountdown** —— "我知道这条路不完美,但我先走着,N turn 后再重算" —— 防止目标不可达时每 turn 重算 A* 把 CPU 烧死。
6. **Formation = 虚拟 entity** —— 编队不是"管理一堆单位的对象",而是 sim 里真的放一个看不见的 entity,有自己的 CCmpUnitMotion + MoveRequest,真实单位订阅它的位置。这个抽象极其干净。
7. **Group filter** —— `ShortPathRequest.group = m_FormationController`,short pathfinder 跳过同 group 单位 → 同队伍不互相当障碍 → 编队不散。
8. **ObstructionManager 双表示 + 增量 Rasterize** —— shape 是真实数据,grid 是它的"快照",dirtinessGrid 控制只刷变化区域。
