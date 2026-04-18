# Ability Lifecycle 解耦：去 LifecycleContext 缓存 + 项目层 responsive hook

**日期**：2026-04-19  
**范围**：`core/abilities/*`、`core/entity/Actor.gd`、`core/world/gameplay_instance.gd`、`stdlib/components/dynamic_stat_modifier_component.gd`、测试  
**触发原因**：headless smoke 测试退出时报告 `60 resources still in use`；调查发现是结构性循环引用，不是 Godot bug

---

## 背景：观察到的症状

跑 `tests/smoke_frontend_main.tscn`（项目层全链路 smoke）退出时稳定报告：

```
WARNING: ObjectDB instances leaked at exit
ERROR: 60 resources still in use at exit
```

`--verbose` 看泄漏明细：60+ 个 `GDScript` / `RefCounted` 实例；refcount 分布集中（有几个值 20-90），提示是**结构化的循环引用**而不是偶发遗漏。

对比 `smoke_strike.tscn`（显式调了 `GameWorld.destroy()` 的测试）泄漏 44 个——说明 `destroy()` 也救不了，**泄漏源在 `GameWorld.shutdown` 之下更深的层级**。

## 考古：`AbilityLifecycleContext` 的真实用法

`AbilityLifecycleContext` 是传给所有 AbilityComponent 生命周期钩子的"上帝对象"，持 5 个字段强引用：

```gdscript
var owner_actor_id: String                   # 值类型
var attribute_set: BaseGeneratedAttributeSet # 对象引用
var ability: Ability                         # 对象引用 ← 循环根源
var ability_set: AbilitySet                  # 对象引用
var event_processor: EventProcessor          # 对象引用
```

grep 所有消费者（生产代码 + stdlib + example）：

| 字段 | 读取方 | 用途 |
|---|---|---|
| `owner_actor_id` | 多处 | 读 ID 字符串做过滤 |
| `event_processor` | **仅** `PreEventComponent.on_apply` 1 处 | 注册 handler（可直接用 `GameWorld.event_processor`，字段多余） |
| `attribute_set` | `StatModifierComponent`（2 处）、`DynamicStatModifierComponent`（2 处） | `.get_raw()` 操作 modifier |
| `ability` | `TagComponent`、`StatModifierComponent`、`cooldown_system`、`no_instance_component`、测试们 | **95% 只读 `.id` / `.config_id`** |
| `ability_set` | **仅** `TagComponent` 2 处 | 调 `_add_component_tags` / `_remove_component_tags` |

**结论 1**：除 `owner_actor_id` 外，4 个对象引用字段的绝大多数消费只读 ID 类字段（`.id`、`.config_id`）。

**结论 2**：`PreEventComponent.on_remove(_context)` 参数带 `_` 前缀，**完全不读 context**，只调闭包里的 `_unregister`。

## 既有约定：LGF 其实已经订好了规矩

框架下游设计中已有两处明示"ID 查询替代对象引用以避免循环"的既有约定：

**`Actor.get_owner_gameplay_instance()`**（`core/entity/Actor.gd`）：
```gdscript
## 通过 GameWorld 查询，避免循环引用
func get_owner_gameplay_instance() -> GameplayInstance:
    return GameWorld.get_instance_by_id(_instance_id)
```

**`HandlerContext`**（`core/events/handler_context.gd`）—— PreEvent handler 收到的 context：
```gdscript
var owner_id: String       # 只存 ID
var ability_id: String     # 只存 ID
var config_id: String      # 只存 ID
var game_state: Variant    # 游戏状态走 provider 抽象
```

**诊断**：`AbilityLifecycleContext` 是违反自家约定的**异类**。非精心设计，更像早期随手写 + 后人不敢碰。

## 三条循环

**循环 A（主犯）**：`Ability._lifecycle_context = context; context.ability = self`
- 缓存在 `apply_effects` 时形成
- 正常路径 `revoke_ability → remove_effects → _lifecycle_context = null` 可断
- 但 `HexBattle.end() → _instances.clear()` **跳过 revoke**，循环永不解开

**循环 B（同犯）**：`PreEventComponent._lifecycle_context = context` + handler lambda 捕获 `self`
- lambda 注册在 `EventProcessor._pre_handlers`（autoload 里，近似永生）
- lambda → self（PreEventComponent）→ `_lifecycle_context` → ability → `_components` → 回到 self
- `on_remove` 时的 `_unregister.call()` 是唯一解药，但和循环 A 同样依赖 revoke 路径

**循环 C（本轮不修）**：`Ability._components[C]` 和 `AbilityComponent._ability` 互相强引用
- 结构性循环，独立于 LifecycleContext
- GDScript RefCounted 无循环 GC，两者永远不归零
- **这才是 60/44 大部分泄漏的主犯**——即使 A/B 都断了，C 依然拖住整个 ability 对象图
- 规划下轮用 `WeakRef` 或显式销毁方案解决

## 方案演进

### 方案 P（否决）：改 `AbilityLifecycleContext` API 为"只存 ID + getter 查询"

```gdscript
# Hypothetical P
var ability: Ability:
    get:
        return GameWorld.get_actor(owner_actor_id).ability_set.find_ability_by_id(ability_id)
```

**否决原因**：用户（项目设计者）的原始直觉是对的 —— `LifecycleContext` 持对象引用是**性能考量**。方案 P 让每次读 `ctx.ability.id` 都做两次 dict 查询，动了不该动的地方。**诊断错了问题**：不是"持引用"错了，是"**长寿命对象缓存**持有 context"错了。

### 方案 Q（采纳）：`LifecycleContext` 不动，禁止长寿命对象缓存它

核心认识：`LifecycleContext` 本身是**短命数据容器**，创建后无 mutator、无 side effect、无内部状态（grep `context.xxx =` 全工程零匹配证实）。问题仅在于被 `Ability._lifecycle_context` 和 `PreEventComponent._lifecycle_context` **缓存**，使其被拖长到长寿命对象的生命周期。

**修法**：
- `Ability.remove_effects()` 签名保持无参，内部用 `_build_remove_context()` 按需精简重建（只需 3 字段）
- `PreEventComponent` 的注册 lambda 改成只捕获 String ID + 用户 Callable，触发时静态方法重建

**为啥签名不改**：如果 `remove_effects(ctx)` 改签名，`Ability.expire(reason)` 也得改 `expire(reason, ctx)`，`TimeDurationComponent._trigger_expiration` 里的 `_ability.expire(...)` 也得改——它没 ctx，只有 `_ability` 引用。签名级联不干净。内部重建是更少侵入的方案。

### 方案 R（补强 Q）：战斗结束清 handler 注册

即便 Q 断了循环，`event_processor._pre_handlers` 里的 `PreHandlerRegistration` 仍留存。它持有 handler/filter lambda —— 这些 lambda 在 Q 之后已不再捕获 PreEventComponent，所以**不再拖住整个 ability 对象图**，但 registration 对象本身依然累积。

**修法**：`GameplayInstance.end()` 遍历 `_actors` 调 `event_processor.remove_handlers_by_owner_id(actor.get_id())`。放在**基类统一做**而不是 `HexBattle` override —— 所有 `GameplayInstance` 子类自动受益。

## 关键设计决策

### 1. 为什么新加 `is_pre_event_responsive()` 而不是一刀切的 `is_active()`

**考虑过的方案**：在 Actor 基类加一个通用虚函数 `is_active()`，框架在所有 ability 触发点（PreEvent handler、`AbilitySet.receive_event`、`Ability.tick`）都查询它。

**否决原因**：会破坏亡语语义。亡语走 `NoInstanceComponent + process_post_event`，死者的 `is_active()` 返回 false 就会被拦。当前亡语能工作依赖一个**时序性契约**：`alive_actor_ids` 在 `check_death` **之前**快照 → 死者还在列表里 → 亡语 handler 能收到自己的 death event。这是项目层契约，框架不该代管。

**采纳的方案**：窄命名 `is_pre_event_responsive()`，只管 PreEvent 分发路径。POST event 分发继续由项目层传入 `alive_actor_ids` 决定；tick 完全不查。如果未来需要更多路径的 eligibility 控制，独立加 `is_tick_responsive()` 等，各管各的。

```gdscript
# core/entity/Actor.gd（框架层，中性命名）
func is_pre_event_responsive() -> bool:
    return true

# example/hex-atb-battle/character_actor.gd（项目层，领域语义）
func is_pre_event_responsive() -> bool:
    return not _is_dead
```

框架**永远不知道**"死亡"是什么概念，只暴露钩子。

### 2. 为什么不在死亡时 revoke abilities

原本段 B 设计是"actor 死亡时 revoke 所有 ability"，但这**破坏复活语义**：
- `revoke_ability` 将 ability 从 `_abilities` 数组移除
- cooldown / execution instance 进度 / 残余 modifier 全部随 ability 对象销毁
- 复活需要重新 `equip_abilities`，技能状态从头开始

用户指出后改为**三层分离**：

| 层 | 状态 | 生命周期 | 何时清 |
|---|---|---|---|
| **Ability 本体**（`AbilitySet._abilities`） | 冷却、execution、modifier | 跟 actor 走，复活无缝恢复 | **永不自动清**（除非主动 revoke） |
| **PreEvent handler 注册**（`event_processor._pre_handlers`） | 事件监听 | 跟战斗走 | 战斗结束时 `remove_handlers_by_owner_id` |
| **运行时响应** | 此刻是否触发 | 跟 is_dead 等状态走 | handler lambda 里 `is_pre_event_responsive()` 短路 |

复活时 `_is_dead = false` → 短路失效 → PreEvent 自动恢复响应，**无需重新注册 handler**。

### 3. "死后还想持续生效"走独立尸体 actor，不让死者继续响应

这是用户的设计决策。框架层只提供机制（responsive 短路），项目层按此决策实现：
- 亡语：`NoInstanceComponent` 监听 death event，触发瞬间 owner 还在 alive 列表 → 能响应
- 死后持续效果（比如"毒雾"）：创建独立的尸体 actor，有自己的 ability_set，不依赖死者

## Rebuild lambda 的三层 null 短路（兜底契约）

`PreEventComponent._rebuild_context` 的关键代码：

```gdscript
static func _rebuild_context(owner_id: String, ability_id: String) -> AbilityLifecycleContext:
    var actor := GameWorld.get_actor(owner_id)
    if actor == null: return null                          # 兜底 1: actor 不存在
    if not actor.is_pre_event_responsive(): return null    # 兜底 2: 项目层短路
    
    var ab_set: AbilitySet = null
    if "ability_set" in actor:
        ab_set = actor.get("ability_set")
    if ab_set == null: return null                         # 兜底 2.5: actor 无 ability_set
    
    var ability := ab_set.find_ability_by_id(ability_id)
    if ability == null: return null                        # 兜底 3: ability 已 revoke
    ...
```

调用方（handler / filter lambda）见到 null 一律返回 `pass_intent()`。保证即使框架某一层出了意外（actor 被 destroy、ability 被 revoke、项目层临时屏蔽），handler 始终安全降级，不抛异常不崩溃。

## 验证

| 测试 | Before | After |
|---|---|---|
| LGF 单元测试 (`run_tests.tscn`) | 59/59 ✅ | **59/59 ✅** |
| `smoke_strike.tscn` | PASS，44 resources leaked | PASS，41 leaked |
| `smoke_frontend_main.tscn` | PASS，60 resources leaked | PASS，57 leaked |

**数字下降有限的原因**：项目所有现有 skill（Strike / Thorn / Deathrattle / Vitality / Vigor）**均使用 `NoInstanceComponent + TriggerConfig`，不使用 `PreEventComponent`**。段 A/B 修的是 PreEvent 路径，当前零用户。

**本轮真实价值**：
1. 断了 LifecycleContext 的结构性循环 —— 以后写 PreEvent 被动不会引入泄漏
2. 建立了 `is_pre_event_responsive` hook —— 以后写 silence / stun / sleep 等状态有干净出口
3. 修复了潜在的"死者/已 revoke ability 的 PreEvent 幽灵响应"问题
4. 建立了"框架不知道领域语义，只暴露 hook"的明确边界
5. `pre_event_component_test` 走完整 GameWorld 注册流程，测试更贴近生产使用

## 未完成：Ability ↔ AbilityComponent 循环

`ability.gd:42` 初始化时 `component.initialize(self)` 把 Ability 存到 `AbilityComponent._ability`。双方互持强引用：

```
Ability._components: Array[AbilityComponent]
                     └─ Component._ability → Ability
```

这条循环独立于 LifecycleContext，是 60/44 泄漏数字的主犯。本轮明确**不处理**，留给下一轮讨论。

可行方向：
- **弱引用**：`AbilityComponent._ability` 改 `WeakRef`，所有 `_ability.xxx` 改 `get_ability().xxx`。调用面 grep 过仅 `time_duration_component.gd:25` 一处外部使用，侵入面小。
- **显式销毁**：`Ability.remove_effects` 末尾 `_components = []` 并让 component 清 `_ability = null`。要求 ability 必经 `remove_effects` 路径才销毁，对短命 ability 不友好。

推荐弱引用方向。
