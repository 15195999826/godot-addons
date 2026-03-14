class_name HexBattlePreEvents
## Hex ATB 战斗的 Pre 阶段事件定义
##
## Pre 事件在效果应用之前触发，允许被动技能修改或取消即将发生的效果。
## 这些事件是 hex-atb-battle 示例项目特有的，不属于框架核心。

# Pre 阶段事件常量
const PRE_DAMAGE_EVENT := "pre_damage"
const PRE_HEAL_EVENT := "pre_heal"


# ========== Pre 阶段事件基类 ==========
## Pre 阶段事件的基类，包含所有 Pre 事件的通用字段。
## 所有 Pre 事件都必须包含 source_actor_id 和 target_actor_id。

class PreExecuteEvent extends GameEvent.Base:
	## 效果来源的 Actor ID（可为空字符串，表示无来源）
	var source_actor_id: String = ""
	## 效果目标的 Actor ID（必须）
	var target_actor_id: String = ""

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"source_actor_id": source_actor_id,
			"target_actor_id": target_actor_id,
		}

	static func from_dict_base(e: PreExecuteEvent, d: Dictionary) -> void:
		e.source_actor_id = d.get("source_actor_id", "")
		e.target_actor_id = d.get("target_actor_id", "")


# ========== Pre 阶段具体事件 ==========

## 伤害前事件，在伤害应用之前触发。
## 允许被动技能修改伤害值、伤害类型，或完全取消伤害。
class PreDamageEvent extends PreExecuteEvent:
	## 原始伤害值
	var damage: float = 0.0
	## 伤害类型（physical, magical, pure）
	var damage_type: String = "physical"

	func _init() -> void:
		kind = PRE_DAMAGE_EVENT

	static func create(
		p_source_actor_id: String,
		p_target_actor_id: String,
		p_damage: float,
		p_damage_type: String = "physical"
	) -> PreDamageEvent:
		var e := PreDamageEvent.new()
		e.source_actor_id = p_source_actor_id
		e.target_actor_id = p_target_actor_id
		e.damage = p_damage
		e.damage_type = p_damage_type
		return e

	func to_dict() -> Dictionary:
		var d := super.to_dict()
		d["damage"] = damage
		d["damage_type"] = damage_type
		return d

	static func from_dict(d: Dictionary) -> PreDamageEvent:
		var e := PreDamageEvent.new()
		PreExecuteEvent.from_dict_base(e, d)
		e.damage = d.get("damage", 0.0)
		e.damage_type = d.get("damage_type", "physical")
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == PRE_DAMAGE_EVENT


## 治疗前事件，在治疗应用之前触发。
## 允许被动技能修改治疗量，或完全取消治疗。
class PreHealEvent extends PreExecuteEvent:
	## 原始治疗量
	var heal_amount: float = 0.0

	func _init() -> void:
		kind = PRE_HEAL_EVENT

	static func create(
		p_source_actor_id: String,
		p_target_actor_id: String,
		p_heal_amount: float
	) -> PreHealEvent:
		var e := PreHealEvent.new()
		e.source_actor_id = p_source_actor_id
		e.target_actor_id = p_target_actor_id
		e.heal_amount = p_heal_amount
		return e

	func to_dict() -> Dictionary:
		var d := super.to_dict()
		d["heal_amount"] = heal_amount
		return d

	static func from_dict(d: Dictionary) -> PreHealEvent:
		var e := PreHealEvent.new()
		PreExecuteEvent.from_dict_base(e, d)
		e.heal_amount = d.get("heal_amount", 0.0)
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == PRE_HEAL_EVENT
