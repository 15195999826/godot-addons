class_name RecordingUtils
## 纯静态工具类：录像订阅辅助函数

## 订阅 AttributeSet 的属性变化
##
## 监听所有属性的变化，BaseGeneratedAttributeSet 已将原始 Dictionary 包装为
## GameEvent.AttributeChanged，此处直接序列化推入录像流。
## @param generated_attr_set 生成的 AttributeSet 类（继承 BaseGeneratedAttributeSet）
## @param ctx 录像上下文
## @return 取消订阅函数数组
static func record_attribute_changes(
	generated_attr_set: BaseGeneratedAttributeSet,
	ctx: RecordingContext
) -> Array[Callable]:
	var unsubscribes: Array[Callable] = []

	var listener_func := func(event: GameEvent.AttributeChanged) -> void:
		ctx.push_event(event.to_dict())

	unsubscribes.append(generated_attr_set.add_change_listener(listener_func))
	return unsubscribes

## 订阅 AbilitySet 的 Ability 生命周期变化
##
## 监听 Ability 的获得、移除、事件触发和执行实例激活，自动转换为对应事件。
## 同时自动订阅 Tag 变化（通过 AbilitySet.tag_container）。
##
## 订阅内容：
## - abilityGranted: Ability 被授予时
## - abilityRemoved: Ability 被移除时
## - abilityTriggered: Ability 收到事件且有 Component 被触发时
## - executionActivated: Ability 创建新的 ExecutionInstance 时（用于表演层获取 timelineId）
## - tagChanged: Tag 层数变化时
static func record_ability_set_changes(ability_set: AbilitySet, ctx: RecordingContext) -> Array[Callable]:
	var unsubscribes: Array[Callable] = []

	# 存储每个 Ability 的触发事件订阅取消函数
	var ability_trigger_unsubscribes := {}
	# 存储每个 Ability 的执行实例激活订阅取消函数
	var ability_execution_unsubscribes := {}

	# 为单个 Ability 订阅触发事件
	var subscribe_ability_triggered := func(ability: Ability) -> void:
		var ability_id := ability.id
		var ability_config_id := ability.config_id
		var unsubscribe := ability.add_triggered_listener(
			func(event: Dictionary, triggered_components: Array[String]) -> void:
				ctx.push_event(
					GameEvent.AbilityTriggered.create(
						ctx.actor_id,
						ability_id,
						ability_config_id,
						event.get("kind", "unknown"),
						triggered_components
					).to_dict()
				)
		)
		ability_trigger_unsubscribes[ability_id] = unsubscribe

	# 为单个 Ability 订阅执行实例激活事件
	var subscribe_ability_executions := func(ability: Ability) -> void:
		var ability_id := ability.id
		var ability_config_id := ability.config_id
		var unsubscribe := ability.add_execution_activated_listener(
			func(instance: AbilityExecutionInstance) -> void:
				var instance_id: String = instance.id if "id" in instance else ""
				var timeline_id: String = instance.timeline_id if "timeline_id" in instance else ""
				ctx.push_event(
					GameEvent.ExecutionActivated.create(
						ctx.actor_id,
						ability_id,
						ability_config_id,
						instance_id,
						timeline_id
					).to_dict()
				)
		)
		ability_execution_unsubscribes[ability_id] = unsubscribe

	# 为已存在的 Ability 订阅事件
	for ability in ability_set.get_abilities():
		subscribe_ability_triggered.call(ability)
		subscribe_ability_executions.call(ability)

	# 订阅 Ability 获得
	var granted_unsub := ability_set.on_ability_granted(
		func(ability: Ability, _ability_set: AbilitySet) -> void:
			# 记录 Ability 获得事件
			ctx.push_event(
				GameEvent.AbilityGranted.create(ctx.actor_id, {
					"instanceId": ability.id,
					"configId": ability.config_id,
				}).to_dict()
			)
			# 为新 Ability 订阅事件
			subscribe_ability_triggered.call(ability)
			subscribe_ability_executions.call(ability)
	)
	unsubscribes.append(granted_unsub)

	# 订阅 Ability 移除
	var revoked_unsub := ability_set.on_ability_revoked(
		func(ability: Ability, _reason: String, _ability_set: AbilitySet, _expire_reason: String) -> void:
			# 记录 Ability 移除事件
			ctx.push_event(
				GameEvent.AbilityRemoved.create(ctx.actor_id, ability.id).to_dict()
			)
			# 清理该 Ability 的订阅
			var ability_id := ability.id
			if ability_trigger_unsubscribes.has(ability_id):
				var trigger_unsub: Callable = ability_trigger_unsubscribes[ability_id]
				if trigger_unsub.is_valid():
					trigger_unsub.call()
				ability_trigger_unsubscribes.erase(ability_id)
			if ability_execution_unsubscribes.has(ability_id):
				var execution_unsub: Callable = ability_execution_unsubscribes[ability_id]
				if execution_unsub.is_valid():
					execution_unsub.call()
				ability_execution_unsubscribes.erase(ability_id)
	)
	unsubscribes.append(revoked_unsub)

	# 订阅 Tag 变化
	unsubscribes.append(record_tag_changes(ability_set.tag_container, ctx))

	# 添加清理所有 Ability 订阅的函数
	var cleanup_all := func() -> void:
		for unsub in ability_trigger_unsubscribes.values():
			if unsub is Callable and unsub.is_valid():
				unsub.call()
		ability_trigger_unsubscribes.clear()
		for unsub in ability_execution_unsubscribes.values():
			if unsub is Callable and unsub.is_valid():
				unsub.call()
		ability_execution_unsubscribes.clear()
	unsubscribes.append(cleanup_all)

	return unsubscribes

## 订阅 Tag 变化
##
## 监听所有来源（Loose/AutoDuration/Component）的 Tag 总层数变化，
## 自动转换为 TagChangedEvent。
static func record_tag_changes(tag_container: TagContainer, ctx: RecordingContext) -> Callable:
	var listener_func := func(tag: String, old_count: int, new_count: int, _container: TagContainer) -> void:
		ctx.push_event(
			GameEvent.TagChanged.create(
				ctx.actor_id,
				tag,
				old_count,
				new_count
			).to_dict()
		)

	return tag_container.on_tag_changed(listener_func)

## 订阅 Actor 生命周期事件
##
## 监听 Actor 的生成和销毁，自动转换为对应事件。
static func record_actor_lifecycle(actor: Actor, ctx: RecordingContext) -> Array[Callable]:
	var unsubscribes: Array[Callable] = []

	# 订阅 Actor 生成事件
	var spawn_listener := func() -> void:
		ctx.push_event(
			GameEvent.ActorSpawned.create(actor.id, actor.to_dict()).to_dict()
		)
	unsubscribes.append(actor.add_spawn_listener(spawn_listener))

	# 订阅 Actor 销毁事件
	var despawn_listener := func() -> void:
		ctx.push_event(
			GameEvent.ActorDestroyed.create(ctx.actor_id).to_dict()
		)
	unsubscribes.append(actor.add_despawn_listener(despawn_listener))

	return unsubscribes
