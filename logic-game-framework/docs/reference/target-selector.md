# TargetSelector 参考

## 概述

`TargetSelector` 是目标选择器的基类，用于在 Action 执行时确定作用目标。

## 类层次结构

```
TargetSelector (基类)
├── TargetSelector.CurrentTarget    # 从当前事件获取目标
├── TargetSelector.AbilityOwner     # 获取 Ability 所有者
└── TargetSelector.Fixed            # 固定目标列表
```

## 工厂方法

推荐使用工厂方法创建 TargetSelector：

```gdscript
# 获取当前事件的目标
TargetSelector.current_target()

# 获取 Ability 的所有者
TargetSelector.ability_owner()

# 固定目标（测试用）
TargetSelector.fixed([actor_ref1, actor_ref2])
```

## 内置选择器

### CurrentTarget

从 `ExecutionContext` 的当前事件中获取目标。

```gdscript
var selector = TargetSelector.current_target()
# 或
var selector = TargetSelector.CurrentTarget.new()
```

**行为**：
- 从 `ctx.get_current_event()` 获取事件
- 读取事件的 `target` 字段（`ActorRef`）
- 返回 `[target]`（单元素数组）

**适用场景**：
- 技能对选定目标造成效果
- 大多数攻击/治疗技能

### AbilityOwner

获取当前 Ability 的所有者。

```gdscript
var selector = TargetSelector.ability_owner()
# 或
var selector = TargetSelector.AbilityOwner.new()
```

**行为**：
- 从 `ctx.ability.owner` 获取所有者
- 返回 `[owner]`（单元素数组）

**适用场景**：
- 自我治疗
- 自我增益
- 移动（移动的是自己）

### Fixed

返回固定的目标列表，主要用于测试。

```gdscript
var targets: Array[ActorRef] = [actor1, actor2]
var selector = TargetSelector.fixed(targets)
# 或
var selector = TargetSelector.Fixed.new(targets)
```

**行为**：
- 直接返回构造时传入的目标列表

**适用场景**：
- 单元测试
- 调试

## 自定义 TargetSelector

### 基本模板

```gdscript
class_name MyCustomSelector
extends TargetSelector

func select(ctx: ExecutionContext) -> Array[ActorRef]:
    # 实现自定义选择逻辑
    var targets: Array[ActorRef] = []
    
    # 例如：选择所有敌人
    var all_actors = ctx.game_state_provider.get_alive_actors()
    var owner_team = ctx.ability.owner.team
    
    for actor in all_actors:
        if actor.team != owner_team:
            targets.append(ActorRef.new(actor.id))
    
    return targets
```

### 示例：范围选择器

```gdscript
class_name AreaSelector
extends TargetSelector

var _center_selector: TargetSelector
var _radius: int

func _init(center_selector: TargetSelector, radius: int) -> void:
    _center_selector = center_selector
    _radius = radius

func select(ctx: ExecutionContext) -> Array[ActorRef]:
    var targets: Array[ActorRef] = []
    
    # 获取中心点
    var centers := _center_selector.select(ctx)
    if centers.is_empty():
        return targets
    
    var center_actor = ctx.game_state_provider.get_actor(centers[0].id)
    var center_pos = center_actor.hex_position
    
    # 获取范围内的所有目标
    var all_actors = ctx.game_state_provider.get_alive_actors()
    for actor in all_actors:
        var distance = hex_distance(center_pos, actor.hex_position)
        if distance <= _radius:
            targets.append(ActorRef.new(actor.id))
    
    return targets
```

### 示例：条件选择器

```gdscript
class_name FilteredSelector
extends TargetSelector

var _base_selector: TargetSelector
var _filter: Callable  # func(actor, ctx) -> bool

func _init(base_selector: TargetSelector, filter: Callable) -> void:
    _base_selector = base_selector
    _filter = filter

func select(ctx: ExecutionContext) -> Array[ActorRef]:
    var base_targets := _base_selector.select(ctx)
    var filtered: Array[ActorRef] = []
    
    for target in base_targets:
        var actor = ctx.game_state_provider.get_actor(target.id)
        if _filter.call(actor, ctx):
            filtered.append(target)
    
    return filtered

# 使用示例：只选择 HP 低于 50% 的目标
var low_hp_selector = FilteredSelector.new(
    TargetSelector.current_target(),
    func(actor, _ctx):
        return actor.get_current_hp() < actor.get_max_hp() * 0.5
)
```

## 在 Action 中使用

```gdscript
class_name MyAction
extends Action.BaseAction

func _init(target_selector: TargetSelector) -> void:
    super._init(target_selector)

func execute(ctx: ExecutionContext) -> ActionResult:
    # 使用 get_targets() 而非直接访问 _target_selector
    var targets := get_targets(ctx)
    
    for target in targets:
        # 对每个目标执行效果
        pass
    
    return ActionResult.create_success_result([])
```

## 最佳实践

1. **使用工厂方法**
   
   优先使用 `TargetSelector.current_target()` 等工厂方法，而非直接 `new()`。

2. **不要在 Action 中硬编码目标**
   
   始终通过 TargetSelector 获取目标，保持 Action 的通用性。

3. **组合选择器**
   
   复杂的选择逻辑可以通过组合多个选择器实现。

4. **测试时使用 Fixed**
   
   单元测试中使用 `TargetSelector.fixed()` 提供确定性的目标。
