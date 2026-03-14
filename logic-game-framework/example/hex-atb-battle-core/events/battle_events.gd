## Battle Events - 战斗事件类型定义
##
## 定义 hex-atb-battle 项目特有的战斗事件类型。
## 这些事件由各 Action 产生，记录到回放时间线中。
##
## 命名约定:
## - 事件使用过去时态命名（表示"已发生的事实"）
## - Actor 引用使用 actor_id: String
## - 坐标使用 Dictionary { "q": int, "r": int }
class_name BattleEvents


# ========== 枚举 ==========

enum DamageType { PHYSICAL, MAGICAL, PURE }


# ========== DamageEvent ==========

class DamageEvent extends GameEvent.Base:
	var target_actor_id: String = ""
	var damage: float = 0.0
	var damage_type: DamageType = DamageType.PHYSICAL
	var source_actor_id: String = ""
	var is_critical: bool = false
	var is_reflected: bool = false
	
	func _init() -> void:
		kind = "damage"
	
	static func create(
		p_target_actor_id: String,
		p_damage: float,
		p_damage_type: DamageType = DamageType.PHYSICAL,
		p_source_actor_id: String = "",
		p_is_critical: bool = false,
		p_is_reflected: bool = false
	) -> DamageEvent:
		var e := DamageEvent.new()
		e.target_actor_id = p_target_actor_id
		e.damage = p_damage
		e.damage_type = p_damage_type
		e.source_actor_id = p_source_actor_id
		e.is_critical = p_is_critical
		e.is_reflected = p_is_reflected
		return e
	
	func to_dict() -> Dictionary:
		var d := {
			"kind": kind,
			"target_actor_id": target_actor_id,
			"damage": damage,
			"damage_type": BattleEvents._damage_type_to_string(damage_type),
			"is_critical": is_critical,
			"is_reflected": is_reflected,
		}
		if source_actor_id != "":
			d["source_actor_id"] = source_actor_id
		return d
	
	static func from_dict(d: Dictionary) -> DamageEvent:
		var e := DamageEvent.new()
		e.target_actor_id = d.get("target_actor_id", "") as String
		e.damage = d.get("damage", 0.0) as float
		e.damage_type = BattleEvents.string_to_damage_type(d.get("damage_type", "physical") as String)
		e.source_actor_id = d.get("source_actor_id", "") as String
		e.is_critical = d.get("is_critical", false) as bool
		e.is_reflected = d.get("is_reflected", false) as bool
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "damage"


# ========== HealEvent ==========

class HealEvent extends GameEvent.Base:
	var target_actor_id: String = ""
	var heal_amount: float = 0.0
	var source_actor_id: String = ""
	
	func _init() -> void:
		kind = "heal"
	
	static func create(p_target_actor_id: String, p_heal_amount: float, p_source_actor_id: String = "") -> HealEvent:
		var e := HealEvent.new()
		e.target_actor_id = p_target_actor_id
		e.heal_amount = p_heal_amount
		e.source_actor_id = p_source_actor_id
		return e
	
	func to_dict() -> Dictionary:
		var d := { "kind": kind, "target_actor_id": target_actor_id, "heal_amount": heal_amount }
		if source_actor_id != "":
			d["source_actor_id"] = source_actor_id
		return d
	
	static func from_dict(d: Dictionary) -> HealEvent:
		var e := HealEvent.new()
		e.target_actor_id = d.get("target_actor_id", "") as String
		e.heal_amount = d.get("heal_amount", 0.0) as float
		e.source_actor_id = d.get("source_actor_id", "") as String
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "heal"


# ========== MoveStartEvent ==========

class MoveStartEvent extends GameEvent.Base:
	var actor_id: String = ""
	var from_hex: Dictionary = {}  # { "q": int, "r": int }
	var to_hex: Dictionary = {}
	
	func _init() -> void:
		kind = "move_start"
	
	static func create(p_actor_id: String, p_from_hex: Dictionary, p_to_hex: Dictionary) -> MoveStartEvent:
		var e := MoveStartEvent.new()
		e.actor_id = p_actor_id
		e.from_hex = p_from_hex
		e.to_hex = p_to_hex
		return e
	
	func to_dict() -> Dictionary:
		return { "kind": kind, "actor_id": actor_id, "from_hex": from_hex, "to_hex": to_hex }
	
	static func from_dict(d: Dictionary) -> MoveStartEvent:
		var e := MoveStartEvent.new()
		e.actor_id = d.get("actor_id", "") as String
		e.from_hex = d.get("from_hex", {}) as Dictionary
		e.to_hex = d.get("to_hex", {}) as Dictionary
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "move_start"


# ========== MoveCompleteEvent ==========

class MoveCompleteEvent extends GameEvent.Base:
	var actor_id: String = ""
	var from_hex: Dictionary = {}
	var to_hex: Dictionary = {}
	
	func _init() -> void:
		kind = "move_complete"
	
	static func create(p_actor_id: String, p_from_hex: Dictionary, p_to_hex: Dictionary) -> MoveCompleteEvent:
		var e := MoveCompleteEvent.new()
		e.actor_id = p_actor_id
		e.from_hex = p_from_hex
		e.to_hex = p_to_hex
		return e
	
	func to_dict() -> Dictionary:
		return { "kind": kind, "actor_id": actor_id, "from_hex": from_hex, "to_hex": to_hex }
	
	static func from_dict(d: Dictionary) -> MoveCompleteEvent:
		var e := MoveCompleteEvent.new()
		e.actor_id = d.get("actor_id", "") as String
		e.from_hex = d.get("from_hex", {}) as Dictionary
		e.to_hex = d.get("to_hex", {}) as Dictionary
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "move_complete"


# ========== DeathEvent ==========

class DeathEvent extends GameEvent.Base:
	var actor_id: String = ""
	var killer_actor_id: String = ""
	
	func _init() -> void:
		kind = "death"
	
	static func create(p_actor_id: String, p_killer_actor_id: String = "") -> DeathEvent:
		var e := DeathEvent.new()
		e.actor_id = p_actor_id
		e.killer_actor_id = p_killer_actor_id
		return e
	
	func to_dict() -> Dictionary:
		var d := { "kind": kind, "actor_id": actor_id }
		if killer_actor_id != "":
			d["killer_actor_id"] = killer_actor_id
		return d
	
	static func from_dict(d: Dictionary) -> DeathEvent:
		var e := DeathEvent.new()
		e.actor_id = d.get("actor_id", "") as String
		e.killer_actor_id = d.get("killer_actor_id", "") as String
		return e
	
	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "death"


# ========== 辅助函数 ==========

static func _damage_type_to_string(p_damage_type: DamageType) -> String:
	match p_damage_type:
		DamageType.PHYSICAL:
			return "physical"
		DamageType.MAGICAL:
			return "magical"
		DamageType.PURE:
			return "pure"
		_:
			return "unknown"


static func string_to_damage_type(s: String) -> DamageType:
	match s:
		"physical":
			return DamageType.PHYSICAL
		"magical":
			return DamageType.MAGICAL
		"pure":
			return DamageType.PURE
		_:
			return DamageType.PHYSICAL
