# Action 系统参考

## 概述

Action 是技能效果的最小执行单元。每个 Action 负责一个具体的效果（伤害、治疗、移动等），并产生对应的事件供回放系统使用。

## 基类：Action.BaseAction

所有 Action 都继承自 `Action.BaseAction`。

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `type` | `String` | Action 类型标识 |
| `_target_selector` | `TargetSelector` | 目标选择器 |

### 方法

| 方法 | 返回值 | 描述 |
|------|--------|------|
| `execute(ctx: ExecutionContext)` | `ActionResult` | 执行 Action，返回结果 |
| `get_targets(ctx: ExecutionContext)` | `Array[ActorRef]` | 获取目标列表 |

### 构造函数规范

```gdscript
func _init(target_selector: TargetSelector = null) -> void:
    if target_selector != null:
        _target_selector = target_selector
    else:
        _target_selector = TargetSelector.current_target()
```

## 创建自定义 Action

### 基本模板

```gdscript
class_name MyCustomAction
extends Action.BaseAction

var _my_param: float

## 构造函数
## @param target_selector: 目标选择器
## @param my_param: 自定义参数
func _init(
    target_selector: TargetSelector,
    my_param: float
) -> void:
    super._init(target_selector)  # ⚠️ 必须调用！
    type = "my_custom"
    _my_param = my_param

func execute(ctx: ExecutionContext) -> ActionResult:
    var targets := get_targets(ctx)
    var all_events: Array = []
    
    for target in targets:
        # 执行效果...
        var event: Dictionary = ctx.event_collector.push({
            "kind": "my_custom_event",
            "target_actor_id": target.id,
            "value": _my_param,
        })
        all_events.append(event)
    
    return ActionResult.create_success_result(all_events)
```

### 关键要点

1. **必须调用 `super._init(target_selector)`**
   
   GDScript 不会自动调用父类构造函数。如果忘记调用，`_target_selector` 将为 `null`。

2. **设置 `type` 属性**
   
   用于标识 Action 类型，便于调试和日志。

3. **使用 `get_targets(ctx)` 获取目标**
   
   不要直接访问 `_target_selector`，使用 `get_targets()` 方法。

4. **通过 `ctx.event_collector.push()` 产生事件**
   
   所有效果都应该产生事件，供回放系统使用。

## 回调系统

某些 Action 支持回调，允许在特定条件下触发额外效果。

### HexBattleDamageAction 回调

| 回调方法 | 触发条件 |
|----------|----------|
| `on_hit(action)` | 每次命中时 |
| `on_critical(action)` | 暴击时 |
| `on_kill(action)` | 击杀目标时 |

### 使用示例

```gdscript
# 暴击时额外造成 10 点伤害
HexBattleDamageAction.new(
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

# 击杀时治疗自己
HexBattleDamageAction.new(
    TargetSelector.current_target(),
    100.0,
    DamageType.PHYSICAL
).on_kill(
    HexBattleHealAction.new(
        TargetSelector.ability_owner(),
        20.0
    )
)
```

### 实现回调系统

```gdscript
class_name MyActionWithCallbacks
extends Action.BaseAction

var _on_success_callbacks: Array[Action.BaseAction] = []

func on_success(action: Action.BaseAction) -> MyActionWithCallbacks:
    _on_success_callbacks.append(action)
    return self  # 支持链式调用

func execute(ctx: ExecutionContext) -> ActionResult:
    # ... 执行主逻辑 ...
    
    # 触发回调
    if success_condition:
        var callback_ctx := ExecutionContext.create_callback_context(ctx, main_event)
        for callback in _on_success_callbacks:
            var result := callback.execute(callback_ctx)
            if result != null and result.events:
                all_events.append_array(result.events)
    
    return ActionResult.create_success_result(all_events)
```

## 内置 Action 列表

### 框架标准库

| Action | 描述 | 构造函数 |
|--------|------|----------|
| `Action.NoopAction` | 空操作 | `NoopAction.new(target_selector?)` |
| `StageCueAction` | 发送舞台提示 | `StageCueAction.new(target_selector, cue_id, params?)` |

### HexBattle 示例

| Action | 描述 | 构造函数 |
|--------|------|----------|
| `HexBattleDamageAction` | 造成伤害 | `new(target_selector, damage, damage_type?)` |
| `HexBattleHealAction` | 治疗 | `new(target_selector, heal_amount)` |
| `HexBattleStartMoveAction` | 开始移动 | `new(target_selector, target_coord)` |
| `HexBattleApplyMoveAction` | 应用移动 | `new(target_selector, target_coord)` |

## 构造函数参数类型

### 静态值 vs Callable

某些参数支持 `Callable`，允许在执行时动态计算：

```gdscript
# 静态值
HexBattleDamageAction.new(
    TargetSelector.current_target(),
    50.0,  # 固定 50 点伤害
    DamageType.PHYSICAL
)

# 动态值（Callable）
HexBattleDamageAction.new(
    TargetSelector.current_target(),
    func(ctx: ExecutionContext) -> float:
        # 根据攻击者属性计算伤害
        var attacker = ctx.game_state_provider.get_actor(ctx.ability.owner.id)
        return attacker.get_attack() * 1.5,
    DamageType.PHYSICAL
)
```

### 支持 Callable 的参数

| Action | 参数 | 类型 |
|--------|------|------|
| `HexBattleHealAction` | `heal_amount` | `float` 或 `Callable` |
| `HexBattleStartMoveAction` | `target_coord` | `Dictionary` 或 `Callable` |
| `HexBattleApplyMoveAction` | `target_coord` | `Dictionary` 或 `Callable` |
| `StageCueAction` | `cue_id` | `String` 或 `Callable` |
| `StageCueAction` | `cue_params` | `Dictionary` 或 `Callable` |

## ActionResult

Action 执行后返回 `ActionResult`：

```gdscript
# 成功
ActionResult.create_success_result(events, metadata?)

# 失败
ActionResult.create_failure_result(error_message)
```

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `success` | `bool` | 是否成功 |
| `events` | `Array` | 产生的事件列表 |
| `metadata` | `Dictionary` | 额外元数据 |
| `error` | `String` | 错误信息（失败时） |
