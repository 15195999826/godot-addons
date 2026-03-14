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
| [TargetSelector](./reference/target-selector.md) | 目标选择器的使用方式 |

### 实践指南

| 文档 | 描述 |
|------|------|
| [逻辑层到表演层数据传递](../example/hex-atb-battle/docs/logic-to-presentation-guide.md) | StageCue 事件、Timeline 配置、数据流架构 |

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
| **项目层** | 转换为具体类型并使用 | 项目定义的类型（如 `HexBattle`） |

#### 推荐做法：创建项目级 Utils 类

项目层应创建一个 `[ProjectName]GameStateUtils` 类，包含：
- 只有静态函数，不保存任何状态
- 显式指定 `game_state_provider` 的具体类型
- 封装所有需要访问游戏状态的辅助函数

```gdscript
## HexBattleGameStateUtils - 项目层的 GameState 辅助函数
class_name HexBattleGameStateUtils

## 获取角色显示名称
static func get_actor_display_name(actor_ref: ActorRef, game_state_provider: HexBattle) -> String:
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
    # 项目层负责类型转换
    var battle: HexBattle = ctx.game_state_provider
    
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
    var battle: HexBattle = ctx.game_state_provider
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
addons/logic-game-framework/example/
├── hex-atb-battle-core/        # 共享数据层（Core Layer）
│   └── events/                 # 强类型事件定义
│       └── battle_events.gd    # BattleEvents（DamageEvent, HealEvent 等）
│
├── hex-atb-battle/             # 逻辑层（Logic Layer）
│   ├── actions/                # 游戏特定 Action（伤害、治疗、移动）
│   ├── skills/                 # 技能配置
│   ├── battle.gd               # 战斗状态管理
│   └── utils/                  # 逻辑层辅助类
│
└── hex-atb-battle-frontend/    # 表演层（Presentation Layer）
    ├── visualizers/            # 事件可视化器（伤害数字、动画）
    ├── battle_player.gd        # 回放播放器
    └── scenes/                 # 3D 场景、UI
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
# hex-atb-battle-frontend/visualizers/damage_visualizer.gd
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
# 项目层可以使用具体类型
var battle: HexBattle = ctx.game_state_provider
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
