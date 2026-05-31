# Logic Game Framework 文档

本框架是一个用于构建回合制/ATB 战斗系统的 GDScript 框架，从 TypeScript 版本迁移而来。

## 快速开始

### 核心概念

- **Action**: 技能效果的最小执行单元（伤害、治疗、移动等）
- **Ability**: 技能配置，包含触发条件、消耗、Timeline 和 Actions
- **Timeline**: 定义技能执行的时间轴和关键帧（tags）
- **TargetSelector**: 目标选择器，决定 Action 作用于哪些目标
- **ExecutionContext**: 执行上下文，包含当前事件、Ability、game_state_provider 等

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

### 4. GameStateProvider 最佳实践

`ExecutionContext.game_state_provider` 是框架传递游戏状态的机制。**框架层不知道也不应该知道它的具体类型**，这是设计意图。

#### 框架层 vs 项目层

| 层级 | 职责 | 类型 |
|------|------|------|
| **框架层** | 传递游戏状态引用 | `Variant`（无类型） |
| **项目层** | 转换为具体类型并使用 | 项目定义的类型（如 `HexWorldGameplayInstance` 或其子类 `HexDemoWorldGameplayInstance` / `SkillPreviewWorldGI`） |

#### 推荐做法：创建项目级 Utils 类

项目层应创建一个 `[ProjectName]GameStateUtils` 类，包含：
- 只有静态函数，不保存任何状态
- 显式指定 `game_state_provider` 的具体类型
- 封装所有需要访问游戏状态的辅助函数

```gdscript
## HexBattleGameStateUtils - 项目层的 GameState 辅助函数
class_name HexBattleGameStateUtils

## 获取角色显示名称
static func get_actor_display_name(actor_ref: ActorRef, game_state_provider: HexWorldGameplayInstance) -> String:
    if actor_ref == null:
        return "???"
    if game_state_provider != null:
        var actor := game_state_provider.get_actor(actor_ref.id)
        if actor != null:
            return actor.get_display_name()
    return actor_ref.id
```

#### 在 Action 中使用

```gdscript
# 项目层 Action
class_name MyProjectDamageAction
extends Action.BaseAction

func execute(ctx: ExecutionContext) -> ActionResult:
    # 项目层负责类型转换 — 收敛到框架基类, 不绑死具体场景子类
    var battle: HexWorldGameplayInstance = ctx.game_state_provider

    # 获取存活角色 ID 列表（用于 Post 阶段广播）
    var alive_actor_ids: Array[String] = battle.get_alive_actor_ids()
    var name := HexBattleGameStateUtils.get_actor_display_name(target, battle)
    
    # ... 业务逻辑
    
    # Post 阶段：EventProcessor 通过 GameWorld.get_actor() + IAbilitySetOwner 获取 AbilitySet
    event_processor.process_post_event(damage_event, alive_actor_ids, battle)
```

#### 为什么这样设计？

1. **框架灵活性**：不同项目可以有完全不同的游戏状态结构
2. **类型安全**：项目层代码获得完整的类型检查和自动补全
3. **代码复用**：辅助函数集中在一处，避免重复
4. **关注点分离**：框架不依赖具体项目实现

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
    var battle: HexWorldGameplayInstance = ctx.game_state_provider
    var event_processor: EventProcessor = GameWorld.event_processor
    var alive_actor_ids: Array[String] = battle.get_alive_actor_ids()
    
    for target in targets:
        # ========== Pre 阶段 ==========
        var pre_event := { "kind": "pre_damage", "damage": _damage, ... }
        var mutable: MutableEvent = event_processor.process_pre_event(pre_event, battle)
        
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
                event_processor.process_post_event(death_event, alive_actor_ids, battle)
                battle.remove_actor(target.id)
        
        # ========== Post 阶段 ==========
        event_processor.process_post_event(damage_event, alive_actor_ids, battle)
    
    return ActionResult.create_success_result(all_events, { "damage": _damage })
```

#### 错误模式（已废弃）

```gdscript
# ❌ 错误：状态同步在 tick() 中延迟处理
func tick(dt: float) -> void:
    # ... 执行 Action ...
    
    var frame_events := event_collector.flush()
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
    
    # 收集本帧事件（仅用于录像，状态已在 Action 内同步）
    var frame_events := event_collector.flush()
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
│   └── timeline/           # Timeline 系统
├── stdlib/                  # 标准库
│   └── actions/            # 通用 Action（StageCueAction 等）
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

属性变化（HP / tag）**不**走 signal —— 交给叠加层 `FrontendBattleAnimator` 消费 event_timeline 驱动飘字 / 特效 / 死亡动画。这是关键解耦：战斗期间 unit view 停在开战时的视觉状态，signal 只服务非战斗期的 view lifecycle；战斗结束后 WorldGI 里 actor 已是终态，animator 播完 timeline 视觉自然追上。`WorldView` **没有** `load_replay` 这种 destructive API，只有 `bind_world` + 订阅。

### (c) recorder 单 buffer + playback 模型

`BattleProcedure` 持有短命的 `BattleRecorder`，随 procedure 销毁。录像的核心不变量是 **"调用栈真实顺序 = 录像顺序"**：Action 的 `event_collector.push` 与 callback 触发的 AttributeChanged / AbilityGranted 在同一调用栈穿插发生，因此 recorder **不分** `pending_events` / `frame_events` 双容器，而是统一汇入 `GameWorld.event_collector` 单一队列，`record_frame(frame, events)` 每帧只接收 flush 出的一个有序数组。

播放侧钉死两层命名：**A 层 `Playback`（现役）** 只从录像 dict spawn 视觉 view、不重建逻辑层；**B 层 `Replay`（deterministic 重算，未来不一定做）** 仅保留 `BattleReplayPlayer` / `BattleReplaySession` 命名占位。录像格式停在 v2，`PROTOCOL_VERSION` 不升，外部消费方（JS / cloud）不受影响。

## 设计铁律

框架演进中固化下来的不可违反约束（蒸馏自历史架构决策，违反会重新引入已根治的 bug）：

- **Ability lifecycle hook**：框架层只暴露中性的 `is_pre_event_responsive()` 钩子、永不内置"死亡 / 沉默"等领域语义，由项目层 override 决定 PreEvent 是否短路响应 —— 框架不该代管亡语的 `alive_actor_ids` 时序契约。
- **Ability 状态不随死亡清除**：死亡时绝不 `revoke_ability`（那会清掉冷却 / execution / modifier，破坏复活语义）。三层分离 —— Ability 本体跟 actor 永存、PreEvent handler 跟战斗走（`end()` 时 `remove_handlers_by_owner_id`）、运行时响应跟 `is_dead` 状态走。
- **Config 驱动跨属性 clamp**：跨属性约束（如 hp ≤ max_hp）必须声明在 attribute config 的 `maxRef` / `minRef`、由生成器产出 `register_cross_attr_clamp` 调用；**禁止**在 Actor 里用 `set_pre_change` 注入 Callable —— lambda 捕获 owner 会形成无法 GC 的闭包循环。
- **子对象回指 container 禁止强引用**：子对象指向所属 container 一律用 `WeakRef`（类型明确时，如 `AbilityComponent._ability`）或调用链参数流（类型是 Variant 接口时，如 `game_state_provider` 不缓存而每次 tick 传入）—— GDScript `RefCounted` 无循环 GC，字段缓存即真泄漏。
- **测试引擎按场景独立**：两种场景生命周期语义冲突（headless 的 init/destroy vs UI 常驻 world）时各写一条 procedure（`SkillPreviewProcedure` vs `HexBattleProcedure`），而非硬塞兼容签名进一条引擎 —— 兼容参数会把 API 撑胖成坑。
- **View 是 state 的 reactive projection**：前端只能 `bind_world` + 订阅 mutation signal（`actor_added` / `actor_removed` / `grid_configured`）自动同步，**禁止任何 destructive 的 view 重建 API**（如 `load_replay`）；且只订阅生命周期 / 结构变化，属性变化（HP / tag）交给 timeline 驱动的 Animator。
- **Playback 不重建逻辑层**：A 层"录像播放"（`Playback`）只从录像 dict spawn 视觉 view、绝不 hydrate 真 Actor / AbilitySet / AttributeSet；B 层"回放"（`Replay`，deterministic 重算）未来不一定做，相关类名仅作命名占位。
- **录像顺序 = 调用栈真实顺序**：所有录像事件统一走 `GameWorld.event_collector.push()` 单一队列，**禁止**按"入口类型"分两个容器再拼接 —— callback 在同步栈里穿插触发，任何固定拼接顺序都会丢失交错信息（反例：`damage1 → grant → damage2`）。
- **Action 是共享无状态对象**：Action 执行后必须 `_verify_unchanged()`，child action 必须随父 `_freeze()`，跨 tag 的临时状态放 execution-local state 而非 Action 字段 —— 详见 [Action 架构契约](./reference/action-architecture.md)。

## 版本历史

- **v0.4.0** - Actor ID 规范化，GameWorld.get_actor() 统一入口，IAbilitySetOwner 接口模式
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
                          └── get_ability_set()  ← IAbilitySetOwner 协议
```

### 查询 Actor

**框架层**：使用 `GameWorld.get_actor()` 统一入口

```gdscript
# ✅ 正确：框架层使用 GameWorld 查询
var actor = GameWorld.get_actor(actor_ref.id)
var ability_set = IAbilitySetOwner.get_ability_set(actor)

# ❌ 错误：框架层不应依赖 game_state_provider 的具体类型
var actor = game_state_provider.get_actor(actor_ref.id)
```

**项目层**：可以直接使用具体实例

```gdscript
# 项目层可以使用具体类型 — 默认收敛到框架基类, 仅在需要场景独有字段时收窄
var battle: HexWorldGameplayInstance = ctx.game_state_provider
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

### IAbilitySetOwner 协议

Actor 如果持有 AbilitySet，需要实现 `get_ability_set()` 方法：

```gdscript
class_name CharacterActor
extends Actor

var ability_set: BattleAbilitySet

## 实现 IAbilitySetOwner 协议
func get_ability_set() -> BattleAbilitySet:
    return ability_set
```

框架层通过 `IAbilitySetOwner` 工具类安全获取：

```gdscript
# 安全获取，未实现协议返回 null
var ability_set := IAbilitySetOwner.get_ability_set(actor)
if ability_set != null:
    ability_set.apply_tag("buff", 1)
```

### 设计原则

| 原则 | 说明 |
|------|------|
| **GameWorld 是唯一入口** | 框架层通过 GameWorld.get_actor() 查询 |
| **GameplayInstance 持有 Actor** | Actor 生命周期绑定到实例 |
| **ID 自描述归属** | `{instance_id}:{local_id}` 格式 |
| **接口协议化** | 使用 `IXxx` 静态工具类检测协议 |

## 未来规划 / 已知债务

> 以下条目均为"设计未完全收敛"的挂账，**陈述事实 + 给出选项**，逐项与 owner 对齐后再落地。

### 已知债务

- **core → stdlib 反向依赖 (BattleRecorder)**：依赖图规定 stdlib 建在 core 之上，但 `core/entity/battle_procedure.gd` 直接持有并构造 stdlib 的 `BattleRecorder`（`_recorder` / `get_recorder()`），`Actor.gd` 也多处引用。破坏单向依赖图，阻塞把 core 拆成独立 addon，且替换 recorder 实现（NoopRecorder / NetworkRecorder）必须改 core。候选：core 定义 `IRecorder` interface（A）/ `BattleProcedure` 整体下放 stdlib（B）/ 把 BattleRecorder 物理移进 core（C）。待决断 recorder 是否属于 core 概念。
- **ProjectileActor / projectile_events 在 core**：`core/entity/projectile_actor.gd` 硬编码玩法常量（`PROJECTILE_TYPE_BULLET / HITSCAN / MOBA`）并反向引用 stdlib 的 `ProjectileSystem`；`core/events/projectile_events.gd` 同理。不做投射物的 example（纯回合卡牌）继承 core 时白带此类型。候选：整体迁 `stdlib/projectile/`，或承认投射物是当前定位的一等公民。与 BattleRecorder 同批讨论 "core 边界"。
- **强类型事件最后落回 Dictionary**：`core/events/game_event.gd` 定义 ~12 个强类型 class，但所有消费路径（`EventProcessor` / `MutableEvent` / `Ability.receive_event` / `EventCollector` / 各 component 的 `on_event`）仍吃 `Dictionary`，强类型只活在构造（`.to_dict()`）与反序列化（`from_dict()`）两个端点。结果：强类型纯文档、编译器不强制、field 拼错只能等 KeyError。候选：全切强类型签名（A）/ 删 class 只留 kind 常量（B）/ 仅 hot path（damage / attribute_changed）切（C）。需先拍板"这层要不要"。
- **Replay / Playback / Director 命名混用**：同一概念三套词交叉 —— stdlib 数据类用 **Replay**（`ReplayData` / `replay_data.gd`）、写入器用 **Recorder**（`BattleRecorder`）、frontend signal 用 **playback**、frontend API 又用 **replay 动词**（`load_replay`）、UI 用 **Playback**。立场已定：A 层 = Playback（现役），B 层 = Replay（未来不一定做）；当前命名让"现役 = A 层"在代码里看不出来。计划随 A 层整合那轮捎带 rename（`ReplayData → PlaybackData` / `load_replay → load_playback`）。
- **28 个 hex 技能未迁移到 condition bundle helper**：标准主动技能门控四件套（`NoTagCondition(cant_act)` + `NoTagCondition(silence)` + `CooldownCondition` + `TimedCooldownCost`）在 ~28 个技能里 byte-identical 手抄，手抄是唯一"正确性保证"。helper 已就位（`HexBattleCooldownSystem.apply_standard_active_gating` / `apply_basic_attack_gating`），`SkillValidator` Stage5 已 advisory 检测漏写（warn-only，strike/move 具名豁免）。待做：~26 个标准技能改用 helper、`strike` 改 `apply_basic_attack_gating`、`move` 不碰。单独成轮：28 文件 diff + 全量 hex 回归面，收益是防漂移而非修 bug。

### 未来规划（触发式重审，当前不修）

- **WorldGameplayInstance 把 hex 概念塞进 core**：`core/entity/world_gameplay_instance.gd` 直接 import `HexCoord` / `GridMapConfig` / `GridMapModel`。当前路线图下**不视为问题** —— 在第二个非 hex example 落地前，把 grid 抽成 `ISpatialBackend` 属过度工程。触发重审条件：立项完全脱离 grid 的 example（纯卡牌 / 文字冒险）、需把 LGF core 单独发布给外部用户、或 `WorldGameplayInstance` 子类增至 3+ 且其中超过一个不用 grid。
