class_name AbilitySet
extends RefCounted

const REVOKE_REASON_EXPIRED := "expired"
const REVOKE_REASON_DISPELLED := "dispelled"
const REVOKE_REASON_REPLACED := "replaced"
const REVOKE_REASON_MANUAL := "manual"

var owner_actor_id: String
var _attribute_set: BaseGeneratedAttributeSet = null
var _abilities: Array[Ability] = []
var tag_container: TagContainer
var _on_granted_callbacks: Array[Callable] = []
var _on_revoked_callbacks: Array[Callable] = []

func _init(p_owner_actor_id: String, p_attribute_set: BaseGeneratedAttributeSet = null) -> void:
	owner_actor_id = p_owner_actor_id
	_attribute_set = p_attribute_set
	tag_container = TagContainer.create(owner_actor_id)

func get_event_processor() -> EventProcessor:
	return GameWorld.event_processor

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

func grant_ability(ability: Ability) -> void:
	for existing in _abilities:
		if existing.id == ability.id:
			Log.warning("AbilitySet", "Ability already granted: %s" % ability.id)
			return
	_abilities.append(ability)
	var context: AbilityLifecycleContext = _create_lifecycle_context(ability)
	ability.apply_effects(context)
	Log.debug("AbilitySet", "获得能力")
	_notify_granted(ability)

func revoke_ability(ability_id: String, reason: String = REVOKE_REASON_MANUAL, expire_reason: String = "") -> bool:
	var index := -1
	for i in range(_abilities.size()):
		if _abilities[i].id == ability_id:
			index = i
			break
	if index == -1:
		return false
	var ability := _abilities[index]
	var effective_expire_reason := expire_reason if expire_reason != "" else reason
	if not ability.is_expired():
		ability.expire(effective_expire_reason)
	_abilities.remove_at(index)
	var final_expire_reason := ability.get_expire_reason() if ability.get_expire_reason() != "" else effective_expire_reason
	Log.debug("AbilitySet", "失去能力 (%s)" % final_expire_reason)
	_notify_revoked(ability, reason, final_expire_reason)
	return true

func revoke_abilities_by_config_id(config_id: String, reason: String = REVOKE_REASON_MANUAL) -> int:
	var to_revoke: Array[Ability] = []
	for ability in _abilities:
		if ability.config_id == config_id:
			to_revoke.append(ability)
	for ability in to_revoke:
		revoke_ability(ability.id, reason)
	return to_revoke.size()

func revoke_abilities_by_ability_tag(tag: String, reason: String = REVOKE_REASON_MANUAL) -> int:
	var to_revoke: Array[Ability] = []
	for ability in _abilities:
		if ability.has_ability_tag(tag):
			to_revoke.append(ability)
	for ability in to_revoke:
		revoke_ability(ability.id, reason)
	return to_revoke.size()

func tick(dt: float, logic_time: float = -1.0) -> void:
	tag_container.tick(dt, logic_time)
	_process_abilities(func(ability: Ability):
		ability.tick(dt)
	)

func tick_executions(dt: float, game_state_provider: Variant) -> Array[String]:
	var all_triggered: Array[String] = []
	_process_abilities(func(ability: Ability):
		var triggered := ability.tick_executions(dt, game_state_provider)
		all_triggered.append_array(triggered)
	)
	return all_triggered

func receive_event(event_dict: Dictionary, game_state_provider: Variant) -> void:
	_process_abilities(func(ability: Ability):
		var context: AbilityLifecycleContext = _create_lifecycle_context(ability)
		ability.receive_event(event_dict, context, game_state_provider)
	)

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

func _create_lifecycle_context(ability: Ability) -> AbilityLifecycleContext:
	return AbilityLifecycleContext.new(
		owner_actor_id,
		_attribute_set,
		ability,
		self,
		get_event_processor()
	)

func _process_abilities(processor: Callable) -> void:
	var expired := []
	for ability in _abilities:
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
