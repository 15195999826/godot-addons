# 世界即唯一 Instance：从"战斗 owns 世界"到"世界 owns 战斗"

**日期**：2026-04-19
**范围**：`core/entity/*`、`example/hex-atb-battle-core/*`、`example/hex-atb-battle-frontend/*`、`stdlib/replay/*`；主仓库的 `scripts/SkillPreviewBattle.gd`、`scenes/`、`tests/`
**类型**：架构级设计文档（前瞻性，尚未实现）

---

## 背景

`skill_preview` 工具开发过程中观察到一个表层现象：点 START 模拟后，3D 场景发生可见的"重建"——格子重渲染、unit view 重 spawn、相机重算。表层修复方向有两条：

1. **字段对齐**：把编辑态和播放态两条路径的 `map_config` / `initial_actors` 打成字节一致，重建过程视觉上无感。
2. **`load_replay` 加 diff**：新旧 record 相同字段就跳过重建。

两条都是"让 destructive 的过程看起来不 destructive"。但深层追问——**为什么 frontend 会有 destructive load？** ——暴露出整个框架的分层假设是错的。

真正的问题不是"重建的视觉跳变"，是 **"战斗"这个概念错误地承担了"世界"的职责**。现代战斗设计（新派 JRPG：遇敌直接在当前地图上展开、不切场景）需要的是"世界永续 + 战斗是过程"，而现在框架实现的是"世界 = 战斗实例的 side-effect"。

本文档确定新的架构心智模型，并列出迁移路径。**不含代码落地**——落地分阶段分 PR 推进。

---

## 现状分析

### 分层错位

```
GameplayInstance (abstract)
  └─ HexBattle (具体实现)
        ├─ UGridMap.configure(…)         ← 战斗 start 时配置地图
        ├─ left_team / right_team         ← 战斗 start 时创建 actor
        ├─ BattleRecorder                  ← 战斗 start 时带上 initial_actors snapshot
        └─ ATB loop / tick(…)              ← 战斗算法

FrontendBattleReplayScene.load_replay(record)
  ├─ 销毁旧 grid
  ├─ 按 record.map_config 新建 grid
  ├─ 按 record.initial_actors 新建 unit view
  └─ 喂 timeline events 给 BattleDirector 驱动飘字/特效
```

**根因**：`GameplayInstance` 这个抽象在框架里没有第二个实现，整个框架的"世界"概念事实上就是"某一场 HexBattle 的运行时容器"。于是：

- `UGridMap` 是战斗的 side effect（战斗一结束世界就"没地图了"）
- Actor 在 `HexBattle.start` 里被 spawn、在 `HexBattle.end` 附近生命周期结束
- Frontend 被动消费 `BattleRecord`，即 **view = 战斗输出的函数**，而不是 **view = 世界状态的投影**

### 后果链

| 症状 | 追到根 |
|---|---|
| frontend 战斗开始/结束场景跳变 | `load_replay` 必须 destructive，因为它假设自己是整个视觉世界的 owner |
| 编辑态和播放态 map_config 字段编码漂（flat vs pointy、hex_size vs size） | 两条路径都要"合成"一个合法的 BattleRecord.map_config，各走各的 |
| `BattleRecord.initial_actors` 是 replay 的必带字段 | 回放需要自己 spawn actor，因为没有一个"世界"来承载 |
| 无法支持"主世界地图上无缝展开战斗" | 战斗实例启停会清洗世界状态；不存在"战斗结束后角色留在原地"的概念 |
| actor id 混战斗 id 前缀（`battle_0:Character_3`） | 战斗是 actor 的 owner，id 以战斗为 scope |

---

## 心智模型切换

**从"战斗 owns 世界"切换为"世界 owns 战斗"**。

```
WorldGameplayInstance (持久, 唯一 instance)
  ├─ 持有 actor / grid / systems
  ├─ 对外暴露 signal：状态变化的权威广播源
  ├─ tick(dt) 推进世界 (或独占推战斗)
  └─ start_battle(participants) 开启战斗; 战斗由 tick 推进;
     结束时 battle_finished signal 广播 event_timeline

BattleProcedure (短命, 普通 RefCounted, 非 Instance)
  ├─ 借用 world 里的 actor（不 spawn）
  ├─ tick 期间修改 actor 属性 = 直接修改 world 的 actor
  ├─ 收集 event timeline
  └─ 结束即销毁；仅被 WorldGI 临时持有 (_active_battle), 战斗结束即释放

Frontend (reactive projection)
  ├─ 订阅 WorldGI signal，自动维护 unit view / grid view
  ├─ view 生命周期跟随 world actor 生命周期，永不重建
  └─ 战斗动画层消费 BattleProcedure 产出的 event timeline，
      在现有 view 上叠加飘字 / 特效，但不拥有 view
```

### 三条哲学底线

1. **视图是状态的 reactive projection**。逻辑端把状态变化作为 signal 暴露，视图端订阅即可自动同步。**不应存在 destructive 的 view 重建 API(如 `load_replay`)**；`bind_world` 这种一次性初始化 API 不算。
2. **战斗是过程不是实例**。HexBattle 的核心行为（start-tick-end）本质是过程，之前被错误归类为 Instance 是因为它附带承担了 actor 归属权、grid 配置、tick driver、ATB loop、recorder 等**不属于"一次战斗"的职责**。把这些职责还给世界，HexBattle 的过程本体就应被拆成 `BattleProcedure`（仅被 WorldGI 临时持有，战斗结束即释放）。
3. **Replay 不是世界的平行宇宙**。回放时实例化一个"回放用 WorldGI"，frontend 对它的订阅方式和对正式 WorldGI 完全一致，代码路径只有一条。

---

## 目标架构（API 草图）

### Core 层

`WorldGameplayInstance` 是**完整游戏流程的载体** —— 从游戏开局到结束就一个 WorldGI session，期间发生任意多场战斗 / 世界演化。它拥有：

- **Entity registry**（actor / grid / systems）
- **Tick**（世界时间推进器；无战斗时推 AI / 回血 / 昼夜等 system，有战斗时独占本帧推战斗）
- **战斗调度**（`start_battle` 开启，tick 里分帧推进，`battle_finished` signal 广播 timeline）
- **Signal 广播**（frontend 做非战斗期的 view lifecycle 同步）

```gdscript
class_name WorldGameplayInstance
extends GameplayInstance

# 每 world tick 推多少 battle tick。默认 INT_MAX:战斗一帧跑完(退化到 blocking
# 语义)。未来实测卡顿再调小,让战斗横跨多个 world tick。
const BATTLE_TICKS_PER_WORLD_FRAME: int = 9223372036854775807

# ========== Entity Registry ==========
var _actors: Dictionary = {}          # id -> Actor
var _systems: Array[System] = []
var grid: GridMapModel

# ========== Signal (frontend 做 view lifecycle 用) ==========
# 仅用于"非战斗期间"的视觉同步(actor 进/出世界、NPC 移动、buff 过期等)。
# 战斗期间 frontend 不消费这些 signal —— 战斗期间 unit view 停在战斗开始时的
# 视觉状态,由 BattleAnimator 消费 event_timeline 回放动画,播完自然追上终态。
signal actor_added(actor_id: String)
signal actor_removed(actor_id: String)
signal actor_position_changed(actor_id: String, old_coord: HexCoord, new_coord: HexCoord)
signal grid_configured(config: GridMapConfig)
signal grid_cell_changed(coord: HexCoord, change_type: String)   # 地形破坏技能用
signal battle_finished(timeline: Dictionary)                      # 战斗结束广播 event_timeline

# ========== 显式 mutation API ==========
func add_actor(actor: Actor) -> void:
    _actors[actor.get_id()] = actor
    actor_added.emit(actor.get_id())

func remove_actor(actor_id: String) -> void:
    if _actors.has(actor_id):
        _actors.erase(actor_id)
        actor_removed.emit(actor_id)

func configure_grid(config: GridMapConfig) -> void:
    grid = GridMapModel.new(config)
    grid_configured.emit(config)

# ========== 战斗触发 ==========
# 只有"开启战斗"入口,没有"同步跑完"入口 —— 战斗的推进统一走 world tick,
# 通过 BATTLE_TICKS_PER_WORLD_FRAME 控制单帧吞吐。调方订阅 battle_finished
# signal 拿 event_timeline。
var _active_battle: BattleProcedure = null

func start_battle(
    participants: Array[Actor],
    ability_configs: Array[AbilityConfig],
) -> BattleProcedure:
    assert(_active_battle == null, "MVP: 同时只允许一场战斗")
    _active_battle = BattleProcedure.new(self, participants, ability_configs)
    _active_battle.start()
    return _active_battle

# ========== 世界 tick ==========
# 战斗优先:有未完成战斗则本帧独占给战斗(不跑世界 system)。
# 分帧节奏由 BATTLE_TICKS_PER_WORLD_FRAME 控制;默认 INT_MAX = 一帧跑完。
func tick(dt: float) -> void:
    if _active_battle != null:
        for _i in BATTLE_TICKS_PER_WORLD_FRAME:
            _active_battle.tick_once()
            if _active_battle.should_end():
                break
        if _active_battle.should_end():
            var timeline := _active_battle.finish()
            _active_battle = null
            battle_finished.emit(timeline)
        return   # 战斗独占本 tick, 不跑世界 system
    for sys in _systems:
        sys.tick(dt)
```

**不在 base class 上的东西**:
- ~~`reset()`~~ —— `reset` 是测试场景的需求(skill_preview / smoke_frontend_main 连续跑多场战斗),不是框架 API。由测试场景各自的子类提供(见下)。

### 测试场景的子类

```gdscript
# 主仓库 scripts/skill_preview_world.gd
class_name SkillPreviewWorldGI
extends HexWorldGameplayInstance

func reset() -> void:
    for aid in _actors.keys():
        actor_removed.emit(aid)
    _actors.clear()
    _systems.clear()
    grid = null
```

`FrontendMainWorldGI` 同理。base `WorldGameplayInstance` 和游戏用的 `HexWorldGameplayInstance` 都保持干净,不污染框架 API。

### BattleProcedure

**分层**：
- `BattleProcedure`（**core 层抽象基类**，`core/entity/battle_procedure.gd`）：提供 `start / tick_once / finish / should_end` 骨架 + recorder 管理 + in_combat tag 管理，不含具体战斗规则
- `HexBattleProcedure`（**example/hex-atb-battle-core 特化**）：继承 BattleProcedure，加 ATB loop、队伍推进逻辑、projectile 广播等 hex 战斗特有行为

下面草图是 core 抽象基类。BattleProcedure 的方法**都是 public**（被 WorldGI.tick 调用，是 package 级 API，不加下划线）。

```gdscript
class_name BattleProcedure
extends RefCounted

var _world: WeakRef                          # WorldGI
var _participant_ids: Array[String]
var _ability_configs: Array[AbilityConfig]
var _recorder: BattleRecorder                # 短命, 随 procedure 销毁
var _current_tick: int = 0
var _finished: bool = false

func start() -> void:
    # 给参战者打 in_combat tag, world tick 的其它 system (regen/AI) 跳过他们
    for pid in _participant_ids:
        _get_actor(pid).tags.add("in_combat")
    _recorder = BattleRecorder.new({"tickInterval": TICK_INTERVAL})
    _recorder.start_recording_events_only()   # 不带 initial_actors snapshot

func tick_once() -> void:
    _current_tick += 1
    for actor_id in _participant_ids:
        var actor := _get_actor(actor_id)
        actor.ability_set.tick(TICK_INTERVAL, _current_tick * TICK_INTERVAL)
        actor.ability_set.tick_executions(TICK_INTERVAL, _world.get_ref())
    var events := GameWorld.event_collector.flush()
    _recorder.record_frame(_current_tick, events)

func should_end() -> bool:
    # 基类提供默认 (如无 active execution 且无 projectile); 子类可 override
    return _finished

func finish() -> Dictionary:
    for pid in _participant_ids:
        var a := _get_actor(pid)
        if a != null:
            a.tags.remove("in_combat")
    _finished = true
    return _recorder.stop_recording("battle_complete")
```

**重点**：
- 属性变化在 `actor.ability_set.tick` 里直接改 `actor.attribute_set.hp` 等 → 因为 actor 是 world 持有的，**等于直接写 world**。战斗结束后 WorldGI 里 actor 已是终态。
- `start` / `tick_once` / `finish` 阶段都不 `add_actor` / `remove_actor`，actor 生命周期完全归 world 管。
- 死亡处理：战斗里 hp → 0 时，**发 death event 到 event_collector，但不 `world.remove_actor(id)`**。上层（游戏规则层）决定"死了是消失还是留尸体"。
- 没有自带 `execute()` loop —— 推进由 WorldGI.tick 驱动。调方拿到 `battle_finished` signal 里的 timeline 后 procedure 即可 GC。

### Frontend 层

```gdscript
class_name WorldView
extends Node3D

var _world_ref: WeakRef
var _unit_views: Dictionary = {}      # actor_id -> UnitView3D
var _battle_animator: BattleAnimator

func bind_world(world: WorldGameplayInstance) -> void:
    _world_ref = weakref(world)
    # 初始 hydrate: 当前 actor 全部 spawn view
    for aid in world.get_all_actor_ids():
        _on_actor_added(aid)
    # 订阅 view lifecycle 相关 signal (不订阅战斗期变化)
    world.actor_added.connect(_on_actor_added)
    world.actor_removed.connect(_on_actor_removed)
    world.actor_position_changed.connect(_on_pos_changed)
    world.grid_configured.connect(_on_grid_configured)
    world.grid_cell_changed.connect(_on_grid_cell_changed)

func _on_actor_added(actor_id: String) -> void:
    # 按 actor 的 config / team 构造 UnitView3D, 挂上
    var view := _build_unit_view(actor_id)
    _unit_views[actor_id] = view
    add_child(view)
    # view 从 actor 当前属性 hydrate 一次 (pull 模式, 不靠 signal)
    view.hydrate_from_actor(_world_ref.get_ref().get_actor(actor_id))

func _on_actor_removed(actor_id: String) -> void:
    if _unit_views.has(actor_id):
        _unit_views[actor_id].queue_free()
        _unit_views.erase(actor_id)

func play_battle_animation(event_timeline: Dictionary) -> void:
    # 战斗结束后 WorldGI actor 已是终态, 但 unit view 仍停在战斗开始时的视觉状态。
    # animator 消费 event_timeline 驱动飘字/特效/死亡动画, 播完视觉自然追上终态。
    # 期间 view 不重建, 也不靠 signal 实时同步 —— 纯粹由 timeline 驱动。
    _battle_animator.play(event_timeline, _unit_views)
```

**关键**：`WorldView` 没有 `load_replay` 这种 API。它只有 `bind_world` + signal 订阅。战斗动画是叠加层（`play_battle_animation`），不是视觉主通道。

### Replay 回放（录像）

```gdscript
class_name ReplayPlayer

static func play(record: Dictionary, parent: Node) -> void:
    # 1. 构造一个临时的回放用 world
    var world := WorldGameplayInstance.new()
    world.hydrate_from_snapshot(record.world_snapshot)  # 触发 actor_added signal
    # 2. WorldView 像绑正式 world 一样绑它
    var view := WorldView.new()
    parent.add_child(view)
    view.bind_world(world)
    # 3. 把 event timeline 按时间轴喂给 animator 驱动动画
    view.play_battle_animation(record.event_timeline)
    # 4. 播完 view 和 world 一起 free
```

**Record 格式升级**：
```
{
    "version": "3.0",
    "meta": {...},
    "world_snapshot": {             # 仅录像回放需要,实时战斗不用
        "grid_config": {...},
        "actors": [{id, type, config, position, attributes, tags, abilities}, ...],
    },
    "event_timeline": [             # 战斗期间的事件流
        {frame: 1, events: [...]},
        ...
    ]
}
```

实时战斗产出的 record 可以只带 `event_timeline`（`world_snapshot` 字段 null），因为实时场景的 WorldGI 已经在。

---

## 与现有代码的对照表

| 现有 | 目标 |
|---|---|
| `HexBattle extends GameplayInstance` | `HexWorldGameplayInstance extends WorldGameplayInstance` |
| `HexBattle.start(config)` 做 grid + actor + recorder | WorldGI 显式 `configure_grid` + `add_actor`（持久）；`HexBattleProcedure` 做 recorder + tick（短命） |
| `HexBattle.left_team / right_team` | `BattleProcedure._participant_ids`（仅 procedure 生命周期内有意义） |
| `BattleRecord.initial_actors` 必带 | 录像模式在 `world_snapshot.actors`；实时模式不带 |
| `FrontendBattleReplayScene.load_replay(record)` | 两条路径：实时 `WorldView.bind_world(world)`；录像 `ReplayPlayer.play(record, parent)` |
| `GameWorld.create_instance(HexBattle)` 每场战斗 | `GameWorld.create_instance(HexWorldGI)` 一个"世界 session"一次（整局游戏一个）；战斗走 `world.start_battle(participants, abilities)` + 监听 `battle_finished(timeline)` signal（推进由 world tick 驱动，分帧常数 `BATTLE_TICKS_PER_WORLD_FRAME` 默认 INT_MAX 退化成一帧跑完） |
| Actor id 形如 `battle_0:Character_3` | Actor id 形如 `world_0:Character_3`（prefix 由 instance 类型决定，自然替换） |

**注**：`GameWorld` autoload 职责不变 —— 它仍是 `GameplayInstance` 的 manager（`create_instance` / `destroy` / 跨 instance 的 `event_collector` / `event_processor`）。`WorldGameplayInstance` 是它管理的一种 instance 类型，和原来的 `HexBattle` 处于同一抽象层。类比 UE：`GameWorld` ≈ `UEngine`，`WorldGameplayInstance` ≈ `GameMode`，允许多个并存。

---

## 迁移阶段

**阶段 0**（本文档）：设计对齐。

**阶段 1 — Core 分层**
- 新增 `WorldGameplayInstance extends GameplayInstance`：signal + mutation API + tick + start_battle 全部在这个类上；base `GameplayInstance` 不动
- 新增 core 层 `BattleProcedure`：抽象骨架（`start / tick_once / finish / should_end` + recorder + in_combat tag 管理）
- 新增 `HexBattleProcedure extends BattleProcedure`：把 `HexBattle.start` 里 ATB / teams 推进 / projectile 广播等 hex 特化逻辑挪进去
- `HexBattle` 改名 `HexWorldGameplayInstance`，职责收缩到 actor registry + grid + system 管理
- **Signal 只由显式 mutation API 触发**（`add_actor` / `remove_actor` / `configure_grid` 等）。战斗里直接改 `actor.attribute_set.hp` / `actor.hex_position` 不走 API，自然不触发 signal，所以不需要在 `AttributeSet` / `TagContainer` 里注入 emit。战斗期变化由 event_timeline 承载，不走 signal 路径。

**阶段 2 — Frontend 订阅器**
- 新增 `WorldView`（订阅 WorldGI signal 维护 unit view / grid）
- `FrontendBattleReplayScene` 保留但标记为"录像回放专用"路径
- 新增 `BattleAnimator`（消费 event timeline 在现有 view 上叠加飘字/特效）

**阶段 3 — skill_preview 工具切换**
- `skill_preview` 编辑态直接用一个常驻 `SkillPreviewWorldGI`（继承 `HexWorldGameplayInstance`，加 `reset()`）
- 右键编辑 actor = 直接 `world.add_actor` / `remove_actor`（触发 signal → WorldView 自动刷新）
- START = `world.start_battle(participants, abilities)` → 监听 `battle_finished(timeline)` → 喂 `BattleAnimator`
- 验证"无缝展开战斗"可行

**阶段 4 — Replay 格式 + 录像路径**
- `BattleRecord` v3 格式（split `world_snapshot` + `event_timeline`）
- `ReplayPlayer`（临时 WorldGI + WorldView）
- 现有录像数据做一次性迁移脚本或版本检测 fallback

**阶段 5 — 正式游戏场景**
- `main.tscn` 切换到 WorldGI 承载；战斗走 `start_battle` + 监听 `battle_finished`
- `scenes/Simulation.tscn` / Web 桥接器适配
- scenario runner / smoke test 适配（大多数断言应该变简单：直接查 WorldGI actor 终态）

每个阶段结束都应能独立跑通 `smoke_frontend_main` + scenario runner，保证增量推进。

---

## 风险与未决问题

### R1. 参战者"锁定"语义

战斗中 actor 的 hp / position 变化不应触发"世界级 system"（AI / 回血 / 掉落等，未来可能加）。

**对策**：`in_combat` tag。任何未来的 world-level system 在 tick 里判这个 tag 跳过。BattleProcedure `_start` 时打、`_finish` 时清。

> **注**：signal 风暴不是问题 —— 战斗是 blocking 的一次性推算，frontend 期间不做同步渲染，unit view 停在战斗开始时的视觉状态，由 `BattleAnimator` 消费 event_timeline 回放动画，播完自然追上 WorldGI 终态。signal 只服务非战斗期间的 view lifecycle（actor 进/出、NPC 移动、buff 过期）。

### R2. Replay 独立性 vs 轻量性

- 纯 `event_timeline`：轻，但脱离 WorldGI 没法独立播放。
- 完整 `world_snapshot`：重，整个 world 序列化对大地图不现实。

**对策**：`world_snapshot` 只存"参战者 + 战斗范围内的 grid cell"（比如施法者周围 N 格），不是整个世界。录像回放时 hydrate 出的是一个局部 WorldGI，够 animator 跑完就行。

### R3. 多战斗并行

同屏多个战斗同时发生（散兵 + boss 战叠加）—— 架构允许多个 `BattleProcedure` 并存（WorldGI passive 不感知），但 signal / animation overlap / in_combat tag 对多战斗的语义要上层 orchestrator 决定。

**对策**：MVP 明确单战斗，多战斗并行做到 V2 再说。

### R4. 地形破坏的粒度

未来影响地形的技能。Grid cell 变化的 signal 粒度：
- 每 cell 一个 `grid_cell_changed(coord, change_type)` → 细，但频繁地震类技能 signal 多
- 整个 grid 版本号 + frontend 轮询 → 粗，实现简单但响应慢

**建议**：每 cell signal + frontend 内部 batching（一 tick 汇总）。

### R5. Save / Load

WorldGI 状态的序列化格式应该和 replay `world_snapshot` 复用同一套 hydrate 逻辑（存档就是一次 WorldGI snapshot，加载就是 `hydrate_from_snapshot`）。阶段 4 一并设计，不要分两套。

---

## 方法论沉淀

1. **视图 = 状态的 reactive projection**。只要逻辑端把状态变化作为 signal 暴露，视图端订阅即可自动同步，不需要任何"加载 / 卸载"显式 API。这是 ECS / React / observer 模式的共通底层哲学。

2. **过程类 vs 实例类的判别标准**：
   - Instance = 有状态、有生命周期、被外界引用
   - Procedure = 无状态（或仅局部状态）、输入 → 输出 → 丢弃、中间无人引用
   - 判错会导致职责错位。HexBattle 被错误归类为 Instance 只是因为它附带承担了 actor 归属权这个 side channel；把 actor 归属权还给世界，HexBattle 就回归 procedure 本职。

3. **表层症状追到架构根**：`skill_preview` 场景跳变 → `load_replay` destructive → "为什么 destructive？" → "因为 frontend 被假设为 record 的 owner" → "为什么 frontend 是 record 的 owner？" → "因为框架里没有'世界'的概念" → 真正要改的是世界抽象本身。遇到表层问题先问三次"为什么"，不要停在表层。

---

## 阶段 1 实装差异（2026-04-20 落地）

上面的 API 草图是"规范的理想形态"；阶段 1 实装时为兼容现状做了如下适配。后续阶段按需回归或继续适配。

| 草图 | 实装 | 原因 |
|---|---|---|
| `add_actor(actor) -> void` / `remove_actor -> void` | `-> Actor` / `-> bool` | 沿用 `GameplayInstance` 父类的返回值约定,避免调用端改动 |
| `configure_grid: grid = GridMapModel.new(config)` | `GridMapModel.new(); grid.initialize(config)` | `GridMapModel.new` 实际不接受参数 |
| `start_battle(participants, ability_configs: Array[AbilityConfig])` | `start_battle(participants)` | `ability_configs` 阶段 1 未使用;用到时再加入(避免死参数) |
| `BattleProcedure._ability_configs` 字段 | 无 | 同上 |
| `BattleProcedure.start: _get_actor(pid).tags.add("in_combat")` | 虚钩子 `_mark_in_combat(id, active)`;HexBattleProcedure 覆盖里走 `actor.ability_set.add_loose_tag` | 基类 `Actor` 无 `.tags` 字段,tag 挂在 `AbilitySet.tag_container` 上 |
| `BattleProcedure.tick_once` 基类做 ability_set.tick | 基类只 `_current_tick += 1` + 录像 flush;子类 HexBattleProcedure override 做完整 ATB loop | 同上(ability_set 不在基类 Actor 上) |
| `BattleProcedure.finish() -> Dictionary` 无参 | `finish(result: String = "battle_complete")` | 需向 recorder 传战斗结果标签(`left_win` / `right_win` / `timeout`) |
| `HexBattle` 改名为 `HexWorldGameplayInstance` 职责收缩 | `HexBattle` 保留为 thin 兼容门面,`extends HexWorldGameplayInstance` | 阶段 1 不改调用端(`main.tscn` / `SkillPreviewBattle` / `SimulationManager` / scenario runner 仍用 `HexBattle`);阶段 5 去门面 |
| Actor id 形如 `world_0:Character_3` | 经 HexBattle 门面仍为 `battle_0:Character_3`,经直接 `HexWorldGameplayInstance` 则为 `world_0:xxx` | 门面 `_init` 用 "battle" prefix 维持向后兼容;阶段 5 去门面时自然替换 |
| `BattleRecorder.start_recording_events_only()` 为唯一路径 | 基类 `BattleProcedure._start_recorder` 虚钩子默认走 events-only,HexBattleProcedure override 走旧版 `start_recording(actors, configs, map_config)` | 阶段 1 保留 `initial_actors` / `map_config`,FrontendBattleReplayScene 不受影响;录像格式 v3 在阶段 4 落地 |

**已落地**:`WorldView` / `BattleAnimator`(阶段 2,2026-04-20,见 [2026-04-20-world-view.md](2026-04-20-world-view.md))。

**未实装(按阶段推进)**:`SkillPreviewWorldGI.reset()`(阶段 3)、`ReplayPlayer` + 录像 v3(阶段 4)、`main.tscn` / `Simulation.tscn` 切换到 WorldGI 承载(阶段 5)。

---

## 下一步

本文档对齐后的推进顺序：

1. ~~阶段 1 起稿：新增 `WorldGameplayInstance`（含 signal + tick + start_battle + mutation API）+ core `BattleProcedure` 抽象基类 + `HexBattleProcedure` + `HexBattle` 改名收缩~~ **已落地(2026-04-20),见上面"阶段 1 实装差异"**。
2. ~~阶段 2 起稿：`WorldView`（订阅 WorldGI signal）+ `BattleAnimator`（消费 event_timeline）~~ **已落地(2026-04-20),见 [2026-04-20-world-view.md](2026-04-20-world-view.md)**。
3. 阶段 3：`skill_preview` 端到端 POC 验证"无缝战斗"
4. 视 POC 结果决定阶段 4/5 的优先级

每个阶段独立一个 `docs/design-notes/YYYY-MM-DD-<topic>.md`，详细记录 probe / 决策 / 验证数字。
