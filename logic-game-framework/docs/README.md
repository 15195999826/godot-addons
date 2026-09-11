# Logic Game Framework 文档

本框架是一个用于构建回合制/ATB 战斗系统的 GDScript 框架，从 TypeScript 版本迁移而来。

## 快速开始

### 核心概念

- **Action**: 技能效果的最小执行单元（伤害、治疗、移动等）
- **Ability**: 技能配置，包含触发条件、消耗、Timeline 和 Actions
- **Timeline**: 定义技能执行的时间轴和关键帧（tags）
- **TargetSelector**: 目标选择器，决定 Action 作用于哪些目标
- **ExecutionContext**: 执行上下文，包含当前事件链、Ability 引用、所属 GameplayInstance（`instance`）等

### 基本用法

```gdscript
# 创建一个伤害 Action
var damage_action = HexBattleDamageAction.new(
    TargetSelector.current_target(),  # 目标选择器
    50.0,                              # 伤害值
    DamageType.PHYSICAL                # 伤害类型
)

# 带回调的伤害 Action（暴击时额外伤害）
var damage_with_callback = HexBattleDamageAction.new(
    TargetSelector.current_target(),
    50.0,
    DamageType.PHYSICAL
).on_critical(
    HexBattleDamageAction.new(
        TargetSelector.current_target(),
        10.0,
        DamageType.PHYSICAL
    )
)
```

## 文档索引

### 核心参考

| 文档 | 描述 |
|------|------|
| [Action 系统](./reference/action-system.md) | Action 基类、构造函数规范、回调系统 |
| [Action 架构契约](./reference/action-architecture.md) | 四层分层合同（Util / Primitive / Flow / SkillLocal）+ 各机制设计边界 + validator 门禁 |
| [TargetSelector](./reference/target-selector.md) | 目标选择器的使用方式 |

### 实践指南

| 文档 | 描述 |
|------|------|
| [逻辑层到表演层数据传递](../example/hex-atb-battle/logic/docs/logic-to-presentation-guide.md) | StageCue 事件、Timeline 配置、数据流架构 |

## 重要约定

### 1. 子类必须显式调用 `super._init()`

所有继承 `Action.BaseAction` 的子类，**必须**在 `_init()` 中显式调用 `super._init(target_selector)`：

```gdscript
# ✅ 正确
func _init(
    target_selector: TargetSelector,
    damage: float
) -> void:
    super._init(target_selector)  # 必须调用！
    _damage = damage

# ❌ 错误 - 忘记调用 super._init()
func _init(
    target_selector: TargetSelector,
    damage: float
) -> void:
    _damage = damage  # _target_selector 未初始化！
```

**原因**: GDScript 不会自动调用父类构造函数。如果不调用 `super._init()`，`_target_selector` 将为 `null`，导致运行时错误。

### 2. 使用类型化构造函数

所有 Action 使用类型化参数，而非 Dictionary：

```gdscript
# ✅ 正确 - 类型化参数
HexBattleDamageAction.new(
    TargetSelector.current_target(),
    50.0,
    DamageType.PHYSICAL
)

# ❌ 错误 - Dictionary 参数（已废弃）
HexBattleDamageAction.new({
    "targetSelector": TargetSelector.current_target(),
    "damage": 50.0,
    "damage_type": DamageType.PHYSICAL,
})
```

### 3. TargetSelector 使用工厂方法

```gdscript
# 获取当前事件的目标
TargetSelector.current_target()

# 获取 Ability 的所有者
TargetSelector.ability_owner()

# 固定目标（测试用）
TargetSelector.fixed([actor_ref1, actor_ref2])
```

### 4. GameplayInstance 上下文（`ctx.instance`）

`ExecutionContext.instance` / `AbilityLifecycleContext.instance` 是本次执行所属的 `GameplayInstance`——框架传的是**真基类**，项目层按需收窄到自己的世界类型。框架层不再有 `Variant` provider，也没有沿调用链一路递下去的尾随参数。

#### 找 instance 只有一种方式

instance 一律按 owner 的 actor id 反查（`GameWorld.get_instance_of_actor(actor_id)`，与 `Actor.get_owner_gameplay_instance()` 同一「id 自描述归属」机制），**不经调用链递、不缓存**：AbilitySet 的定向投递 / grant / `can_activate` 查询、on_remove / 叠层 / Break 钩子（`AbilityLifecycleContext.for_ability`）、pre / post handler 的重建 context（`AbilityLifecycleContext.rebuild_for_handler`）、`AbilityExecutionInstance` 每次建的 ExecutionContext（含 revoke / expire 触发的取消）、`NoInstanceComponent` 的事件与 lifecycle action 都走这一条。owner 未注册进 GameWorld（孤立单测、`create_instance` 注册之前的 grant）时为 `null`。

#### 推荐做法：必须有世界的读点经项目的 `world(ctx)` helper

项目层的 `[ProjectName]GameStateUtils` 提供 `world(ctx) -> <具体世界类型>`：`as` 收窄，类型不符（含 `null`）视为接线错误、`Log.assert_crash` 响亮报错。helper 收的是 `ExecutionContext`（Action / Resolver / Selector 里的读点）；Condition / Cost / trigger filter / PreEvent handler 拿到的是 `AbilityLifecycleContext`，同样 typed assign 后判空，必须有世界就在判空分支里 `Log.assert_crash`。helper 随项目第一处「必须有世界」的读点出现——hex 的 `HexBattleGameStateUtils.world` 如下；inkmon / dota2 现有读点都允许缺席、走下方的判空写法，暂无 helper：

```gdscript
static func world(ctx: ExecutionContext) -> HexWorldGameplayInstance:
    var battle := ctx.instance as HexWorldGameplayInstance
    if battle == null:
        Log.assert_crash(false, "HexBattleGameStateUtils",
            "ctx.instance 不是 HexWorldGameplayInstance: %s" % ctx.instance)
    return battle
```

#### 在 Action 中使用

```gdscript
# 项目层 Action
class_name MyProjectDamageAction
extends Action.BaseAction

func execute(ctx: ExecutionContext) -> ActionResult:
    # 必须有世界：经项目 helper 收窄（hex 的 world(ctx) 返回 HexWorldGameplayInstance）
    var battle := HexBattleGameStateUtils.world(ctx)
    var target_name := HexBattleGameStateUtils.get_actor_display_name(target_id, battle)

    # ... 业务逻辑

    # Post 阶段：事件设施归 instance；观众是按 trigger kind 订阅了这类事件的 ability，被击杀的目标还响应不响应由它的 is_event_responsive 决定
    battle.event_processor.process_post_event(damage_event)

# 允许在没有世界时静默降级的读点，基类隐式下转后判空：
#   var battle: HexWorldGameplayInstance = ctx.instance
#   if battle == null:
#       return ActionResult.create_success_result([], { "skipped": "no_instance" })
```

#### 为什么这样设计？

1. **类型在边界上说清楚**：框架只承诺 `GameplayInstance`，项目层一次收窄就拿到完整的类型检查与补全；`Variant` provider 下 41 个读点里 37 个拿到手就强转，类型错误只是被推迟到运行时。
2. **一种找法**：id 反查不依赖调用方把谁递进来——取消、lifecycle 这类手上没有 world 的路径同样拿得到，execution 不必为此持 WeakRef 回指。
3. **不成环**：context 只活在调用栈上、永不缓存；instance 的强边只向下（见「设计铁律」）。

### 5. 技能执行流程（Action 原子性）⚡

这是框架最核心的设计原则：**Action 内状态同步**。

#### 核心原则

```
┌─────────────────────────────────────────────────────────────────────┐
│  Action 是原子操作单元                                               │
│                                                                     │
│  push(event) + 应用状态 + process_post_event 必须连续执行            │
│                                                                     │
│  EventCollector 仅供录像/表演层消费，不参与逻辑状态同步               │
└─────────────────────────────────────────────────────────────────────┘
```

#### 分层职责

| 层级 | 职责 | 示例 |
|------|------|------|
| **AbilityComponent** | 决定「何时执行」 | 触发条件、冷却、消耗 |
| **Action** | 决定「做什么」 | 伤害计算、状态应用、Post 事件 |
| **BattleEvent** | 记录「结果」 | 供录像/表演层消费 |

#### 完整执行流程

以 `DamageAction` 为例：

```
DamageAction.execute()
│
├─ 1. Pre 阶段
│   └─ process_pre_event(pre_damage)
│       └─ 允许减伤/免疫等被动修改或取消
│       └─ if mutable.cancelled: 跳过此目标
│
├─ 2. 产生事件 + 应用状态（原子操作）
│   ├─ ctx.event_collector.push(damage_event)  ← 事件入队（录像用）
│   └─ target.modify_hp(-damage)               ← 立即扣血
│
├─ 3. 死亡检测
│   └─ if check_death():
│       ├─ push(death_event)                   ← 死亡事件入队
│       ├─ process_post_event(death_event)     ← 触发死亡相关被动
│       └─ battle.remove_actor()               ← 移除角色
│
├─ 4. 处理回调
│   └─ on_hit / on_critical / on_kill
│
└─ 5. Post 阶段
    └─ process_post_event(damage_event)        ← 触发反伤/吸血等被动
```

#### 代码示例

```gdscript
func execute(ctx: ExecutionContext) -> ActionResult:
    var battle := HexBattleGameStateUtils.world(ctx)
    var event_processor := battle.event_processor  # 事件设施归所属 instance，不在 GameWorld 上

    for target in targets:
        # ========== Pre 阶段 ==========
        var pre_event := { "kind": "pre_damage", "damage": _damage, ... }
        var mutable: MutableEvent = event_processor.process_pre_event(pre_event)

        if mutable.cancelled:
            continue  # 被减伤/免疫取消

        var final_damage: float = mutable.get_current_value("damage")

        # ========== 产生事件 + 应用状态（原子操作） ==========
        var event := BattleEvents.DamageEvent.create(target.id, final_damage, ...)
        var damage_event: Dictionary = ctx.event_collector.push(event.to_dict())

        var target_actor := battle.get_actor(target.id)
        if target_actor != null:
            target_actor.modify_hp(-final_damage)  # 立即扣血

            # ========== 死亡检测 ==========
            if target_actor.check_death():
                var death_event := BattleEvents.DeathEvent.create(target.id, source_id)
                ctx.event_collector.push(death_event.to_dict())
                event_processor.process_post_event(death_event)
                battle.remove_actor(target.id)

        # ========== Post 阶段 ==========
        event_processor.process_post_event(damage_event)

    return ActionResult.create_success_result(all_events, { "damage": _damage })
```

#### 错误模式（已废弃）

```gdscript
# ❌ 错误：状态同步在 tick() 中延迟处理
func tick(dt: float) -> void:
    # ... 执行 Action ...
    
    var frame_events := world.event_collector.flush()
    _process_frame_events(frame_events)  # 遍历事件应用状态 ← 违反原子性！

func _process_frame_events(events: Array) -> void:
    for event in events:
        if event.kind == "damage":
            target.modify_hp(-damage)  # 状态与事件分离 ← 危险！
```

**问题**：
1. push 事件与应用状态分离，破坏原子性
2. Post 阶段被动可能基于过期状态触发
3. 死亡检测时序错误

#### 正确模式（当前设计）

```gdscript
# ✅ 正确：状态同步在 Action 内立即完成
func tick(dt: float) -> void:
    # ... 执行 Action（内部已完成状态同步） ...
    
    # 收集本帧事件（仅用于录像，状态已在 Action 内同步）；collector 归所属 world instance
    var frame_events := world.event_collector.flush()
    recorder.record_frame(tick_count, frame_events)  # 仅录像
```

#### 关键要点

| 要点 | 说明 |
|------|------|
| **push 后立即 modify_hp** | 事件入队 → 立即应用状态 |
| **死亡检测在 Action 内** | 不在 tick 或外部处理 |
| **Post 事件紧随状态变更** | 确保被动基于最新状态触发 |
| **flush() 仅用于录像** | 不做任何状态处理 |

## 项目结构

```
addons/logic-game-framework/
├── core/                    # 框架核心
│   ├── actions/            # Action 基类、TargetSelector
│   ├── abilities/          # Ability 系统
│   ├── events/             # 事件系统
│   ├── playback/           # 录像（BattleRecorder / PlaybackData）
│   └── timeline/           # TimelineData（技能时间轴；builder .timeline() 声明即冻结 tags）
├── stdlib/                  # 标准库
│   ├── actions/            # 通用 Action（StageCueAction 等）
│   └── projectile/         # 投射物（ProjectileActor / ProjectileSystem / detectors）
├── example/                 # 示例项目
│   └── hex-atb-battle/     # 六边形 ATB 战斗示例
│       ├── actions/        # 游戏特定 Action
│       ├── skills/         # 技能配置
│       ├── utils/          # 项目级辅助类（如 HexBattleGameStateUtils）
│       └── docs/           # 示例文档
└── docs/                    # 框架文档
    ├── README.md           # 本文件
    └── reference/          # 详细参考文档
```

## 逻辑表演分离架构 📦

本框架推荐使用三层架构设计，将游戏逻辑与表现层完全分离，提高代码可测试性和可维护性。

### 三层架构设计 🏗️

以 `hex-atb-battle` 示例项目为例，采用以下三层结构：

```
addons/logic-game-framework/example/hex-atb-battle/
├── core/                       # 共享数据层（Core Layer）
│   └── events/                 # 强类型事件定义
│       └── battle_events.gd    # BattleEvents（DamageEvent, HealEvent 等）
│
├── logic/                      # 逻辑层（Logic Layer）
│   ├── actions/                # 游戏特定 Action（伤害、治疗、移动）
│   ├── skills/                 # 技能配置
│   ├── battle.gd               # 战斗状态管理
│   └── utils/                  # 逻辑层辅助类
│
├── frontend/                   # 表演层（Presentation Layer）
│   ├── visualizers/            # 事件可视化器（伤害数字、动画）
│   ├── battle_player.gd        # 回放播放器
│   └── scenes/                 # 3D 场景、UI
│
├── skill-preview/              # 技能预览子模式（沙盒战斗）
└── tests/                      # 该游戏专属冒烟与契约测试
```

### 设计原则 🎯

1. **单向依赖**：`frontend → battle → core`
   - 表演层依赖逻辑层和共享层
   - 逻辑层仅依赖共享层
   - 共享层无依赖（纯数据）

2. **事件驱动**：逻辑层通过事件通知表演层
   - 逻辑层产生事件（DamageEvent, HealEvent）
   - 表演层订阅事件并渲染（伤害数字、动画）

3. **可测试性**：逻辑层独立于 Godot 节点系统
   - 逻辑层使用纯 GDScript 类（RefCounted）
   - 可在无渲染环境下运行单元测试

4. **可复用性**：共享层数据结构可被多个系统使用
   - 事件定义可用于回放、网络同步、AI 训练

### 事件类设计模式 ⚡

所有事件类必须实现以下 5 个方法，确保类型安全和序列化支持：

#### 1. `_init()` - 设置事件类型标识

```gdscript
func _init() -> void:
    kind = "damage"  # 事件类型唯一标识
```

#### 2. `static func create(...)` - 类型安全的工厂方法

```gdscript
static func create(
    target_actor_id: String,
    damage: float,
    damage_type: DamageType = DamageType.PHYSICAL
) -> DamageEvent:
    var e := DamageEvent.new()
    e.target_actor_id = target_actor_id
    e.damage = damage
    e.damage_type = damage_type
    return e
```

#### 3. `func to_dict() -> Dictionary` - 序列化为 JSON

```gdscript
func to_dict() -> Dictionary:
    return {
        "kind": kind,
        "targetActorId": target_actor_id,  # camelCase for JSON
        "damage": damage,
        "damageType": BattleEvents._damage_type_to_string(damage_type),
    }
```

#### 4. `static func from_dict(d: Dictionary)` - 反序列化

```gdscript
static func from_dict(d: Dictionary) -> DamageEvent:
    var e := DamageEvent.new()
    e.target_actor_id = d.get("targetActorId", "")
    e.damage = d.get("damage", 0.0)
    e.damage_type = BattleEvents.string_to_damage_type(d.get("damageType", "physical"))
    return e
```

#### 5. `static func is_match(d: Dictionary) -> bool` - 类型守卫

```gdscript
static func is_match(d: Dictionary) -> bool:
    return d.get("kind") == "damage"
```

### 完整事件类示例 💡

```gdscript
class_name BattleEvents
extends RefCounted

enum DamageType { PHYSICAL, MAGICAL, PURE }

class Base:
    var kind: String = ""
    
    func to_dict() -> Dictionary:
        return { "kind": kind }

class DamageEvent extends Base:
    var target_actor_id: String = ""
    var damage: float = 0.0
    var damage_type: DamageType = DamageType.PHYSICAL
    var source_actor_id: String = ""
    var is_critical: bool = false
    
    func _init() -> void:
        kind = "damage"
    
    static func create(
        target_actor_id: String,
        damage: float,
        damage_type: DamageType = DamageType.PHYSICAL,
        source_actor_id: String = "",
        is_critical: bool = false
    ) -> DamageEvent:
        var e := DamageEvent.new()
        e.target_actor_id = target_actor_id
        e.damage = damage
        e.damage_type = damage_type
        e.source_actor_id = source_actor_id
        e.is_critical = is_critical
        return e
    
    func to_dict() -> Dictionary:
        var d := {
            "kind": kind,
            "targetActorId": target_actor_id,
            "damage": damage,
            "damageType": BattleEvents._damage_type_to_string(damage_type),
            "isCritical": is_critical,
        }
        if source_actor_id != "":
            d["sourceActorId"] = source_actor_id
        return d
    
    static func from_dict(d: Dictionary) -> DamageEvent:
        var e := DamageEvent.new()
        e.target_actor_id = d.get("targetActorId", "")
        e.damage = d.get("damage", 0.0)
        e.damage_type = BattleEvents.string_to_damage_type(d.get("damageType", "physical"))
        e.source_actor_id = d.get("sourceActorId", "")
        e.is_critical = d.get("isCritical", false)
        return e
    
    static func is_match(d: Dictionary) -> bool:
        return d.get("kind") == "damage"

# 枚举序列化辅助函数
static func _damage_type_to_string(damage_type: DamageType) -> String:
    match damage_type:
        DamageType.PHYSICAL: return "physical"
        DamageType.MAGICAL: return "magical"
        DamageType.PURE: return "pure"
        _: return "unknown"

static func string_to_damage_type(s: String) -> DamageType:
    match s:
        "physical": return DamageType.PHYSICAL
        "magical": return DamageType.MAGICAL
        "pure": return DamageType.PURE
        _: return DamageType.PHYSICAL
```

### 序列化约定 🔧

#### Dictionary Keys vs Class Properties

- **Dictionary keys**（JSON）：使用 **camelCase**
  - 原因：JSON 标准约定，便于与前端/网络通信
  - 示例：`"targetActorId"`, `"damageType"`, `"isCritical"`

- **Class properties**（GDScript）：使用 **snake_case**
  - 原因：GDScript 官方代码风格
  - 示例：`target_actor_id`, `damage_type`, `is_critical`

```gdscript
# ✅ 正确示例
class DamageEvent:
    var target_actor_id: String = ""  # snake_case property
    
    func to_dict() -> Dictionary:
        return {
            "targetActorId": target_actor_id,  # camelCase key
        }
```

#### 枚举序列化

枚举值序列化为 **小写字符串**，便于人类阅读和调试：

```gdscript
enum DamageType { PHYSICAL, MAGICAL, PURE }

# 序列化：DamageType.PHYSICAL → "physical"
# 反序列化："physical" → DamageType.PHYSICAL
```

### 为什么使用强类型？ 💪

相比传统的 Dictionary 事件，强类型事件类提供：

1. **编译时类型检查**
   ```gdscript
   # ❌ Dictionary：运行时才发现拼写错误
   var damage = event.get("damge", 0.0)  # 拼写错误！
   
   # ✅ 强类型：编译时报错
   var e := DamageEvent.from_dict(event)
   var damage = e.damge  # LSP 立即提示错误
   ```

2. **IDE 自动补全**
   - 输入 `e.` 后自动显示所有可用属性
   - 减少查文档次数，提高开发效率

3. **重构安全**
   - 重命名属性时，IDE 可自动更新所有引用
   - 避免遗漏导致的运行时错误

4. **文档即代码**
   - 类定义即完整的事件结构文档
   - 类型标注清晰表达数据含义

### 使用示例 🎮

#### 逻辑层：产生事件

```gdscript
# hex-atb-battle/actions/damage_action.gd
class_name HexBattleDamageAction
extends Action.BaseAction

func execute(ctx: ExecutionContext) -> ActionResult:
    var target := _resolve_target(ctx)
    var final_damage := _calculate_damage(target)
    var is_critical := _roll_critical()
    
    # 创建强类型事件
    var event := BattleEvents.DamageEvent.create(
        target.id,
        final_damage,
        _damage_type,
        ctx.source_actor_id,
        is_critical
    )
    
    # 推送到事件收集器
    ctx.event_collector.push(event.to_dict())
    
    return ActionResult.success()
```

#### 表演层：消费事件

```gdscript
# hex-atb-battle/frontend/visualizers/damage_visualizer.gd
class_name DamageVisualizer
extends BaseVisualizer

func can_handle(event: Dictionary) -> bool:
    return BattleEvents.DamageEvent.is_match(event)

func visualize(event: Dictionary, context: Dictionary) -> void:
    # 反序列化为强类型
    var e := BattleEvents.DamageEvent.from_dict(event)
    
    # 类型安全访问
    var target_node := _get_actor_node(e.target_actor_id)
    var damage_text := str(int(e.damage))
    
    if e.is_critical:
        _show_critical_damage(target_node, damage_text)
    else:
        _show_normal_damage(target_node, damage_text)
```

<a id="world-owns-battle"></a>
## World owns Battle + 响应式前端

本框架的核心心智模型是 **"世界 owns 战斗"**，而非早期实现的 "战斗 owns 世界"。这一翻转源于一个表层现象的深挖：`skill_preview` 点 START 时 3D 场景发生可见的"重建"（格子重渲染、unit view 重 spawn、相机重算）。追到根因，问题不是"视觉跳变"，而是 **"战斗"这个概念错误地承担了"世界"的职责** —— 现代 JRPG 需要的是"世界永续、战斗是过程"，而旧框架里 `UGridMap`、actor 生命周期、recorder 全都成了战斗启停的 side-effect。

### (a) 为什么 GameWorld 持有单一 GameplayInstance

新模型确立：`WorldGameplayInstance`（具体子类 `HexWorldGameplayInstance` / `HexDemoWorldGameplayInstance`）是**完整游戏流程的载体** —— 整局游戏一个 world session，期间发生任意多场战斗。它独占持有 actor registry、`grid`、systems，并通过显式 mutation API（`add_actor` / `remove_actor` / `configure_grid`）广播 signal。战斗本体被降级为短命的 `BattleProcedure`（`core` 层抽象基类）/ `HexBattleProcedure`（hex 特化）：它**借用** world 里的 actor 而非 spawn，tick 期间直接改 `actor.attribute_set.hp` 即等于写 world，结束即 GC。

判别标准：有状态、被外界引用的是 **Instance**；输入 → 输出 → 丢弃、中间无人引用的是 **Procedure**。战斗推进统一走 `WorldGameplayInstance.tick(dt)` —— 有未完成战斗时本帧独占给战斗（`BATTLE_TICKS_PER_WORLD_FRAME` 默认 INT_MAX，退化成一帧跑完），否则推世界 system。参战者打 `in_combat` tag 让未来的 world-level system（回血 / AI）跳过他们。

### (b) 响应式前端如何观察 world 而非消费 events

`FrontendWorldView` 是 state 的 **reactive projection**：`bind_world(world)` 先一次性 hydrate 当前所有 actor，再订阅 mutation signal 自动维护 unit view 与 grid。它**只订阅生命周期 / 结构变化**（`actor_added` → 建 view、`actor_removed` → `queue_free`、`grid_configured` → 重渲染），且只为 `CharacterActor` 建 view（过滤掉 projectile）。

属性变化（HP / tag）**不**走 signal —— 交给叠加层 `FrontendBattleAnimator` 消费 event_timeline 驱动飘字 / 特效 / 死亡动画。这是关键解耦：战斗期间 unit view 停在开战时的视觉状态，signal 只服务非战斗期的 view lifecycle；战斗结束后 WorldGI 里 actor 已是终态，animator 播完 timeline 视觉自然追上。`WorldView` **没有**「加载录像重建 view」这种 destructive API（历史反例：已删除的 `FrontendBattleReplayScene.load_replay`），只有 `bind_world` + 订阅。

### (c) recorder 单 buffer + playback 模型

`BattleProcedure` 持有短命的 `BattleRecorder`，随 procedure 销毁。录像的核心不变量是 **"调用栈真实顺序 = 录像顺序"**：Action 的 `event_collector.push` 与 callback 触发的 AttributeChanged / AbilityGranted 在同一调用栈穿插发生，因此 recorder **不分** `pending_events` / `frame_events` 双容器，而是统一汇入所属 world 的 `event_collector` 单一队列（`BattleRecorder` 构造时注入，Action 经 `ctx.event_collector` 推的是同一个），`record_frame(frame, events)` 每帧只接收 flush 出的一个有序数组。事件设施随 instance 生灭：两个 instance 的 collector / pre handler 互不可见；world 结束时若战斗仍在进行，`WorldGameplayInstance.end()` 先中止它（退订录像闭包、不发 `battle_finished`、不产出录像）。

播放侧钉死两层命名：**A 层 `Playback`（现役）** 只从录像 dict spawn 视觉 view、不重建逻辑层；**B 层 `Replay`（deterministic 重算，未来不一定做）** 仅保留 `BattleReplayPlayer` / `BattleReplaySession` 命名占位。

录像格式：`{meta, world_snapshot{actors, mapConfig, positionFormats}, timeline}`，无 version 字段（录像是短命数据，不做多版本共存；防呆走 `BattleRecord.from_dict` 的必需字段检查，坏文件直接 crash 不静默播空场）。`world_snapshot` 承载开战初态（回放的起点），由 **世界侧产出**——`WorldGameplayInstance.capture_world_snapshot()`，范围由 `should_record_actor()` 钩子裁定（常驻世界借此排除 overworld 实体）；recorder 只接收注入、专职事件流。web/JS 端解析器尚未同步当前格式，启用 web 发布时一并升级（2026-07-03 拍板，见 `docs/proposals/2026-07-03-playback-v3-format.md`）。

## 设计铁律

框架演进中固化下来的不可违反约束（蒸馏自历史架构决策，违反会重新引入已根治的 bug）：

- **事件响应钩子：观众由注册决定，死活由 actor 决定**：post 事件只送达订阅了它的 ability——`Ability.apply_effects` 按 component 的 trigger kind 注册、`remove_effects` 注销，`process_post_event(event_dict)` 没有观众参数；pre / post handler 按 owner 重建 context 之前都先问 `is_event_responsive(event_dict, phase)`。这个钩子是中性的，`Actor` 恒 `true`、不含任何领域语义；`BattleActor` 作为 **opt-in** 的战斗基类只提供一个默认答案（`not is_dead()`），项目层 override 说了算 —— hex 让死者仍响应自己的 death（亡语）与自己作为 target 的 damage（致死一击的荆棘）。激活请求与 grant 自投递是定向投递（`EventProcessor.DIRECT_DELIVERY_KINDS`，只经 `AbilitySet.receive_event`），不注册、不走 post 派发、也不问这个钩子。`check_death` 只按 hp 锁存一次，"留尸体还是 tick 末移除"是项目层决定。
- **Ability 状态不随死亡清除**：死亡时绝不 `revoke_ability`（那会清掉冷却 / execution / modifier，破坏复活语义）。三层分离 —— Ability 本体跟 actor 永存、pre / post handler 注册跟 ability 效果与 registry 走（`remove_effects` / `remove_actor` 注销，`end()` 时 `remove_all_handlers` 清空）、运行时响应跟 `is_event_responsive` 走。
- **Config 驱动跨属性 clamp**：跨属性约束（如 hp ≤ max_hp）必须声明在 attribute config 的 `maxRef` / `minRef`、由生成器产出 `register_cross_attr_clamp` 调用；**禁止**在 Actor 里用 `set_pre_change` 注入 Callable —— lambda 捕获 owner 会形成无法 GC 的闭包循环。
- **子对象回指 container 禁止强引用**：子对象指向所属 container 一律用 String id 或 `WeakRef`（`AbilityComponent._ability_ref` / `System._instance_ref` / `BattleProcedure._world`）；`BattleProcedure` 子类要具体世界类型就协变覆盖 `_get_world()`，不另存 world 字段（`world._active_battle` 强持 procedure，强回指即成环），procedure 持有的对象也只经调用参数拿 world；需要所属 instance 时按 owner id 反查（`GameWorld.get_instance_of_actor`），**不**在 AbilitySet / Ability / execution 上绑引用。context 对象（`ExecutionContext` / `AbilityLifecycleContext`）携带 `instance` 强引用，只许活在调用栈上、永不存进字段；`execution_state` 被 execution 强持有，同样不许放 instance / actor 这类 owning Object；既有的 `RecordingContext._recorder` 强引用靠 `BattleRecorder.stop_recording` / `abort_recording`（world 结束时由 `BattleProcedure.abort` 调）退订全部订阅闭包来打断；instance 自持的 `EventProcessor` / `EventCollector` 不回指 instance，processor 上的 pre / post handler 闭包只捕获 id（post handler 在 static 上下文里建，拿不到 Ability / Component / context）—— GDScript `RefCounted` 无循环 GC，字段缓存即真泄漏。
- **测试引擎按场景独立**：两种场景生命周期语义冲突（headless 的 shutdown 清场 vs UI 常驻 world）时各写一条 procedure（`SkillPreviewProcedure` vs `HexBattleProcedure`），而非硬塞兼容签名进一条引擎 —— 兼容参数会把 API 撑胖成坑。
- **View 是 state 的 reactive projection**：前端只能 `bind_world` + 订阅 mutation signal（`actor_added` / `actor_removed` / `grid_configured`）自动同步，**禁止任何 destructive 的 view 重建 API**（历史反例：已删除的 `FrontendBattleReplayScene.load_replay`）；且只订阅生命周期 / 结构变化，属性变化（HP / tag）交给 timeline 驱动的 Animator。
- **Playback 不重建逻辑层**：A 层"录像播放"（`Playback`）只从录像 dict spawn 视觉 view、绝不 hydrate 真 Actor / AbilitySet / AttributeSet；B 层"回放"（`Replay`，deterministic 重算）未来不一定做，相关类名仅作命名占位。
- **录像顺序 = 调用栈真实顺序**：所有录像事件统一走所属 world 的 `event_collector.push()` 单一队列（Action 经 `ctx.event_collector`，录像回调经注入 recorder 的同一个 collector），**禁止**按"入口类型"分两个容器再拼接 —— callback 在同步栈里穿插触发，任何固定拼接顺序都会丢失交错信息（反例：`damage1 → grant → damage2`）。
- **Action 是共享无状态对象**：Action 执行后必须 `_verify_unchanged()`，child action 必须随父 `_freeze()`，跨 tag 的临时状态放 execution-local state 而非 Action 字段 —— 详见 [Action 架构契约](./reference/action-architecture.md)。

## 版本历史

- **v0.4.0** - Actor ID 规范化，GameWorld.get_actor() 统一入口，BattleActor 战斗骨架基类
- **v0.3.0** - 重命名 `gameplay_state` → `game_state_provider`，添加 GameStateUtils 最佳实践
- **v0.2.0** - Action 构造函数重构：Dictionary → 类型化参数
- **v0.1.0** - 初始版本，从 TypeScript 迁移

## Actor 管理架构 🎭

### Actor ID 规范

Actor ID 采用 `{instance_id}:{local_id}` 格式，支持跨实例查询：

```gdscript
# ID 格式示例
"battle_001:hero_001"  # instance_id = "battle_001", local_id = "hero_001"

# 使用 ActorId 工具类
var full_id := ActorId.format("battle_001", "hero_001")
var parsed := ActorId.parse(full_id)
print(parsed.instance_id)  # "battle_001"
print(parsed.local_id)     # "hero_001"
```

### 架构设计

```
GameWorld (Autoload 单例)
  └── get_actor(full_id)  ← 统一查询入口
        ↓ 解析 ActorId
  └── _instances: Dictionary<instance_id, GameplayInstance>
        └── GameplayInstance
              └── _actors: Array<Actor>
                    └── Actor
                          ├── get_id() → "{instance_id}:{local_id}"
                          ├── get_local_id() → "local_id"
                          └── (BattleActor) get_ability_set() / get_attribute_set()
```

### 查询 Actor

**框架层**：使用 `GameWorld.get_actor()` 统一入口

```gdscript
# ✅ 正确：框架层使用 GameWorld 查询
var actor := GameWorld.get_actor(actor_ref.id)
var ability_set := BattleActor.ability_set_of(actor)

# ❌ 错误：框架层不应把 ctx.instance 收窄成某个项目的具体世界类型
var battle := ctx.instance as HexWorldGameplayInstance
```

**项目层**：可以直接使用具体实例

```gdscript
# 必须有世界的读点经项目 helper 收窄（hex）；允许缺席的读点写 `var battle: HexWorldGameplayInstance = ctx.instance` 再判空
var battle := HexBattleGameStateUtils.world(ctx)
var actor := battle.get_actor(actor_id)
```

### 创建 Actor

Actor 必须通过 `GameplayInstance.create_actor()` 创建，以确保 ID 规范：

```gdscript
# ✅ 正确：通过 GameplayInstance 创建
var actor := instance.create_actor(func(): return CharacterActor.new(class_config))
# actor.get_id() → "instance_001:Character_001"

# ❌ 错误：直接 new 不会设置 instance_id
var actor := CharacterActor.new(class_config)
# actor.get_id() → "Character_001"（缺少 instance_id 前缀）
```

### BattleActor 协议

参与战斗管线的 Actor 继承 `BattleActor`（`core/entity/battle_actor.gd`）。基类**不**声明
`ability_set` / `attribute_set` 字段 —— 子类各持强类型字段，用协变返回覆盖两个虚函数：

```gdscript
class_name CharacterActor
extends BattleActor

var ability_set: BattleAbilitySet
var attribute_set: HexBattleCharacterAttributeSet

func get_ability_set() -> BattleAbilitySet:
    return ability_set

func get_attribute_set() -> HexBattleActorAttributeSet:
    return attribute_set
```

两个虚函数默认返回 `null`：只想共享位置 / 录像形状的**纯数据 actor**（overworld 玩家、NPC）
直接继承即可，`check_death()` 对它们恒返回 false（`has_hp()` 把"没血条"与"血条为 0"分开），
`setup_recording()` 只订阅生命周期一条。

框架层拿到的是 `Actor` 基类引用，用静态查询安全取 AbilitySet：

```gdscript
# 非 BattleActor（或纯数据 BattleActor）返回 null
var ability_set := BattleActor.ability_set_of(actor)
if ability_set != null:
    ability_set.add_loose_tag("buff", 1)
```

回合 / ATB 主循环里，一帧 ability runtime 走 `AbilitySet.tick_runtime(dt, logic_time) -> bool`：
内部顺序固定为 `tick` → 算 blocking → `tick_executions`，返回本帧是否有阻塞执行。
"哪些 ability 算阻塞"由项目子类覆盖 `_is_blocking_execution(ability)` 表达（默认全部阻塞）。
自行编排相位的实时 example（dota2）不走它，直接用 `has_executing_instances()` + `tick_executions()`。

### 设计原则

| 原则 | 说明 |
|------|------|
| **GameWorld 是唯一入口** | 框架层通过 GameWorld.get_actor() 查询 |
| **GameplayInstance 持有 Actor** | Actor 生命周期绑定到实例 |
| **ID 自描述归属** | `{instance_id}:{local_id}` 格式 |
| **Actor 中性 / BattleActor opt-in** | 战斗设施（死亡锁存 / AbilitySet / 录像默认订阅）住子类，`Actor` 不假设任何玩法 |

## 未来规划 / 已知债务

> 以下条目均为"设计未完全收敛"的挂账，**陈述事实 + 给出选项**，逐项与 owner 对齐后再落地。

### 已知债务

> 2026-07-03 起本节按 [线 3 提案](proposals/2026-07-03-known-debt-and-hex-architecture-proposal.md) 收敛——每条已有裁决与执行轮次，完成即标 ✅。

- ✅ **core → stdlib 反向依赖 (BattleRecorder)**（裁决 2026-07-03，轮 A 位移完成；轮 B 收尾）：录像是 core 一等公民——`BattleProcedure.finish()` 返回值即 recorder 输出、`EventCollector` 只服务录像/表演层、「录像顺序 = 调用栈真实顺序」是铁律——recorder 家族（`BattleRecorder` / `RecordingContext` / `RecordingUtils` / `ReplayData` / `ReplayLogPrinter`）已物理迁入 `core/playback/`（类名不变，零代码改动）；`ability.gd` 对 `TimeDurationComponent` 的字符串鸭子匹配（文档此前未记录的第三处反依赖）已改为 `on_ability_stack_refreshed()` component 钩子（轮 B）——core→stdlib 代码级反向依赖清零。否决：IRecorder 抽象 + 注入（YAGNI、改 core 接口波及三个 procedure 子类）；BattleProcedure 下放 stdlib（被 `WorldGameplayInstance._active_battle` / 工厂钩子钉死）。
- ✅ **ProjectileActor / projectile_events 在 core**（2026-07-03 轮 A 完成）：原「反向引用 stdlib 的 ProjectileSystem」描述经查证**不实**（core 内唯一命中是注释）；真实问题 = 玩法策略常量（bullet/hitscan/moba）住 core + 全仓仅 hex 一个 example 使用（dota2 / inkmon 白带）。裁决：投射物是 stdlib 可选件而非 core 一等公民——`ProjectileActor` / `ProjectileEvents` 工厂 / `ProjectileSystem` / collision detector 家族整体迁 `stdlib/projectile/`；`GameEvent.ProjectileHit` 强类型事件类按「事件类型定义归 core 注册表」原则留在 `game_event.gd`。
- ✅ **强类型事件与 Dictionary 的分工**（已裁决并落地 2026-07-03，轮 B + 轮 E）：**dict = 总线/序列化形态**（`EventCollector` 与录像边界的合法形态，`EventProcessor` / `MutableEvent` / `receive_event` / `on_event` 管线签名不切强类型）；**强类型 = 两端形态**（构造走 `create()`、消费走 `from_dict()` / 字段直访）。`is_match` 从四件套降级为可选（实测全仓真实调用 0 处，kind 常量比较是事实标准）。执行项：`AbilityActivate` 补齐 schema（logicTime / target 字段）消灭全仓仅存的 6 处手写事件 literal、删除零使用死类 `AbilityActivated`（轮 B）；4 个手写 `.get()` visualizer 改 from_dict、kind 字符串字面量常量化（轮 E）。否决：管线签名全切强类型（波及全部 example + inkmon 主游戏，违「少改 core」）；删 class 只留 kind 常量（违用户既有强类型意志，见架构 KB P084）。
- ✅ **Replay / Playback / Director 命名混用**（2026-07-03 轮 C 完成）：最小 rename 落地 = `ReplayData → PlaybackData`（文件名同步 `playback_data.gd` / `playback_log_printer.gd`）+ `load_replay → load_playback`（.gd 17 文件 69 处 + 现行文档，含主仓 inkmon 4 文件联动）。已核实录像 JSON 顶层 key 与 web 桥协议均不含 replay 字样，rename 零协议波及；`PROTOCOL_VERSION` 不动。明确不动：69 个 scenario 的 `assert_replay` 测试 DSL 名、`BattleRecorder` 家族（Recorder = 写入器语义无争议）、`playback_*` signal（词根已正确）、`initialize_from_replay` / `get_replay_data` 等含 replay 词根的其余方法（超出最小集，B 层语义重审时再议）、B 层占位名 `BattleReplayPlayer` / `BattleReplaySession`（仅存在于本句文档，代码零实现）。
- ✅ **28 个 hex 技能未迁移到 condition bundle helper**（2026-07-03 轮 D 完成）：`active/` 30 文件 = 28 个 byte-identical 手抄已机械迁 `apply_standard_active_gating`（链头包装形态，每文件 -5+1）+ `strike` 迁 `apply_basic_attack_gating`（silence 豁免自此为显式 API 调用而非「沉默的省略」）+ `move`（零门控，走 ActivateInstanceConfig 事件路由，不碰）。条件链尾→链头前移语义等价（纯查询条件 + 单 cost）。`SkillValidator` 豁免名单字符串错位（`"skill_move"` ≠ 实际 `"action_move"`）已在轮 B 先行修正。

### 未来规划（触发式重审，当前不修）

- **WorldGameplayInstance 把 grid 概念塞进 core**：`core/entity/world_gameplay_instance.gd` 直接引用姊妹 addon ultra-grid-map 的 `HexCoord` / `GridMapConfig` / `GridMapModel`（addon→addon 依赖，非 core→example）。**维持不修**（2026-07-03 线 3 复核）——现有 3 个 WorldGI 分支中，hex example 与 inkmon 主游戏（adr/0002 明确把 `grid` / `actor_position_changed` 钉为 GI 基类机器）都用 grid，仅 dota2 不用（白带字段无实害；其战斗推进也不走 `tick()` 的 blocking 循环、由前端时钟外部 drive `tick_once`——实时模型的既有绕行，已在源码注释文档化）。触发重审条件：再出现一个不用 grid 的 WorldGI 分支、或需把 LGF core 单独发布给外部用户。
