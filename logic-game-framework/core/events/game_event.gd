class_name GameEvent
extends RefCounted

const ABILITY_ACTIVATE_EVENT := "abilityActivate"
const ABILITY_ACTIVATE_FAILED_EVENT := "abilityActivateFailed"
const ACTOR_SPAWNED_EVENT := "actorSpawned"
const ACTOR_DESTROYED_EVENT := "actorDestroyed"
const ATTRIBUTE_CHANGED_EVENT := "attributeChanged"
const ABILITY_GRANTED_EVENT := "abilityGranted"
const ABILITY_REMOVED_EVENT := "abilityRemoved"
const ABILITY_ACTIVATED_EVENT := "abilityActivated"
const ABILITY_TRIGGERED_EVENT := "abilityTriggered"
const ABILITY_STACKS_CHANGED_EVENT := "abilityStacksChanged"
const EXECUTION_ACTIVATED_EVENT := "executionActivated"
const TAG_CHANGED_EVENT := "tagChanged"
const STAGE_CUE_EVENT := "stageCue"


# ========== 事件基类 ==========

class Base:
	var kind: String = ""
	
	func to_dict() -> Dictionary:
		return { "kind": kind }
	
	static func is_match(_d: Dictionary) -> bool:
		return false  # 子类覆盖


# ========== 强类型事件类 ==========

class ActorSpawned extends Base:
	var actor_id: String = ""
	var actor_data: Dictionary = {}
	
	func _init() -> void:
		kind = ACTOR_SPAWNED_EVENT
	
	static func create(p_actor_id: String, p_actor_data: Dictionary) -> ActorSpawned:
		var e := ActorSpawned.new()
		e.actor_id = p_actor_id
		e.actor_data = p_actor_data
		return e
	
	func to_dict() -> Dictionary:
		return { "kind": kind, "actorId": actor_id, "actor": actor_data }
	
	static func from_dict(d: Dictionary) -> ActorSpawned:
		var e := ActorSpawned.new()
		e.actor_id = d.get("actorId", "")
		e.actor_data = d.get("actor", {})
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ACTOR_SPAWNED_EVENT


class ActorDestroyed extends Base:
	var actor_id: String = ""
	var reason: String = ""
	
	func _init() -> void:
		kind = ACTOR_DESTROYED_EVENT
	
	static func create(p_actor_id: String, p_reason: String = "") -> ActorDestroyed:
		var e := ActorDestroyed.new()
		e.actor_id = p_actor_id
		e.reason = p_reason
		return e
	
	func to_dict() -> Dictionary:
		var d := { "kind": kind, "actorId": actor_id }
		if reason != "":
			d["reason"] = reason
		return d
	
	static func from_dict(d: Dictionary) -> ActorDestroyed:
		var e := ActorDestroyed.new()
		e.actor_id = d.get("actorId", "")
		e.reason = d.get("reason", "")
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ACTOR_DESTROYED_EVENT


class AttributeChanged extends Base:
	var actor_id: String = ""
	var attribute: String = ""
	var old_value: float = 0.0
	var new_value: float = 0.0
	var source: Dictionary = {}
	
	func _init() -> void:
		kind = ATTRIBUTE_CHANGED_EVENT
	
	static func create(p_actor_id: String, p_attribute: String, p_old_value: float, p_new_value: float, p_source: Dictionary = {}) -> AttributeChanged:
		var e := AttributeChanged.new()
		e.actor_id = p_actor_id
		e.attribute = p_attribute
		e.old_value = p_old_value
		e.new_value = p_new_value
		e.source = p_source
		return e
	
	func to_dict() -> Dictionary:
		var d := { "kind": kind, "actorId": actor_id, "attribute": attribute, "oldValue": old_value, "newValue": new_value }
		if not source.is_empty():
			d["source"] = source
		return d
	
	static func from_dict(d: Dictionary) -> AttributeChanged:
		var e := AttributeChanged.new()
		e.actor_id = d.get("actorId", "")
		e.attribute = d.get("attribute", "")
		e.old_value = d.get("oldValue", 0.0)
		e.new_value = d.get("newValue", 0.0)
		e.source = d.get("source", {})
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ATTRIBUTE_CHANGED_EVENT


class AbilityGranted extends Base:
	var actor_id: String = ""
	var ability: Dictionary = {}
	
	func _init() -> void:
		kind = ABILITY_GRANTED_EVENT
	
	static func create(p_actor_id: String, p_ability: Dictionary) -> AbilityGranted:
		var e := AbilityGranted.new()
		e.actor_id = p_actor_id
		e.ability = p_ability
		return e
	
	func to_dict() -> Dictionary:
		return { "kind": kind, "actorId": actor_id, "ability": ability }
	
	static func from_dict(d: Dictionary) -> AbilityGranted:
		var e := AbilityGranted.new()
		e.actor_id = d.get("actorId", "")
		e.ability = d.get("ability", {})
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ABILITY_GRANTED_EVENT


class AbilityRemoved extends Base:
	var actor_id: String = ""
	var ability_instance_id: String = ""
	
	func _init() -> void:
		kind = ABILITY_REMOVED_EVENT
	
	static func create(p_actor_id: String, p_ability_instance_id: String) -> AbilityRemoved:
		var e := AbilityRemoved.new()
		e.actor_id = p_actor_id
		e.ability_instance_id = p_ability_instance_id
		return e
	
	func to_dict() -> Dictionary:
		return { "kind": kind, "actorId": actor_id, "abilityInstanceId": ability_instance_id }
	
	static func from_dict(d: Dictionary) -> AbilityRemoved:
		var e := AbilityRemoved.new()
		e.actor_id = d.get("actorId", "")
		e.ability_instance_id = d.get("abilityInstanceId", "")
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ABILITY_REMOVED_EVENT


## ability.stacks 变化时由业务方主动 emit(core 不在 add_stacks/remove_stacks 里耦合)。
## 首个消费者:PoisonTickAction 每轮 tick 减一层后 emit。
## frontend BuffVisualizer 用它更新 BuffSummary.primary。
class AbilityStacksChanged extends Base:
	var actor_id: String = ""
	var ability_instance_id: String = ""
	var ability_config_id: String = ""
	var old_stacks: int = 0
	var new_stacks: int = 0

	func _init() -> void:
		kind = ABILITY_STACKS_CHANGED_EVENT

	static func create(p_actor_id: String, p_ability_instance_id: String, p_ability_config_id: String, p_old_stacks: int, p_new_stacks: int) -> AbilityStacksChanged:
		var e := AbilityStacksChanged.new()
		e.actor_id = p_actor_id
		e.ability_instance_id = p_ability_instance_id
		e.ability_config_id = p_ability_config_id
		e.old_stacks = p_old_stacks
		e.new_stacks = p_new_stacks
		return e

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"actorId": actor_id,
			"abilityInstanceId": ability_instance_id,
			"abilityConfigId": ability_config_id,
			"oldStacks": old_stacks,
			"newStacks": new_stacks,
		}

	static func from_dict(d: Dictionary) -> AbilityStacksChanged:
		var e := AbilityStacksChanged.new()
		e.actor_id = d.get("actorId", "")
		e.ability_instance_id = d.get("abilityInstanceId", "")
		e.ability_config_id = d.get("abilityConfigId", "")
		e.old_stacks = d.get("oldStacks", 0)
		e.new_stacks = d.get("newStacks", 0)
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ABILITY_STACKS_CHANGED_EVENT


class AbilityActivated extends Base:
	var actor_id: String = ""
	var ability_instance_id: String = ""
	var ability_config_id: String = ""
	var target: Dictionary = {}
	
	func _init() -> void:
		kind = ABILITY_ACTIVATED_EVENT
	
	static func create(p_actor_id: String, p_ability_instance_id: String, p_ability_config_id: String, p_target: Dictionary = {}) -> AbilityActivated:
		var e := AbilityActivated.new()
		e.actor_id = p_actor_id
		e.ability_instance_id = p_ability_instance_id
		e.ability_config_id = p_ability_config_id
		e.target = p_target
		return e
	
	func to_dict() -> Dictionary:
		var d := { "kind": kind, "actorId": actor_id, "abilityInstanceId": ability_instance_id, "abilityConfigId": ability_config_id }
		if not target.is_empty():
			d["target"] = target
		return d
	
	static func from_dict(d: Dictionary) -> AbilityActivated:
		var e := AbilityActivated.new()
		e.actor_id = d.get("actorId", "")
		e.ability_instance_id = d.get("abilityInstanceId", "")
		e.ability_config_id = d.get("abilityConfigId", "")
		e.target = d.get("target", {})
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ABILITY_ACTIVATED_EVENT


class AbilityTriggered extends Base:
	var actor_id: String = ""
	var ability_instance_id: String = ""
	var ability_config_id: String = ""
	var trigger_event_kind: String = ""
	var triggered_components: Array[String] = []
	
	func _init() -> void:
		kind = ABILITY_TRIGGERED_EVENT
	
	static func create(p_actor_id: String, p_ability_instance_id: String, p_ability_config_id: String, p_trigger_event_kind: String, p_triggered_components: Array[String]) -> AbilityTriggered:
		var e := AbilityTriggered.new()
		e.actor_id = p_actor_id
		e.ability_instance_id = p_ability_instance_id
		e.ability_config_id = p_ability_config_id
		e.trigger_event_kind = p_trigger_event_kind
		e.triggered_components = p_triggered_components.duplicate()
		return e
	
	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"actorId": actor_id,
			"abilityInstanceId": ability_instance_id,
			"abilityConfigId": ability_config_id,
			"triggerEventKind": trigger_event_kind,
			"triggeredComponents": triggered_components.duplicate(),
		}
	
	static func from_dict(d: Dictionary) -> AbilityTriggered:
		var e := AbilityTriggered.new()
		e.actor_id = d.get("actorId", "")
		e.ability_instance_id = d.get("abilityInstanceId", "")
		e.ability_config_id = d.get("abilityConfigId", "")
		e.trigger_event_kind = d.get("triggerEventKind", "")
		e.triggered_components = d.get("triggeredComponents", []).duplicate()
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ABILITY_TRIGGERED_EVENT


class ExecutionActivated extends Base:
	var actor_id: String = ""
	var ability_instance_id: String = ""
	var ability_config_id: String = ""
	var execution_id: String = ""
	var timeline_id: String = ""
	
	func _init() -> void:
		kind = EXECUTION_ACTIVATED_EVENT
	
	static func create(p_actor_id: String, p_ability_instance_id: String, p_ability_config_id: String, p_execution_id: String, p_timeline_id: String) -> ExecutionActivated:
		var e := ExecutionActivated.new()
		e.actor_id = p_actor_id
		e.ability_instance_id = p_ability_instance_id
		e.ability_config_id = p_ability_config_id
		e.execution_id = p_execution_id
		e.timeline_id = p_timeline_id
		return e
	
	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"actorId": actor_id,
			"abilityInstanceId": ability_instance_id,
			"abilityConfigId": ability_config_id,
			"executionId": execution_id,
			"timelineId": timeline_id,
		}
	
	static func from_dict(d: Dictionary) -> ExecutionActivated:
		var e := ExecutionActivated.new()
		e.actor_id = d.get("actorId", "")
		e.ability_instance_id = d.get("abilityInstanceId", "")
		e.ability_config_id = d.get("abilityConfigId", "")
		e.execution_id = d.get("executionId", "")
		e.timeline_id = d.get("timelineId", "")
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == EXECUTION_ACTIVATED_EVENT


class TagChanged extends Base:
	var actor_id: String = ""
	var tag: String = ""
	var old_count: int = 0
	var new_count: int = 0
	
	func _init() -> void:
		kind = TAG_CHANGED_EVENT
	
	static func create(p_actor_id: String, p_tag: String, p_old_count: int, p_new_count: int) -> TagChanged:
		var e := TagChanged.new()
		e.actor_id = p_actor_id
		e.tag = p_tag
		e.old_count = p_old_count
		e.new_count = p_new_count
		return e
	
	func to_dict() -> Dictionary:
		return { "kind": kind, "actorId": actor_id, "tag": tag, "oldCount": old_count, "newCount": new_count }
	
	static func from_dict(d: Dictionary) -> TagChanged:
		var e := TagChanged.new()
		e.actor_id = d.get("actorId", "")
		e.tag = d.get("tag", "")
		e.old_count = d.get("oldCount", 0)
		e.new_count = d.get("newCount", 0)
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == TAG_CHANGED_EVENT


class StageCue extends Base:
	var source_actor_id: String = ""
	var target_actor_ids: Array[String] = []
	var cue_id: String = ""
	var params: Dictionary = {}
	
	func _init() -> void:
		kind = STAGE_CUE_EVENT
	
	static func create(p_source_actor_id: String, p_target_actor_ids: Array[String], p_cue_id: String, p_params: Dictionary = {}) -> StageCue:
		var e := StageCue.new()
		e.source_actor_id = p_source_actor_id
		e.target_actor_ids = p_target_actor_ids.duplicate()
		e.cue_id = p_cue_id
		e.params = p_params
		return e
	
	func to_dict() -> Dictionary:
		var d := { "kind": kind, "sourceActorId": source_actor_id, "targetActorIds": target_actor_ids.duplicate(), "cueId": cue_id }
		if not params.is_empty():
			d["params"] = params
		return d
	
	static func from_dict(d: Dictionary) -> StageCue:
		var e := StageCue.new()
		e.source_actor_id = d.get("sourceActorId", "")
		e.target_actor_ids = d.get("targetActorIds", []).duplicate()
		e.cue_id = d.get("cueId", "")
		e.params = d.get("params", {})
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == STAGE_CUE_EVENT


class ProjectileHit extends Base:
	var projectile_id: String = ""
	var source_actor_id: String = ""
	var target_actor_id: String = ""
	var ability_config_id: String = ""
	var hit_position: Vector3 = Vector3.ZERO
	var fly_time: float = 0.0
	var fly_distance: float = 0.0
	
	func _init() -> void:
		kind = ProjectileEvents.PROJECTILE_HIT_EVENT
	
	static func create(p_projectile_id: String, p_source_actor_id: String, p_target_actor_id: String, p_hit_position: Vector3, p_fly_time: float, p_fly_distance: float, p_ability_config_id: String = "") -> ProjectileHit:
		var e := ProjectileHit.new()
		e.projectile_id = p_projectile_id
		e.source_actor_id = p_source_actor_id
		e.target_actor_id = p_target_actor_id
		e.hit_position = p_hit_position
		e.fly_time = p_fly_time
		e.fly_distance = p_fly_distance
		e.ability_config_id = p_ability_config_id
		return e
	
	func to_dict() -> Dictionary:
		var d := {
			"kind": kind,
			"projectileId": projectile_id,
			"source_actor_id": source_actor_id,
			"target_actor_id": target_actor_id,
			"hitPosition": hit_position,
			"flyTime": fly_time,
			"flyDistance": fly_distance,
		}
		if ability_config_id != "":
			d["ability_config_id"] = ability_config_id
		return d
	
	static func from_dict(d: Dictionary) -> ProjectileHit:
		var e := ProjectileHit.new()
		e.projectile_id = d.get("projectileId", "")
		e.source_actor_id = d.get("source_actor_id", "")
		e.target_actor_id = d.get("target_actor_id", "")
		e.ability_config_id = d.get("ability_config_id", "")
		e.hit_position = d.get("hitPosition", Vector3.ZERO)
		e.fly_time = d.get("flyTime", 0.0)
		e.fly_distance = d.get("flyDistance", 0.0)
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind", "") == ProjectileEvents.PROJECTILE_HIT_EVENT


class AbilityActivate extends Base:
	var ability_instance_id: String = ""
	var source_id: String = ""
	
	func _init() -> void:
		kind = ABILITY_ACTIVATE_EVENT
	
	static func create(p_ability_instance_id: String, p_source_id: String) -> AbilityActivate:
		var e := AbilityActivate.new()
		e.ability_instance_id = p_ability_instance_id
		e.source_id = p_source_id
		return e
	
	func to_dict() -> Dictionary:
		return { "kind": kind, "abilityInstanceId": ability_instance_id, "sourceId": source_id }
	
	static func from_dict(d: Dictionary) -> AbilityActivate:
		var e := AbilityActivate.new()
		e.ability_instance_id = d.get("abilityInstanceId", "")
		e.source_id = d.get("sourceId", "")
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ABILITY_ACTIVATE_EVENT


## ActiveUseComponent 的 condition / cost 检查失败时 push。
##
## 语义边界: 失败事件只代表"已经匹配到 trigger 的 ability 在 condition/cost
## 阶段被拒绝"。triggers 没匹配上(skill 不该响应这个 event)不 push 失败事件
## —— 那是正常 silent skip, 不是失败。
##
## reason: 失败的 condition.get_fail_reason / cost.get_fail_reason 字符串,
## 由 example 层填充语义 (LGF core 不知道"冷却"/"mp 不足", 只搬运字符串)。
## failed_component_type: "condition" / "cost", 让前端区分图标。
class AbilityActivateFailed extends Base:
	var ability_instance_id: String = ""
	var ability_config_id: String = ""
	var source_id: String = ""
	var target_actor_id: String = ""
	var reason: String = ""
	var failed_component_type: String = ""

	func _init() -> void:
		kind = ABILITY_ACTIVATE_FAILED_EVENT

	static func create(
		p_ability_instance_id: String,
		p_ability_config_id: String,
		p_source_id: String,
		p_target_actor_id: String,
		p_reason: String,
		p_failed_component_type: String,
	) -> AbilityActivateFailed:
		var e := AbilityActivateFailed.new()
		e.ability_instance_id = p_ability_instance_id
		e.ability_config_id = p_ability_config_id
		e.source_id = p_source_id
		e.target_actor_id = p_target_actor_id
		e.reason = p_reason
		e.failed_component_type = p_failed_component_type
		return e

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"abilityInstanceId": ability_instance_id,
			"abilityConfigId": ability_config_id,
			"sourceId": source_id,
			"targetActorId": target_actor_id,
			"reason": reason,
			"failedComponentType": failed_component_type,
		}

	static func from_dict(d: Dictionary) -> AbilityActivateFailed:
		var e := AbilityActivateFailed.new()
		e.ability_instance_id = d.get("abilityInstanceId", "")
		e.ability_config_id = d.get("abilityConfigId", "")
		e.source_id = d.get("sourceId", "")
		e.target_actor_id = d.get("targetActorId", "")
		e.reason = d.get("reason", "")
		e.failed_component_type = d.get("failedComponentType", "")
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == ABILITY_ACTIVATE_FAILED_EVENT

