# 结构性循环根治：WeakRef + 调用链参数流

**日期**：2026-04-19（续：同日更晚轮次）
**范围**：`core/abilities/core/ability_component.gd`、`core/abilities/core/ability.gd`、`core/abilities/core/ability_execution_instance.gd`、`core/abilities/core/ability_set.gd`、`core/entity/System.gd`、`stdlib/components/time_duration_component.gd`、`stdlib/systems/projectile_system.gd`、上层调用方与测试
**前置**：`2026-04-19-ability-lifecycle-decoupling.md`（同日早轮次，修复循环 A/B）

---

## 背景

前一轮断了 `Ability._lifecycle_context` 和 `PreEventComponent._lifecycle_context` 两条循环（循环 A/B），但泄漏数字降幅极小（`smoke_frontend_main` 60→57、`smoke_strike` 44→41）。前一轮的 design note 末尾标注了**循环 C 未修**，并推测它是主犯。本轮开工前先做了 PREDELETE probe 验证。

## 定位：三个结构性循环

PREDELETE probe 验证手段：在 `_init` 打印 `get_instance_id()`，在 `_notification(NOTIFICATION_PREDELETE)` 打印同一 id。跑 smoke 比对创建 vs 析构计数。

### 循环 C：Ability ↔ AbilityComponent（前轮标注，本轮确认并修复）

```
Ability._components: Array[AbilityComponent]   ← Array 强持 Component
  └─ AbilityComponent._ability: Ability         ← Component 强持 Ability
```

**Probe 结果（未修时）**：smoke_strike 6 Ability / 6 Component 全部 0 析构。`Ability.remove_effects()` 只调 `on_remove` + 清 callback 数组，**没有清空 `_components` 数组**——即使 `remove_effects` 被调，循环依然锁死。

### 循环 D：battle → ... → AbilityExecutionInstance → provider = battle（本轮新发现）

```
GameplayInstance (= battle)
  └─ _actors[]: Array[Actor]
      └─ Actor.ability_set
          └─ AbilitySet._abilities[]
              └─ Ability._execution_instances[]
                  └─ AbilityExecutionInstance._game_state_provider = battle  ← 回指！
```

**Probe 结果**：Strike 触发时产生 1 个 execution instance（Strike 的 timeline）。该 instance 持 `_game_state_provider = battle`。即便 shutdown 后 `GameWorld._instances.clear()` 解除一份引用，execution instance 那份仍在——**一个 execution instance 就能锁住整个 battle 对象图（6 abilities + 2 actors + 1 battle）**。

### 循环 E：GameplayInstance ↔ System（本轮调研时顺带发现）

```
GameplayInstance._systems: Array[System]
  └─ System._instance: GameplayInstance        ← 回指！
```

与循环 C 同形状。`ProjectileSystem` 是项目内唯一触发者——`smoke_strike` 因未调 `battle.start()` 不触发，但正式 HexBattle 和 `smoke_frontend_main` 都触发。

`GameplayInstance.end()` 遍历调 `system.on_unregister()` 清 `_instance = null`——但这是**纪律性防御**（依赖 end 被正确调用）。

---

## 关键架构认识：子对象回指 container 禁止强引用

框架内 owner/child 关系的既有处理不一致：

| 关系 | 既有处理 | 状态 |
|---|---|---|
| `Actor._instance_id: String` → `GameplayInstance` | String id + getter 查询 | 正确 |
| `HandlerContext.game_state: Variant` | 调用时参数，不缓存 | 正确 |
| `ExecutionContext.game_state_provider: Variant` | 调用时构造，不持久缓存 | 正确 |
| **`AbilityComponent._ability`** | **强引用** | 违反约定（循环 C）|
| **`AbilityExecutionInstance._game_state_provider`** | **字段缓存** | 违反约定（循环 D）|
| **`System._instance`** | **强引用** | 违反约定（循环 E）|

本轮确立统一原则并代码化到前三个异类：**子对象回指所属 container 禁止强引用，一律用 WeakRef 或 String id**。

选择标准：
- **WeakRef**：当类型是框架明确的（如 `AbilityComponent._ability: Ability`、`System._instance: GameplayInstance`），直接 WeakRef；不需要 ID 字段。语义上 Component / System 对 owner 的引用"存在即用，不 prevent 销毁"。
- **调用链参数**：当类型是项目层泛化接口（`game_state_provider: Variant` 允许任意实现 `IGameStateProvider` 接口），且本来就有调用入口携带该参数的路径（如 `receive_event`、`tick_executions`），不缓存，每次由调用链传入。

循环 D 选第二种（provider 是 Variant，WeakRef 只能对 Object）。循环 C/E 选第一种（类型明确）。

---

## 修复细节

### 循环 C：AbilityComponent 弱引用化

```gdscript
# core/abilities/core/ability_component.gd
var _ability_ref: WeakRef = null

func initialize(ability: Ability) -> void:
    _ability_ref = weakref(ability) if ability != null else null
    _state = "active"

func get_ability() -> Ability:
    if _ability_ref == null:
        return null
    return _ability_ref.get_ref() as Ability
```

唯一外部消费点 `stdlib/components/time_duration_component.gd`：

```gdscript
func _trigger_expiration() -> void:
    mark_expired()
    var ability := get_ability()
    if ability != null:
        ability.expire(EXPIRE_REASON_TIME_DURATION)
```

子类不再允许直接 `_ability.xxx`——必须走 `get_ability()` 并检查 null。这是一个**语义强化**：Component 对 Ability 的访问从"已存在所有权"变为"弱引用查询"，反映了 Component 是 Ability 的附属而非所有者。

### 循环 D：删字段，参数流

彻底移除 `AbilityExecutionInstance._game_state_provider` 字段。所有需要 provider 的方法加参数：

```gdscript
# 原
func tick(dt: float) -> Array[String]: ...
func fire_sync_actions(actions, current_tag) -> void: ...
func _build_execution_context(current_tag) -> ExecutionContext: ...

# 后
func tick(dt: float, game_state_provider: Variant) -> Array[String]: ...
func fire_sync_actions(actions, current_tag, game_state_provider) -> void: ...
func _build_execution_context(current_tag, game_state_provider) -> ExecutionContext: ...
```

`Ability.activate_new_execution_instance` 的 `p_game_state_provider` 参数**保留但不存**：只用于激活瞬间 `fire_sync_actions(p_on_timeline_start_actions, "__timeline_start__", p_game_state_provider)` 一次性触发 on_timeline_start。这符合"provider 作为参数流动"的语义。

级联改动范围（仅 tick 路径，event 路径本已正确）：
- `AbilitySet.tick_executions(dt, provider)`
- `Ability.tick_executions(dt, provider)`
- 调用入口 `hex_battle.gd:343`、`scripts/SkillPreviewBattle.gd:98`、`tests/smoke_strike.gd:71`

测试对齐：`ability_execution_instance_test.gd`、`ability_test.gd`、`timeline_loop_test.gd` 的所有 `.new()` / `.tick()` / `.fire_sync_actions()` 调用。

### 循环 E：System 弱引用化

与循环 C 同形状，同样模式：

```gdscript
# core/entity/System.gd
var _instance_ref: WeakRef = null

func on_register(instance: GameplayInstance) -> void:
    _instance_ref = weakref(instance) if instance != null else null

func on_unregister() -> void:
    _instance_ref = null

func get_instance() -> GameplayInstance:
    if _instance_ref == null:
        return null
    return _instance_ref.get_ref() as GameplayInstance

func get_logic_time() -> float:
    var instance := get_instance()
    if instance == null:
        return 0.0
    return instance.get_logic_time()
```

唯一外部消费点 `stdlib/systems/projectile_system.gd::_process_pending_removal` 改走 `get_instance()`。

**为什么即使 `end()` 已经做了 unregister 还要 WeakRef**：纪律防御 → 结构防御的质变。未来新增的 GameplayInstance 销毁路径、异常退出、测试中 instance 被 dict.clear 直接剔除等场景，都不再依赖 end() 被正确调用。

---

## 为什么不选方案 1（`GameplayInstance.end()` 里遍历 `cancel_all_executions()`）

针对循环 D，当时讨论过方案 1：在 `GameplayInstance.end()` 末尾遍历所有 ability 调 `cancel_all_executions()`（该方法存在但从来没被任何地方调用），顺势清空 `_execution_instances` 从而释放 `_game_state_provider`。

否决原因：

1. **同类反模式堆叠**：前一轮已经把 "`remove_handlers_by_owner_id`" 塞进了 `GameplayInstance.end()`。如果这一轮再加 `cancel_all_executions` 清理逻辑，`end()` 会变成"清理 kitchen sink"。code smell——多次往同一个防御点堆逻辑意味着**问题根源不在清理时机而在引用关系本身**。
2. **违反框架既有约定**：`AbilityExecutionInstance._game_state_provider` 是唯一一个缓存 provider 的地方，`HandlerContext` / `ExecutionContext` / `Component.on_event` 等所有同类场景都走"调用时参数"模式。让这一个异类保持"靠 end 清理"而不回归既有约定，是在固化异类。
3. **未来风险**：任何新增的 instance 销毁路径都要记得调 `cancel_all_executions`。

方案 5（删字段 + 参数流）直接消除异类，让 `AbilityExecutionInstance` 对齐框架约定。

---

## 未尽事项

### smoke_strike 仍有 38 个资源泄漏

断了 C/D/E 三条循环后，`smoke_strike` 从 41 降到 38。probe 显示：

```
shutdown.before_end: battle refcount=3
shutdown.after_end:  battle refcount=3       # end() 没释放外部引用
shutdown.after_clear: refcount=2, 仍存活       # clear 解除 _instances[] 那份，还剩 1 个外部引用
```

（其中 refcount 包含 probe 函数内部的局部变量 1 份，实际真实外部引用为 1。）

进程退出时 `GameplayInstance._predelete` 从未触发——即 battle 最终没析构，链条仍锁死。

这**不是循环 C/D/E**（已验证）。可能的候选：
- **Action 对象持 Callable** 绑定到 battle 或 actor
- **event_collector 的事件字典** 某个字段存了对象引用而非 id（需要审查 damage_event / ability_activate_event 的字典格式）
- **`UGridMap.place_occupant(coord, actor)`** —— UGridMap 是 autoload 永生，持 actor 强引用；actor 通过某种路径间接持 battle？
- **smoke 测试结构问题**：`_ready` 局部变量 `var battle` 理论上返回时释放，但 Godot 的 quit(0) 时序可能让某些引用未及时释放

需要新一轮 probe 深挖（`Action.execute` 前后对比、event_dict 内容检查、UGridMap model 清理）。独立问题，不阻塞本轮结构性修复落地。

### 数字解读

本轮三个循环理论上应该带来大幅下降，但 `smoke_strike` 只降 3、`smoke_frontend` 降 11 的原因：**另一个未识别的循环持续拖着 battle 对象图**。因此循环 C/D/E 的真实收益被低估——frontend 降 11 是循环 D（provider 字段删除）的真实体现；smoke_strike 的 circular path 被其他循环压住了，看不到提升。

下一轮解决未知循环后，数字应该显著下降到个位数或 0。

---

## 方法论总结

1. **承认"长寿命对象缓存"是反模式**。字段缓存外部对象引用是初学者陷阱，在 GDScript/RefCounted 下尤其致命——没有循环 GC，所有互持都是真泄漏。
2. **PREDELETE probe 比猜测快 10 倍**。怀疑对象泄漏时 `_init` + `_notification(NOTIFICATION_PREDELETE)` 加 id 打印，跑一遍就有事实。
3. **先定位，再设计**。本轮开始前尝试直接按上一轮 handoff 推荐动手，被用户拦下问"这是架构合理的方案吗"——强制讨论后识别出循环 D 是真凶、循环 C 只是次要，并发现循环 E。如果跳过讨论直接改，会漏修一半。
4. **方案的"对"不等于数字的大幅下降**。循环 E 本轮数字贡献为 0（因为 `end()` 碰巧清掉了），但它依然值得修——把纪律防御变成结构防御，未来新场景才不会再踩。
