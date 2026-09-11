class_name AbilityLifecycleContext
extends RefCounted
## Ability 生命周期上下文
##
## 在 Ability 的 apply/remove/event 等生命周期方法中传递的上下文对象。
## 包含 Ability 运行所需的所有依赖引用。
##
## 栈作用域：只活在一次生命周期调用的调用栈上。`instance` 是强引用——Component / Ability
## 把 context（或 context.instance）存进字段，就接上 instance → actor → ability_set → ability
## → component → context → instance 这条环；RefCounted 没有循环 GC，整张图从此不再释放。

## 存活计数（所有构建）：测试在调用返回后断言它回到基线，同 ExecutionContext。
static var _live_count := 0

## 能力拥有者的 ID
var owner_actor_id: String

## 拥有者的属性集
var attribute_set: BaseGeneratedAttributeSet

## 当前能力实例
var ability: Ability

## 能力集合
var ability_set: AbilitySet

## 拥有者所属的 GameplayInstance（按 owner_actor_id 反查）。
## owner 未注册进 GameWorld（孤立单测、注册前的 grant）时为 null：必须有世界的逻辑判空后响亮报错，允许缺席的判空降级。
var instance: GameplayInstance

## 事件处理器：派生自 instance（`instance.event_processor`），instance 为 null 时为 null。
## 不可赋值（setter 报错）；backing 字段恒为空，调试器里读到的 null 不代表 processor 缺席。
var event_processor: EventProcessor:
	get:
		return instance.event_processor if instance != null else null
	set(_value):
		Log.assert_crash(false, "AbilityLifecycleContext", "event_processor 派生自 instance，不可赋值")


func _init(
	p_owner_actor_id: String,
	p_attribute_set: BaseGeneratedAttributeSet,
	p_ability: Ability,
	p_ability_set: AbilitySet,
	p_instance: GameplayInstance
) -> void:
	owner_actor_id = p_owner_actor_id
	attribute_set = p_attribute_set
	ability = p_ability
	ability_set = p_ability_set
	instance = p_instance
	_live_count += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_live_count -= 1


## 当前存活的实例数。
static func get_live_count() -> int:
	return _live_count


## 为 on_remove / 叠层 / Break 钩子建 context：手上有 ability、没有 AbilitySet 递来的 context。
##
## 与 handler 重建同一种找法：instance 按 owner id 反查，actor 从该 instance 取，两个 set 取自 actor。
## owner 未注册进 GameWorld（隔离单测）或不是 BattleActor 时 instance / attribute_set / ability_set 为 null，
## context 照建——清理类钩子不能因为 owner 缺席就不跑；会读这些字段的 component（StatModifier / Tag /
## DynamicStatModifier）要求测试注册 owner。
static func for_ability(ability: Ability) -> AbilityLifecycleContext:
	var owner_id := ability.owner_actor_id
	var owner_instance := GameWorld.get_instance_of_actor(owner_id)
	var actor: BattleActor = null
	if owner_instance != null:
		actor = owner_instance.get_actor(owner_id) as BattleActor
	return _from_actor(owner_id, ability, actor, owner_instance)


## 为 pre / post handler 按 id 重建 context（handler 闭包只带 id，不带 ability / context）。
##
## 返回 null = 本 handler 这一次不执行：owner 未注册或已移出 instance、owner 此刻不响应这条事件
## （is_event_responsive 返回 false）、不是 BattleActor 或没有 AbilitySet、ability 已不在 owner 的 AbilitySet 里
## （revoke 之后残留的注册）。
static func rebuild_for_handler(owner_id: String, ability_id: String, event_dict: Dictionary, phase: String) -> AbilityLifecycleContext:
	var owner_instance := GameWorld.get_instance_of_actor(owner_id)
	if owner_instance == null:
		return null
	var actor := owner_instance.get_actor(owner_id)
	if actor == null or not actor.is_event_responsive(event_dict, phase):
		return null
	var owner_ability_set := BattleActor.ability_set_of(actor)
	if owner_ability_set == null:
		return null
	var ability := owner_ability_set.find_ability_by_id(ability_id)
	if ability == null:
		return null
	return _from_actor(owner_id, ability, actor as BattleActor, owner_instance)


## 按 owner 反查的两个工厂共用的装配：两个 set 一律取自 actor。
static func _from_actor(owner_id: String, ability: Ability, actor: BattleActor, owner_instance: GameplayInstance) -> AbilityLifecycleContext:
	if actor == null:
		return AbilityLifecycleContext.new(owner_id, null, ability, null, owner_instance)
	return AbilityLifecycleContext.new(owner_id, actor.get_attribute_set(), ability, actor.get_ability_set(), owner_instance)
