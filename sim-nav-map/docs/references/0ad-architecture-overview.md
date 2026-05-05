# 0 A.D. 架构总览

> 来源: [github.com/0ad/0ad](https://github.com/0ad/0ad) (master, 已 archive,新仓在 gitea.wildfiregames.com)
> 范围: 引擎主架构 + 模拟层 (simulation2) + 游戏逻辑层 (mods/public)
> 目的: 在决定"是否照搬到 inkmon RTS"之前,先把 0 A.D. 自己的层次摸清。

---

## 0. 一句话

**双层 ECS:C++ 引擎处理性能敏感的 simulation core (寻路 / 渲染 / 序列化 / 网络),JavaScript 处理游戏规则 (UnitAI / Formation / 攻击 / 经济),两边通过 component interface 沟通。整套跑在 lockstep turn-based 模拟器上,fixed-point 数值保证跨平台 determinism。**

---

## 1. 顶层目录

```
0ad/
├── source/                              ← C++ 引擎 (63.7%)
│   ├── main.cpp                         ← 程序入口
│   ├── ps/                              ← Pyrogenesis engine 主循环
│   ├── simulation2/                     ← 模拟核心 (本文档重点)
│   ├── graphics/                        ← 场景图 / 模型 / 动画
│   ├── renderer/                        ← OpenGL/Vulkan 渲染
│   ├── network/                         ← lockstep 多人同步
│   ├── scriptinterface/                 ← C++ ↔ SpiderMonkey JS 桥接
│   ├── gui/                             ← XML/JS GUI 系统
│   ├── maths/                           ← Vector / Matrix / Fixed-point
│   ├── lib/, third_party/, ...
├── binaries/data/mods/public/           ← 游戏数据 + JS 逻辑 (24% C 是 SM 引擎)
│   └── simulation/
│       ├── components/                  ← JS 游戏逻辑组件 (~80 个)
│       ├── ai/                          ← 电脑 AI 脚本
│       ├── helpers/                     ← JS 工具
│       ├── data/                        ← 配置 (technologies / civs / ...)
│       └── templates/                   ← 单位/建筑/资源 XML 模板
├── build/, libraries/, ...
```

**一句话**: `source/` = C++ 引擎,`binaries/data/mods/public/` = 游戏 mod (默认 mod 就是"0 A.D. 这个游戏"本身)。引擎是引擎,游戏是 mod —— 这个分离是 0 A.D. 架构的根源。

---

## 2. 模拟层 (simulation2) —— 整个游戏的心脏

`source/simulation2/`:

```
simulation2/
├── Simulation2.cpp/h               ← 公共 API,外界唯一入口
├── MessageTypes.h                  ← 所有跨组件消息定义
├── TypeList.h                      ← 编译期组件注册
├── system/                         ← ECS 框架本身
│   ├── ComponentManager.cpp/h      ← 组件存储 + 调度 + 注册
│   ├── Component.h                 ← REGISTER_COMPONENT_TYPE 宏
│   ├── IComponent.h                ← 所有组件基类
│   ├── Entity.h                    ← entity_id_t = uint32 (纯 ID)
│   ├── EntityMap.h                 ← 高速 entity → component 表
│   ├── Message.h                   ← 消息基类
│   ├── DynamicSubscription.cpp/h   ← 运行时订阅 (JS 用)
│   ├── ParamNode.cpp/h             ← XML schema → 运行时配置树
│   ├── SimContext.cpp/h            ← 模拟全局上下文
│   ├── CmpPtr.h                    ← 组件指针 (类似 weak_ptr)
│   ├── TurnManager.cpp/h           ← 单机 turn 调度
│   ├── LocalTurnManager.cpp/h      ← 本地 turn (无网络)
│   └── ReplayTurnManager.cpp/h     ← 回放 turn (从录像读命令)
├── components/                     ← C++ 组件 (~30 个,性能敏感)
├── helpers/                        ← C++ 工具,寻路/几何/碰撞核心
├── scripting/                      ← C++ 组件暴露给 JS 的 binding
├── serialization/                  ← 整局序列化 (replay / network sync)
├── tests/                          ← cxxtest 单元测试
└── docs/                           ← 内部文档 (CCmpExample 是组件模板)
```

### 2.1 ECS 模型

- **Entity** = 纯整数 ID (`entity_id_t`),没有任何数据/行为
- **Component** = 一个具名 interface (`ICmpFoo`) + 至少一个实现 (`CCmpFoo` / `Foo.js`)。同一 entity 一个 interface 上只有一个 component 实例
- **ComponentManager** = 管所有 entity 上挂的所有 component。按 `(entity_id, interface_id)` 索引
- **Message** = 跨组件通信。组件订阅消息,manager 路由

**关键性质**: 同一个 interface 在同一 entity 上**只能有一个实现**,但实现可以是 C++ 或 JS。比如 `ICmpMotion` 这个接口,普通单位用 C++ 的 `CCmpUnitMotion`,飞行单位用 JS 的 `UnitMotionFlying.js`,投射物用 `MotionBall.cpp`。游戏看到的统一接口,实现可以换。

### 2.2 Turn-based 模拟 + 消息驱动 + 分阶段更新

整个游戏(包括看起来"实时连续"的部分)实际上是**离散 turn 模拟**:

- 默认 turn 长度 = 200ms (5 turns/sec, 单机) 或 500ms (网络)
- 每 turn 触发一连串 `CMessage*`,组件按订阅响应
- 渲染层在两 turn 之间插值 (`InterpolatedTransform`)

每个 turn 的消息序列 (摘自 `MessageTypes.h`):

```
TurnStart                        ← turn 开始,清缓存
Update                           ← 通用 update,顺序无关组件
Update_MotionFormation           ← 编队"控制器"先动 (虚拟 entity,管 slot)
Update_MotionUnit                ← 各单位跟着 formation 走
Update_Final                     ← 最终 update,after-the-fact 修正
... (还有 Interpolate / RenderSubmit 等渲染相关,跑在 turn 外)
```

**为什么分阶段**: formation controller 是个"看不见的虚拟 entity",它先决定整队往哪走,然后真实单位才跟进自己的 slot。如果不分阶段,单位先动 formation 再动,formation 跟不上。这就是 0 A.D. 编队"不散队"的根本原因。

### 2.3 Determinism

- **fixed-point**: 几乎所有数值用 `maths/Fixed.h` 的定点数 (`fixed`)。位置 / 速度 / 攻击范围 / 寻路距离 全是 fixed
- **lockstep**: 网络模式下所有客户端只交换玩家命令 (`SimulationCommand`),不同步状态。因为 sim 是 deterministic,每个客户端独立跑出同样结果
- **replay**: `ReplayTurnManager` 从 commands.txt 重放 → 每帧状态 bit-identical
- **OOSLog (Out-Of-Sync log)**: Hash 全 entity 状态,不一致时立刻定位是哪个 entity 偏了

---

## 3. 模拟层 (C++ components) —— 性能敏感的部分

`source/simulation2/components/`(只列重要的):

| 组件 | 职责 | 我们对应 |
|---|---|---|
| **CCmpPathfinder** | 寻路总入口,管 long/short 两个 pathfinder + obstruction grid | RtsPathfinding (差距大) |
| **CCmpObstructionManager** | 全场障碍数据库,给寻路提供 query | RtsBattleGrid (差距大) |
| **CCmpObstruction** | 单个 entity 的障碍 shape (圆 / OBB) | 部分在 RtsBuildingActor.footprint_cells (差距大) |
| **CCmpFootprint** | 视觉/选择 footprint (跟 obstruction 分开!) | 跟 obstruction 混在一起 |
| **CCmpUnitMotion_System / CCmpUnitMotion** | 单位实际移动逻辑,调用 pathfinder + 执行 step | RtsNavAgent + RtsUnitSteering |
| **CCmpPosition** | 单位位置 + 朝向 + 插值 | RtsActor.position_2d |
| **CCmpRangeManager** | 视野 / 攻击范围查询 + LOS (line-of-sight) | RtsAutoTargetSystem 部分 |
| **CCmpVision** | 单位视野 | 我们没视野系统 |
| **CCmpTerrain** | 高度图 / 地形类型 | 我们没地形 |
| **CCmpWaterManager** | 水面 (给两栖单位用) | 没 |
| **CCmpTerritoryManager** | 领土系统 (建筑控制范围) | 没 |
| **CCmpProjectileManager** | 投射物 | RtsProjectileSystem |
| **CCmpAIManager** | C++ 给 JS AI 的接口层 | RtsComputerPlayer |
| **CCmpCommandQueue** | 玩家命令队列 (lockstep 关键) | PlayerCommandStore |
| **CCmpTemplateManager** | 模板缓存 (entity prototype) | 各 *Config.gd |
| **CCmpRallyPointRenderer** | 集结点渲染 | 没 |

注意 C++ 组件几乎全是"基础设施"——不含游戏规则 (Attack / Heal / Resource 都不在这,见下面 JS 层)。

### 3.1 Pathfinding 子系统 (在 helpers/)

`source/simulation2/helpers/`:

```
Pathfinding.h                    ← navcell / passability class / Goal 定义
Grid.h                           ← 多类型 grid 数据结构
HierarchicalPathfinder.cpp/h     ← chunk + region 可达性 (O(1) IsReachable)
LongPathfinder.cpp/h             ← long-range A* + JPS (找全图路径)
VertexPathfinder.cpp/h           ← short-range visibility graph (绕动态单位)
PathGoal.cpp/h                   ← Goal 类型 (point / circle / inverse-circle)
Rasterize.cpp/h                  ← obstruction shape → grid 栅格化
Geometry.cpp/h                   ← OBB / circle / 距离计算
Spatial.h                        ← 空间索引
Los.h                            ← line-of-sight 视野
Position.h                       ← entity_pos_t (fixed-point 坐标)
Selection.cpp/h                  ← 框选
Render.cpp/h                     ← debug 可视化
```

**寻路三层调度** (CCmpPathfinder 协调):

```
玩家命令"去那"
    ↓
1. Hierarchical: 起点终点是否同 region? 不是 → MakeGoalReachable 找最近可达点
    ↓
2. LongPathfinder: A* + JPS 跑全图,得到 cell-level 路径
    ↓
3. UnitMotion 每 tick 取下一段
    ↓
4. VertexPathfinder: 在当前可见范围内重新计算 short-range,绕开移动单位
    ↓
5. CCmpUnitMotion 执行 step
```

每 tick 都跑 4-5,长路径不重算 (除非阻塞);转角、绕单位、动态避让全在 short-range 这层处理。

---

## 4. 游戏逻辑层 (JS components) —— 游戏规则

`binaries/data/mods/public/simulation/components/` 共 ~80 个 JS 组件。按职责分组:

### 4.1 单位 AI / 移动

- **UnitAI.js** —— 巨型 FSM,管"待命/移动/采集/攻击/巡逻/护卫/返回基地"等所有 order 状态。这是单位行为的中枢
- **UnitMotionFlying.js** —— 飞行单位 motion (覆盖 C++ 的 UnitMotion,直线飞)
- **MotionBall.js** —— 弹球类投射物 motion

### 4.2 编队

- **Formation.js** —— 编队 controller (管 slot 分配 / 队形选择 / 整体移动)
- **FormationAttack.js** —— 编队整体攻击行为

### 4.3 战斗

- **Attack.js** —— 攻击数据 (近战/远程/范围) + cooldown
- **Health.js / Resistance.js** —— HP + 抗性 (按伤害类型)
- **DeathDamage.js / DelayedDamage.js** —— 死亡 AOE / 投射物伤害
- **Heal.js** —— 治疗
- **Capturable.js** —— 建筑捕获
- **Auras.js** —— 光环效果
- **StatusEffectsReceiver.js** —— 状态效果

### 4.4 经济

- **ResourceSupply.js** —— 资源点 (树/矿) 数据
- **ResourceGatherer.js** —— 单位采集能力
- **ResourceDropsite.js** —— 卸货点 (基地)
- **ResourceTrickle.js** —— 时间累积资源
- **Cost.js / Loot.js** —— 单位/建筑造价 + 死亡掉落
- **Trader.js / Market.js / Barter.js** —— 贸易

### 4.5 建造 / 生产

- **Builder.js** —— 单位会盖建筑
- **BuildRestrictions.js** —— 建筑摆放限制 (距离/地形)
- **Foundation.js** —— 半成品建筑 (建造中)
- **AutoBuildable.js** —— 自动建造
- **ProductionQueue.js** —— 训练队列
- **Trainer.js / Researcher.js** —— 训练单位/研究科技
- **TechnologyManager.js** —— 科技树
- **TrainingRestrictions.js** —— 训练上限

### 4.6 玩家 / 外交

- **Player.js / PlayerManager.js** —— 玩家数据
- **Diplomacy.js** —— 同盟 / 中立 / 敌对
- **EndGameManager.js** —— 胜负判定
- **Population.js** —— 人口上限
- **EntityLimits.js** —— 建筑上限 (奇观等)
- **Promotion.js** —— 单位升级
- **Upkeep.js** —— 维护费

### 4.7 视野 / 可见性

- **Visibility.js / Fogging.js / Mirage.js / VisionSharing.js** —— 战争迷雾 + 探索/未探索 + 残影

### 4.8 触发器 / 关卡

- **Trigger.js / TriggerPoint.js / AlertRaiser.js / CeasefireManager.js**

### 4.9 GUI 桥接

- **GuiInterface.js** —— C++ GUI ↔ JS sim 之间唯一沟通入口
- **AIInterface.js / AIProxy.js** —— 给 AI 的接口
- **RangeOverlayManager.js / RallyPoint.js** —— UI 元素

### 4.10 其他游戏机制

- **GarrisonHolder.js / Garrisonable.js** —— 驻扎
- **TurretHolder.js / Turretable.js** —— 炮塔位 (城墙带兵)
- **Pack.js** —— 攻城武器打包/展开
- **Gate.js / WallPiece.js** —— 城门 / 城墙连接
- **Settlement.js** —— 殖民地
- **Territory*.js** —— 领土系统
- **Identity.js / Sound.js** —— 身份信息 / 音效

**观察**: 游戏规则全在 JS,不在 C++。这意味着 modder 改 JS 就能改游戏机制,而不用重编引擎。 这是 0 A.D. 选择 C++/JS 双层的根本动机。

---

## 5. 模板系统 (XML)

`binaries/data/mods/public/simulation/templates/` —— 每个 entity 类型一个 XML 文件,描述它有哪些 component + 各 component 的初始参数。

```xml
<Entity>
  <Identity>...</Identity>
  <Position>...</Position>
  <Health>... <Max>100</Max> ...</Health>
  <UnitMotion>... <WalkSpeed>9</WalkSpeed> ...</UnitMotion>
  <UnitAI><DefaultStance>aggressive</DefaultStance>...</UnitAI>
  <Attack><Melee><Damage>...</Damage></Melee></Attack>
  ...
</Entity>
```

支持**模板继承**: 子模板 `units/spartan/spear` 可以从父模板 `template_unit_infantry_melee_spear` 继承,只覆盖差异。我们的 `*Config.gd` 没有继承,只能字段拷贝。

---

## 6. 网络 / Replay

- **lockstep model**: 客户端只交换 `SimulationCommand` (玩家命令),不同步 entity 状态
- **TurnManager** 三个变种: Local (单机) / Network (多人) / Replay (回放)
- **OOS detection**: 每 N turn 算一遍全 entity hash,不一致就 dump 双方状态
- **Serialization**: 全 entity 整局可序列化 (`Serialize/Deserialize` 是每个 component 必须实现的)

---

## 7. AI (电脑玩家)

`binaries/data/mods/public/simulation/ai/` —— 完全跑在 JS 沙箱里 (`CCmpAIManager` 给沙箱)
- 每个 AI bot 一个独立 JS context
- AI 只能通过 `IProxy` 看到 sim 状态(只读 + delta),不能直接操作 entity
- 给 AI 设计这种沙箱是为了防作弊 + 让 AI 跟人类玩家走同一套命令通道

---

## 8. 引擎其他主要模块

| 模块 | 职责 |
|---|---|
| **graphics/** | 场景图 / 模型加载 (collada) / 动画 / 粒子 / 天空盒 / 地形 mesh |
| **renderer/** | OpenGL/Vulkan 渲染管线 / shadow / water / postFX |
| **gui/** | XML 定义 + JS 逻辑的 GUI 系统 (类似早期 web) |
| **network/** | TCP lockstep + ENet UDP / lobby 接入 |
| **scriptinterface/** | SpiderMonkey embedding + C++↔JS marshalling |
| **lobby/** | XMPP 多人大厅 |
| **i18n/** | gettext 国际化 |
| **maths/** | Vector2/3/4, Matrix3/4, **Fixed**, Quaternion |
| **lib/** | 跨平台 OS 抽象 (file / thread / socket) |
| **soundmanager/** | OpenAL 音频 |
| **rlinterface/** | Reinforcement Learning 接口 (供 AI 研究用) |

---

## 9. 给 inkmon RTS 的"映射"

如果照搬 0 A.D.,我们现有架构每一层对应到哪:

| 0 A.D. 层 | 现有 inkmon 实现 | 差距 |
|---|---|---|
| ECS (Entity-Component-Manager) | LGF 的 Actor / AbilitySet / AttributeSet | 我们更面向对象,他们更纯 ECS |
| Message-driven update | LGF EventProcessor + RtsActivity | 概念相似,他们分阶段更细 |
| Lockstep + Replay | 已有 (PlayerCommandStore + replay smoke) | **概念已对齐** ✓ |
| Fixed-point | 浮点 | 跨平台风险,但 Godot WASM 实测已 deterministic |
| C++ 引擎 + JS 游戏 | GDScript 单层 | 性能敏感时单层会撞墙 |
| Pathfinder 三层 | 单层 grid + A* + steering | **最大差距** |
| Obstruction (动态 + 静态分开管理) | 全栈进 RtsBattleGrid bool | 中等差距 |
| Footprint (视觉) ≠ Obstruction (碰撞) | 混在一起 | 中等差距 (Bug 1 根因) |
| UnitAI FSM | RtsActivity (类 FSM,但更轻) | 中等差距 (无 stance) |
| Formation controller | 无 (个体 destination_offset) | **大差距** |
| ResourceGatherer + Dropsite | RtsResourceNode + worker activity | 小差距,可参考结构升级 |
| Vision + LOS + Fogging | 无 | 我们暂时不需要 |
| Templates (XML 继承) | *Config.gd (无继承) | 小差距 (将来 mod 才需要) |

---

## 10. 工程量参考

0 A.D. 体量:

- **C++**: ~450 个文件,~30 万行 (引擎 + simulation2 C++ 组件 + 寻路)
- **JS**: ~80 个 sim components + ~30 个 GUI scripts,~20 万行
- **XML 模板**: ~3000 个单位/建筑/资源
- **2001 启动,2009 alpha 1,至今 23 年开发**,30+ 全职等价开发者贡献

我们想"完整照搬"的实际范围:
- C++ 引擎 → 跳过 (我们用 Godot,渲染 / GUI / 资源 / 平台抽象 / 音频全有)
- simulation2 system (ECS 框架) → 我们 LGF 已有近似物
- simulation2 components C++ + helpers → **真正要参考的核心**,~80 个文件,~5 万行
- mods/public 的 sim components JS → **游戏规则参考**,~80 个文件,~10 万行 (但其中很多机制我们不需要,如 territory / market / promotion)
- 模板 + 资源 → 我们用自己的

**保守估计**: 仅"完整照搬寻路 + 编队 + UnitAI + 经济采集"四大块到我们 GDScript 实现 = 1-3 万行新 + 现有 1.5 万行重写。

---

## 11. 给后续决策的关键观察

1. **0 A.D. 的力量来自分层,不是来自任何单一算法**。寻路三层不是因为算法多么神,而是因为它把"全图找路"和"绕开动态单位"分离;编队不散是因为分阶段消息保证 controller 先动;复杂游戏机制可加是因为 ECS + 80 个独立 component 互不耦合。
2. **性能敏感 = C++,游戏规则 = JS** —— 这个分层对我们价值有限,因为 GDScript 单层就够。但"data 配置 + 行为脚本分离"这个思路 (XML 模板 + JS component) 对我们仍有借鉴。
3. **lockstep + fixed-point + replay** 我们已经有 (除了 fixed-point),不用学这一层。
4. **真正值得照搬的是 6 件事**:
   - Pathfinder 三层 (long-range + hierarchical + short-range vertex)
   - Obstruction 双表示 (高精度 shape + grid rasterize)
   - Footprint vs Obstruction 分离
   - UnitAI 完整 FSM + Stance
   - Formation controller (虚拟 entity 管 slot)
   - 分阶段 update 消息 (formation 先于 unit)
5. **可以不照搬的**: ECS 大改 (LGF 已经够用)、C++/JS 双层 (Godot 单层够)、视野/迷雾、领土、贸易、科技树 —— 除非游戏需要。

---

## 12. 参考链接

- 引擎主仓 (archived): https://github.com/0ad/0ad
- 新主仓: https://gitea.wildfiregames.com/0ad/0ad
- Wiki: https://trac.wildfiregames.com/wiki/EngineOverview (常被防爬挡,可以走 archive.org)
- 配套文档:
  - [0ad-pathfinding.md](./0ad-pathfinding.md) — 寻路子系统深度解析
  - [0ad-vs-inkmon-rts.md](./0ad-vs-inkmon-rts.md) — 寻路差距对比
