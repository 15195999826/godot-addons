class_name AbilitySet
extends RefCounted

const REVOKE_REASON_EXPIRED := "expired"
const REVOKE_REASON_DISPELLED := "dispelled"
const REVOKE_REASON_REPLACED := "replaced"
const REVOKE_REASON_MANUAL := "manual"

## 持有者一侧的订阅策略（grant 时查）：
## - BROADCAST_ALLOWED：默认，ability 想订阅什么广播都行。
## - DIRECT_ONLY：本 set 的 ability 只许收定向投递（`.direct()` 的 trigger）——任一广播订阅（非 direct 的 post trigger、
##   PreEvent）在 grant 时断言且不 grant。给「一个持有者成十上百份」的 actor 用（单位 / 成员 / 子弹），保证广播的
##   登记数不随持有者数涨；条件是回调、处理器不能索引，登记数就是每条事件的派发成本。
enum SubscriptionPolicy { BROADCAST_ALLOWED, DIRECT_ONLY }

var owner_actor_id: String
var subscription_policy := SubscriptionPolicy.BROADCAST_ALLOWED
var _attribute_set: BaseGeneratedAttributeSet = null
var _abilities: Array[Ability] = []
var tag_container: TagContainer
var _on_granted_callbacks: Array[Callable] = []
var _on_revoked_callbacks: Array[Callable] = []

func _init(p_owner_actor_id: String, p_attribute_set: BaseGeneratedAttributeSet = null) -> void:
	owner_actor_id = p_owner_actor_id
	_attribute_set = p_attribute_set
	tag_container = TagContainer.create(owner_actor_id)

## 绑定所属 actor 的 id。owner_actor_id 与 tag_container.owner_id 是同一条真相的两个副本
## （AbilitySet 在 actor 拿到 id 之前就构造好，两处都先揣着空 id），一起换才不会长期漂移。
## tag_container.owner_id 当前没有读者——它是容器的自述身份，不是本方法在修的 bug。
func bind_owner(actor_id: String) -> void:
	owner_actor_id = actor_id
	tag_container.owner_id = actor_id

## owner 所属的 GameplayInstance，每次按 owner_actor_id 反查（owner 未注册时为 null）。
##
## 只存 id、不绑引用：AbilitySet 在 actor 拿到 id 之前就构造，还会被项目层整个换新
## （inkmon reset_battle_runtime 每场重建、构造时只带 id），「绑一次」式的引用会在这类
## 路径上漏绑；强引用更会接成 instance → actor → ability_set → instance 的环。
func get_owner_instance() -> GameplayInstance:
	return GameWorld.get_instance_of_actor(owner_actor_id)

func add_loose_tag(tag: String, stacks: int = 1) -> void:
	tag_container.add_loose_tag(tag, stacks)

func remove_loose_tag(tag: String, stacks: int = -1) -> bool:
	return tag_container.remove_loose_tag(tag, stacks)

func add_auto_duration_tag(tag: String, duration: float) -> void:
	tag_container.add_auto_duration_tag(tag, duration)

func _add_component_tags(ability_id: String, tags: Dictionary) -> void:
	tag_container.add_component_tags(ability_id, tags)

func _remove_component_tags(ability_id: String) -> void:
	tag_container.remove_component_tags(ability_id)

func has_tag(tag: String) -> bool:
	return tag_container.has_tag(tag)

func get_tag_stacks(tag: String) -> int:
	return tag_container.get_tag_stacks(tag)

func get_all_tags() -> Dictionary:
	return tag_container.get_all_tags()

func get_logic_time() -> float:
	return tag_container.get_logic_time()

func has_loose_tag(tag: String) -> bool:
	return tag_container.has_loose_tag(tag)

func get_loose_tag_stacks(tag: String) -> int:
	return tag_container.get_loose_tag_stacks(tag)

## grant 新 ability，随后恒把 ABILITY_GRANTED_EVENT 只寄给刚 grant 的这个实例（EventProcessor.deliver_to_ability），
## 让 TriggerConfig.GRANTED_SELF 等 direct trigger 能响应（典型用途：挂上就自动 tick 的 buff 通过
## ActivateInstanceConfig 自激活 loop timeline）。自不自激活只由 ability 自己声明的 trigger
## 决定，与 grant 的调用点无关。
##
## 只寄给新实例、不广播：同 set 的其它 ability 与别的 actor 都收不到「有人被 grant 了」，要听得由业务层另发 post 事件。
##
## 三条前置：
## - owner 必须已 add_actor 进 instance（post 订阅、pre 注册、context 的 instance 都按 owner id 反查，注册前 grant 会
##   静默缺订阅）——未登记即 assert，不 grant。
## - ability 的 owner 由本 set 盖章：构造时留空即填本 set 的 owner（source 为空时同步补齐），非空则必须与本 set 的
##   owner 相同——不一致时注册派发正常而 for_ability / AbilityRef 反查到别人（tag 撤不掉、execution 拿 null instance），
##   静默半残，所以 assert 不 grant。
## - subscription_policy 为 DIRECT_ONLY 时 ability 不得有任何广播订阅（Ability.broadcast_subscription_kinds 非空即 assert，
##   不 grant）：这是持有者的性质，从哪条路 grant 进来都一样，所以查在这里而不是各调用点。
func grant_ability(ability: Ability) -> void:
	for existing in _abilities:
		if existing.id == ability.id:
			Log.warning("AbilitySet", "Ability already granted: %s" % ability.id)
			return
	var owner_instance := get_owner_instance()
	if owner_instance == null:
		Log.assert_crash(false, "AbilitySet",
			"grant_ability: owner '%s' 未登记进任何 GameplayInstance，先 add_actor 再 grant（ability '%s'）" % [owner_actor_id, ability.config_id])
		return
	if ability.owner_actor_id == "":
		ability.owner_actor_id = owner_actor_id
		if ability.source_actor_id == "":
			ability.source_actor_id = owner_actor_id
	elif ability.owner_actor_id != owner_actor_id:
		Log.assert_crash(false, "AbilitySet",
			"grant_ability: ability '%s' 的 owner '%s' 与本 set 的 owner '%s' 不一致" % [ability.config_id, ability.owner_actor_id, owner_actor_id])
		return
	if subscription_policy == SubscriptionPolicy.DIRECT_ONLY:
		var broadcast_kinds := ability.broadcast_subscription_kinds()
		if not broadcast_kinds.is_empty():
			Log.assert_crash(false, "AbilitySet",
				"grant_ability: owner '%s' 的技能集只收定向投递（DIRECT_ONLY），ability '%s' 订阅了广播 %s——命中 / 激活走 TriggerConfig.direct()，旁观反应归别的持有者" % [owner_actor_id, ability.config_id, broadcast_kinds])
			return
	_abilities.append(ability)
	var context: AbilityLifecycleContext = _create_lifecycle_context(ability, owner_instance)
	ability.apply_effects(context)
	Log.debug("AbilitySet", "获得能力")
	_notify_granted(ability)

	var event_dict := GameEvent.AbilityGranted.create(owner_actor_id, ability.serialize()).to_dict()
	owner_instance.event_processor.deliver_to_ability(event_dict, owner_actor_id, ability.id)

## 单个退场：expire（跑 on_remove）→ 除名 → revoked 广播；不在集里返回 false。
##
## 除名按对象、在 expire 之后现找：on_remove 里可以再 revoke 同集的 ability，进门时的下标到这里可能已经左移
## （指着旁观者，或越过数组尾）。on_remove 里连自己也 revoke 了（按条件批量 revoke 命中自己）时，重入的那次已经
## 除名并广播过，这里找不到就收手，不二次广播；退场已成，仍返回 true。
func revoke_ability(ability_id: String, reason: String = REVOKE_REASON_MANUAL, expire_reason: String = "") -> bool:
	var ability := find_ability_by_id(ability_id)
	if ability == null:
		return false
	var effective_expire_reason := expire_reason if expire_reason != "" else reason
	if not ability.is_expired():
		ability.expire(effective_expire_reason)
	var index := _abilities.find(ability)
	if index == -1:
		return true
	_abilities.remove_at(index)
	var final_expire_reason := ability.get_expire_reason() if ability.get_expire_reason() != "" else effective_expire_reason
	Log.debug("AbilitySet", "失去能力 (%s)" % final_expire_reason)
	_notify_revoked(ability, reason, final_expire_reason)
	return true

## 按条件批量 revoke：predicate(ability) -> bool 命中的每个都走 revoke_ability 的正规退场（expire → 除名 → 广播）。
## 条件由游戏层写（按 config_id / tag / source / 全部……），core 不为任一种条件立专用动词——「只清别人施加的」（驱散）
## 也只是一种 predicate。返回本调用亲手 revoke 的条数。
##
## 先快照命中集合再逐个 revoke：某个命中者的 on_remove 里再 revoke 别的 ability 会让活数组左移、跳过下一个；
## 被这样连带退场的命中者再遇到时 revoke_ability 返回 false，不二次退场、不计数。
func revoke_abilities_where(predicate: Callable, reason: String = REVOKE_REASON_MANUAL) -> int:
	var to_revoke: Array[Ability] = []
	for ability in _abilities:
		if predicate.call(ability):
			to_revoke.append(ability)
	var revoked := 0
	for ability in to_revoke:
		if revoke_ability(ability.id, reason):
			revoked += 1
	return revoked

## 一帧时间推进：tag 容器拨钟、清到期的计时 tag，再让每个 ability 推进自己的计时 component。
## 没有任何 ability 交了推进函数（Ability.needs_tick）就不走那趟遍历——每帧现判、读真实 _abilities，不记计数；
## 那趟对它们本是空转，早退不遍历也就不需要快照。
func tick(dt: float, logic_time: float = -1.0) -> void:
	tag_container.tick(dt, logic_time)
	if not _has_ticking_ability():
		return
	_process_abilities(func(ability: Ability):
		ability.tick(dt)
	)

## 推进在飞的 execution；没有任何 execution 在飞就不进门（那趟遍历只剩快照 / lambda / 各 ability 的 filter 分配）。
## advance_and_is_acting 自己先扫过一遍（顺便算 is_acting）；直接调本方法的循环（dota2 / scenario harness）靠这里的判断。
func tick_executions(dt: float) -> Array[String]:
	if not has_executing_instances():
		return []
	var all_triggered: Array[String] = []
	_process_abilities(func(ability: Ability):
		var triggered := ability.tick_executions(dt)
		all_triggered.append_array(triggered)
	)
	return all_triggered

## 推进一帧 ability runtime 并回答「是否正在行动」：tick → 算 is_acting → tick_executions；
## 返回本帧是否有算行动的 execution 在飞（哪些 execution 算行动由 _is_acting_execution 定）。
##
## is_acting 必须在 tick_executions **之前**算：本帧内跑完的 execution 也算占用了这一帧，
## 战斗主循环据此决定「施法期间 ATB 冻结」；先推进再问，刚结束的那帧会被误判成空闲，
## 角色一帧内既施法又充能。
func advance_and_is_acting(dt: float, logic_time: float) -> bool:
	tick(dt, logic_time)
	var has_any_execution := false
	var acting := false
	# 一趟同时算两个答案：本方法每 actor 每 tick 都跑，分两趟遍历纯属白走。
	for ability in _abilities:
		if not ability.has_executing_instance():
			continue
		has_any_execution = true
		if _is_acting_execution(ability):
			acting = true
			break
	if has_any_execution:
		tick_executions(dt)
	return acting

## 是否有任一 ability 处于执行中（不区分是否阻塞）。
func has_executing_instances() -> bool:
	for ability in _abilities:
		if ability.has_executing_instance():
			return true
	return false

## 是否有任一 ability 交了推进函数（每帧现判，不记计数）。
func _has_ticking_ability() -> bool:
	for ability in _abilities:
		if ability.needs_tick():
			return true
	return false

## 执行中的 ability 算不算「行动」（在飞期间持有者视为正在行动，战斗主循环据此冻结 ATB）。
## 默认全算；项目子类按自己的规则覆盖（hex 只认 active / action 标签，inkmon 豁免 intrinsic）。
func _is_acting_execution(_ability: Ability) -> bool:
	return true

## 激活门的纯查询干跑（零副作用、可重入）：UI / AI / tooltip 三源共用的合法性
## Query 入口。context 与真实激活（EventProcessor.deliver_to_ability 按 owner 反查重建）落在同一个 actor / instance 上，
## Condition/Cost 在"查询"与"真实激活"两条路径读到的是同一个世界。
##
## event_dict 是透传给 Condition.check / Cost.can_pay 的拟真输入（如带
## target_actor_id 的预设目标语境）；无目标语境传 {}。返回形状见
## AbilityActivationQuery：{allowed, reason, failed_component_type}。
##
## ability 必须属于本 AbilitySet——跨 set 查询构造出的 context 会谎报 owner，
## 属调用方编程错误，直接 crash 而非静默给出错误答案。
func can_activate(
	ability: Ability,
	event_dict: Dictionary = {},
) -> Dictionary:
	# 断言在 debug 下不阻断调用方：每条断言之后都返回 denied，不对 null / 别家 ability 继续干跑。
	if ability == null:
		Log.assert_crash(false, "AbilitySet", "can_activate 要求非空 ability")
		return AbilityActivationQuery.denied("ability is null", AbilityActivationQuery.FAILED_ABILITY)
	if not _abilities.has(ability):
		Log.assert_crash(false, "AbilitySet",
			"can_activate: ability '%s' 不属于本 AbilitySet (owner=%s)" % [ability.id, owner_actor_id])
		return AbilityActivationQuery.denied(
			"ability '%s' is not in this set" % ability.id, AbilityActivationQuery.FAILED_ABILITY)
	var context: AbilityLifecycleContext = _create_lifecycle_context(ability, get_owner_instance())
	return ability.can_activate(context, event_dict)

func get_abilities() -> Array[Ability]:
	return _abilities

func find_ability_by_id(ability_id: String) -> Ability:
	for ability in _abilities:
		if ability.id == ability_id:
			return ability
	return null

func find_ability_by_config_id(config_id: String) -> Ability:
	for ability in _abilities:
		if ability.config_id == config_id:
			return ability
	return null

func find_abilities_by_config_id(config_id: String) -> Array[Ability]:
	var results: Array[Ability] = []
	for ability in _abilities:
		if ability.config_id == config_id:
			results.append(ability)
	return results

func find_abilities_by_ability_tag(tag: String) -> Array[Ability]:
	var results: Array[Ability] = []
	for ability in _abilities:
		if ability.has_ability_tag(tag):
			results.append(ability)
	return results

func has_ability(config_id: String) -> bool:
	for ability in _abilities:
		if ability.config_id == config_id:
			return true
	return false

func get_ability_count() -> int:
	return _abilities.size()

func on_ability_granted(callback: Callable) -> Callable:
	return _add_listener(_on_granted_callbacks, callback)

func on_ability_revoked(callback: Callable) -> Callable:
	return _add_listener(_on_revoked_callbacks, callback)

func serialize() -> Dictionary:
	var abilities: Array[Dictionary] = []
	for ability in _abilities:
		abilities.append(ability.serialize())
	return {
		"owner_actor_id": owner_actor_id,
		"abilities": abilities,
	}

func _create_lifecycle_context(ability: Ability, owner_instance: GameplayInstance) -> AbilityLifecycleContext:
	return AbilityLifecycleContext.new(
		owner_actor_id,
		_attribute_set,
		ability,
		self,
		owner_instance
	)

func _process_abilities(processor: Callable) -> void:
	var expired := []
	# 遍历快照：processor 里的 revoke（如护盾破裂即时移除）会让活数组左移、跳过下一个 ability。
	for ability in _abilities.duplicate():
		if ability.is_expired():
			expired.append(ability)
			continue
		processor.call(ability)
		if ability.is_expired():
			expired.append(ability)
	for ability in expired:
		revoke_ability(ability.id, REVOKE_REASON_EXPIRED, ability.get_expire_reason())

func _notify_granted(ability: Ability) -> void:
	for callback in _on_granted_callbacks:
		if callback.is_valid():
			callback.call(ability, self)
		else:
			Log.error("AbilitySet", "Error in ability granted callback")

func _notify_revoked(ability: Ability, reason: String, expire_reason: String) -> void:
	for callback in _on_revoked_callbacks:
		if callback.is_valid():
			callback.call(ability, reason, self, expire_reason)
		else:
			Log.error("AbilitySet", "Error in ability revoked callback")

static func create(p_owner_actor_id: String, p_attribute_set: BaseGeneratedAttributeSet = null) -> AbilitySet:
	return AbilitySet.new(p_owner_actor_id, p_attribute_set)

func _add_listener(list: Array[Callable], callback: Callable) -> Callable:
	list.append(callback)
	return func() -> void:
		var index := list.find(callback)
		if index != -1:
			list.remove_at(index)
