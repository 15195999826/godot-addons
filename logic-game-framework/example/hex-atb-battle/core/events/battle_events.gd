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
	## 该字段保留为「修正后总伤害」（pre 阶段易伤/减伤/暴击之后、护盾结算之前的值）。
	## 为兼容现有 reflect / thorn 等逻辑保持原名 damage 不动。
	var target_actor_id: String = ""
	var damage: float = 0.0
	var damage_type: DamageType = DamageType.PHYSICAL
	var source_actor_id: String = ""
	var is_critical: bool = false
	var is_reflected: bool = false
	## 护盾系统填充：本次被护盾吸收的总量（>= 0）。无护盾参与时为 0
	var shield_absorbed: float = 0.0
	## 护盾系统填充：实际打到生命的伤害（= damage - shield_absorbed，>= 0）。
	## on-damage-taken 类反应（反伤/吸血）默认应只对 actual_life_damage > 0 响应。
	var actual_life_damage: float = 0.0
	## 护盾系统填充：本次伤害消耗的护盾记录（按消耗顺序）
	## 每条字段见 HexBattleShieldComponent.get_state_snapshot() + absorbed/broken/damage_type
	var consumption_records: Array = []

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
		e.actual_life_damage = p_damage  # 默认 = damage，apply_damage 在护盾结算后写真值
		return e

	func to_dict() -> Dictionary:
		var d := {
			"kind": kind,
			"target_actor_id": target_actor_id,
			"damage": damage,
			"damage_type": BattleEvents._damage_type_to_string(damage_type),
			"is_critical": is_critical,
			"is_reflected": is_reflected,
			"shield_absorbed": shield_absorbed,
			"actual_life_damage": actual_life_damage,
			"consumption_records": consumption_records.duplicate(true),
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
		e.shield_absorbed = d.get("shield_absorbed", 0.0) as float
		e.actual_life_damage = d.get("actual_life_damage", e.damage) as float
		e.consumption_records = (d.get("consumption_records", []) as Array).duplicate(true)
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "damage"


# ========== BasicAttackLandedEvent ==========
##
## Basic-attack 命中后的 domain event. Strike (以及未来其它"普攻"类 ability)
## 在标准 damage 结算之后通过 on_hit callback emit. 用于:
##   - Phase B HexBattleGeneralPassive 触发 attack_lifesteal_pct
##   - Phase G+ 装备 on-hit / 法球 / 攻击特效订阅
##
## 不由 Fireball / Poison tick / reflected damage / Fire Tile / Totem passive damage 触发.
## 通过 mutable.cancelled 或 target 已死的 damage 同样不触发 (callback 在那两个分支前 skip).
## actual_life_damage = 0 (shield 全吸) 时仍 emit, consumer 自行 no-op.
##
## Post-broadcast 顺序: BasicAttackLandedEvent 在 HexBattleDamageAction.on_hit 内 broadcast,
## 早于 broadcast_post_damage (即"父 damage event 的 post"). 同一帧同时订阅 'damage' 与
## 'basic_attack_landed' 的 listener 会先收到 basic_attack_landed 再收到 damage post.
## attacker_actor_id 可能指向已死 actor (Strike timeline 自 HIT 起 fire-and-forget, 父
## DamageAction 没有 caster-alive guard); consumer 自行用 GameWorld.get_actor() 校验.

class BasicAttackLandedEvent extends GameEvent.Base:
	var attacker_actor_id: String = ""
	var target_actor_id: String = ""
	var source_ability_id: String = ""
	var source_ability_config_id: String = ""
	var actual_life_damage: float = 0.0
	## 携带触发本事件的 damage event dict, 供 consumer 读取 shield_absorbed /
	## consumption_records / is_critical 等字段, 不必再回查 EventCollector.
	var damage_event: Dictionary = {}

	func _init() -> void:
		kind = "basic_attack_landed"

	## 注意: damage_event 字段保存 caller 传入的 dict 引用本身 (不 duplicate).
	## 反正 to_dict() 出口会 duplicate(true), 此处再拷一次纯属浪费 (deep array /
	## consumption_records 在 shield 链长时尤甚). caller 责任: 传入后不再 mutate
	## 该 dict (Strike._EmitBasicAttackLandedAction 满足此约定).
	static func create(
		p_attacker_actor_id: String,
		p_target_actor_id: String,
		p_source_ability_id: String,
		p_source_ability_config_id: String,
		p_actual_life_damage: float,
		p_damage_event: Dictionary,
	) -> BasicAttackLandedEvent:
		var e := BasicAttackLandedEvent.new()
		e.attacker_actor_id = p_attacker_actor_id
		e.target_actor_id = p_target_actor_id
		e.source_ability_id = p_source_ability_id
		e.source_ability_config_id = p_source_ability_config_id
		e.actual_life_damage = p_actual_life_damage
		e.damage_event = p_damage_event
		return e

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"attacker_actor_id": attacker_actor_id,
			"target_actor_id": target_actor_id,
			"source_ability_id": source_ability_id,
			"source_ability_config_id": source_ability_config_id,
			"actual_life_damage": actual_life_damage,
			"damage_event": damage_event.duplicate(true),
		}

	static func from_dict(d: Dictionary) -> BasicAttackLandedEvent:
		var e := BasicAttackLandedEvent.new()
		e.attacker_actor_id = d.get("attacker_actor_id", "") as String
		e.target_actor_id = d.get("target_actor_id", "") as String
		e.source_ability_id = d.get("source_ability_id", "") as String
		e.source_ability_config_id = d.get("source_ability_config_id", "") as String
		e.actual_life_damage = d.get("actual_life_damage", 0.0) as float
		var damage_event_value: Variant = d.get("damage_event", null)
		e.damage_event = (damage_event_value as Dictionary).duplicate(true) if damage_event_value is Dictionary else {}
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "basic_attack_landed"


# ========== ShieldBrokenEvent ==========
##
## 护盾被本次伤害打破时由 apply_damage 触发的二次事件。
## 单纯通报「这个护盾刚刚破了」，不携带伤害数值。on_break 回调要 push 的爆炸 / 治疗 / 反伤
## 是另外的 damage / heal event，跟这条事件没有 1:1 关系。

class ShieldBrokenEvent extends GameEvent.Base:
	var target_actor_id: String = ""
	var attacker_actor_id: String = ""
	var shield_ability_id: String = ""
	var shield_config_id: String = ""
	var damage_type: String = ""
	var absorbed_amount: float = 0.0

	func _init() -> void:
		kind = "shield_broken"

	static func create(
		p_target_actor_id: String,
		p_attacker_actor_id: String,
		p_shield_ability_id: String,
		p_shield_config_id: String,
		p_damage_type: String,
		p_absorbed_amount: float
	) -> ShieldBrokenEvent:
		var e := ShieldBrokenEvent.new()
		e.target_actor_id = p_target_actor_id
		e.attacker_actor_id = p_attacker_actor_id
		e.shield_ability_id = p_shield_ability_id
		e.shield_config_id = p_shield_config_id
		e.damage_type = p_damage_type
		e.absorbed_amount = p_absorbed_amount
		return e

	func to_dict() -> Dictionary:
		var d := {
			"kind": kind,
			"target_actor_id": target_actor_id,
			"shield_ability_id": shield_ability_id,
			"shield_config_id": shield_config_id,
			"damage_type": damage_type,
			"absorbed_amount": absorbed_amount,
		}
		if attacker_actor_id != "":
			d["attacker_actor_id"] = attacker_actor_id
		return d

	static func from_dict(d: Dictionary) -> ShieldBrokenEvent:
		var e := ShieldBrokenEvent.new()
		e.target_actor_id = d.get("target_actor_id", "") as String
		e.attacker_actor_id = d.get("attacker_actor_id", "") as String
		e.shield_ability_id = d.get("shield_ability_id", "") as String
		e.shield_config_id = d.get("shield_config_id", "") as String
		e.damage_type = d.get("damage_type", "") as String
		e.absorbed_amount = d.get("absorbed_amount", 0.0) as float
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "shield_broken"


# ========== RegenerationEvent ==========
##
## Resource 自然恢复 (Phase C: hp_regen_per_sec; 未来 mp_regen_per_sec).
##
## V1 contract (per advanced-skills-next-batch.md):
##   - NOT a heal: 不走 HexBattleHealAction, 不产生 HealEvent.
##   - 不触发 heal-related passive (on-heal / post-heal / heal amp / overheal).
##   - 仍 replay/frontend 可见: 独立 RegenerationEvent.
##   - actual_amount clamp 到 max_hp - hp_before (overheal 不补 shield).
##   - 由 HexBattleGeneralPassive periodic timeline 驱动, source 标 "general_passive".

class RegenerationEvent extends GameEvent.Base:
	var target_actor_id: String = ""
	var resource: String = "hp"  ## 当前仅 "hp"; 未来 "mp" 等
	## amount: 周期内理论恢复量 (= resource_per_sec * period_s)
	var amount: float = 0.0
	## actual_amount: clamp 到 max 之后的实际恢复 (overheal 会 < amount)
	var actual_amount: float = 0.0
	## source: 标记来源, 便于 replay/分析区分多个 regen 来源
	var source: String = ""

	func _init() -> void:
		kind = "regeneration"

	static func create(
		p_target_actor_id: String,
		p_resource: String,
		p_amount: float,
		p_actual_amount: float,
		p_source: String,
	) -> RegenerationEvent:
		var e := RegenerationEvent.new()
		e.target_actor_id = p_target_actor_id
		e.resource = p_resource
		e.amount = p_amount
		e.actual_amount = p_actual_amount
		e.source = p_source
		return e

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"target_actor_id": target_actor_id,
			"resource": resource,
			"amount": amount,
			"actual_amount": actual_amount,
			"source": source,
		}

	static func from_dict(d: Dictionary) -> RegenerationEvent:
		var e := RegenerationEvent.new()
		e.target_actor_id = d.get("target_actor_id", "") as String
		e.resource = d.get("resource", "hp") as String
		e.amount = d.get("amount", 0.0) as float
		e.actual_amount = d.get("actual_amount", 0.0) as float
		e.source = d.get("source", "") as String
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "regeneration"


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


# ========== ActorDisplacedEvent ==========
##
## 强制位移 (forced displacement) — 区别于自愿 MoveComplete:
##   - knockback / pull / scatter 都走这个事件
##   - 仅当 actor 真的移动时 push (from_hex != to_hex)
##   - 目标格被挡住没移动时不 push 此事件, 走 PushBlockedEvent
##
class ActorDisplacedEvent extends GameEvent.Base:
	var actor_id: String = ""
	var from_hex: Dictionary = {}
	var to_hex: Dictionary = {}
	var displacement_kind: String = ""  # "knockback" | (future) "pull" | "scatter" | "swap"
	var source_actor_id: String = ""
	var actual_distance: int = 0
	var action_lock_duration_ms: float = 0.0
	var collision_action_lock_bonus_ms: float = 0.0
	## Phase E (Swap): 配对 displacement event 同 swap_id, 让 frontend visualizer
	## 找到对手做配对动画。其它 displacement_kind 默认空字符串。
	var swap_id: String = ""

	func _init() -> void:
		kind = "actor_displaced"

	static func create(
		p_actor_id: String,
		p_from_hex: Dictionary,
		p_to_hex: Dictionary,
		p_displacement_kind: String,
		p_source_actor_id: String,
		p_actual_distance: int = 0,
		p_action_lock_duration_ms: float = 0.0,
		p_collision_action_lock_bonus_ms: float = 0.0,
		p_swap_id: String = ""
	) -> ActorDisplacedEvent:
		var e := ActorDisplacedEvent.new()
		e.actor_id = p_actor_id
		e.from_hex = p_from_hex
		e.to_hex = p_to_hex
		e.displacement_kind = p_displacement_kind
		e.source_actor_id = p_source_actor_id
		e.actual_distance = p_actual_distance
		e.action_lock_duration_ms = p_action_lock_duration_ms
		e.collision_action_lock_bonus_ms = p_collision_action_lock_bonus_ms
		e.swap_id = p_swap_id
		return e

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"actor_id": actor_id,
			"from_hex": from_hex,
			"to_hex": to_hex,
			"displacement_kind": displacement_kind,
			"source_actor_id": source_actor_id,
			"actual_distance": actual_distance,
			"action_lock_duration_ms": action_lock_duration_ms,
			"collision_action_lock_bonus_ms": collision_action_lock_bonus_ms,
			"swap_id": swap_id,
		}

	static func from_dict(d: Dictionary) -> ActorDisplacedEvent:
		var e := ActorDisplacedEvent.new()
		e.actor_id = d.get("actor_id", "") as String
		e.from_hex = d.get("from_hex", {}) as Dictionary
		e.to_hex = d.get("to_hex", {}) as Dictionary
		e.displacement_kind = d.get("displacement_kind", "") as String
		e.source_actor_id = d.get("source_actor_id", "") as String
		e.actual_distance = d.get("actual_distance", 0) as int
		e.action_lock_duration_ms = d.get("action_lock_duration_ms", 0.0) as float
		e.collision_action_lock_bonus_ms = d.get("collision_action_lock_bonus_ms", 0.0) as float
		e.swap_id = d.get("swap_id", "") as String
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "actor_displaced"


# ========== ActorFacingChangedEvent ==========
##
## §0.3: 角色逻辑朝向变化事件。前端消费用于 visual-facing 平滑转向 (lerp/tween),
## 不引入 turn speed / turn duration / facing lock。
## old_direction / new_direction 0..5 对应 HexCoord.DIRECTIONS (E/NE/NW/W/SW/SE)。
## reason 取自 HexFacing.REASON_* 常量 (init / move / active_use / shadow_step / ...)。
##
class ActorFacingChangedEvent extends GameEvent.Base:
	var actor_id: String = ""
	var old_direction: int = 0
	var new_direction: int = 0
	var reason: String = ""

	func _init() -> void:
		kind = "actor_facing_changed"

	static func create(
		p_actor_id: String,
		p_old_direction: int,
		p_new_direction: int,
		p_reason: String
	) -> ActorFacingChangedEvent:
		var e := ActorFacingChangedEvent.new()
		e.actor_id = p_actor_id
		e.old_direction = p_old_direction
		e.new_direction = p_new_direction
		e.reason = p_reason
		return e

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"actor_id": actor_id,
			"old_direction": old_direction,
			"new_direction": new_direction,
			"reason": reason,
		}

	static func from_dict(d: Dictionary) -> ActorFacingChangedEvent:
		var e := ActorFacingChangedEvent.new()
		e.actor_id = d.get("actor_id", "") as String
		e.old_direction = d.get("old_direction", 0) as int
		e.new_direction = d.get("new_direction", 0) as int
		e.reason = d.get("reason", "") as String
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "actor_facing_changed"


# ========== PushBlockedEvent ==========
##
## 推 / 击退被阻挡 — target 沿 push 方向尝试位移, 但路径上撞到不可越过的物体或地图边界。
## 与 ActorDisplacedEvent 互补:
##   - 完全没移动 (撞到正前方): 仅 PushBlockedEvent
##   - 移动若干格后撞到 (N>1 链式推): ActorDisplacedEvent + PushBlockedEvent
## 字段语义与 ActorDisplacedEvent 对齐: actor_id = 被推的 target;
## stopped_at_hex = target 实际停在哪 (= ActorDisplacedEvent.to_hex 当二者同时 fire);
## attempted_to_hex = 若不挡能到达的格子。replay / frontend / scenario 不必重算坐标。
##
class PushBlockedEvent extends GameEvent.Base:
	var actor_id: String = ""                 # 被推的 target
	var stopped_at_hex: Dictionary = {}       # target 实际停在的位置
	var attempted_to_hex: Dictionary = {}     # 若不挡, 推算到达的目标格
	var blocked_by: String = ""               # "edge" | "actor"
	var blocker_actor_id: String = ""         # 当 blocked_by == "actor" 时的 blocker id, 否则 ""
	var source_actor_id: String = ""
	var actual_distance: int = 0
	var action_lock_duration_ms: float = 0.0
	var collision_action_lock_bonus_ms: float = 0.0

	func _init() -> void:
		kind = "push_blocked"

	static func create(
		p_actor_id: String,
		p_stopped_at_hex: Dictionary,
		p_attempted_to_hex: Dictionary,
		p_blocked_by: String,
		p_blocker_actor_id: String,
		p_source_actor_id: String,
		p_actual_distance: int = 0,
		p_action_lock_duration_ms: float = 0.0,
		p_collision_action_lock_bonus_ms: float = 0.0
	) -> PushBlockedEvent:
		var e := PushBlockedEvent.new()
		e.actor_id = p_actor_id
		e.stopped_at_hex = p_stopped_at_hex
		e.attempted_to_hex = p_attempted_to_hex
		e.blocked_by = p_blocked_by
		e.blocker_actor_id = p_blocker_actor_id
		e.source_actor_id = p_source_actor_id
		e.actual_distance = p_actual_distance
		e.action_lock_duration_ms = p_action_lock_duration_ms
		e.collision_action_lock_bonus_ms = p_collision_action_lock_bonus_ms
		return e

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"actor_id": actor_id,
			"stopped_at_hex": stopped_at_hex,
			"attempted_to_hex": attempted_to_hex,
			"blocked_by": blocked_by,
			"blocker_actor_id": blocker_actor_id,
			"source_actor_id": source_actor_id,
			"actual_distance": actual_distance,
			"action_lock_duration_ms": action_lock_duration_ms,
			"collision_action_lock_bonus_ms": collision_action_lock_bonus_ms,
		}

	static func from_dict(d: Dictionary) -> PushBlockedEvent:
		var e := PushBlockedEvent.new()
		e.actor_id = d.get("actor_id", "") as String
		e.stopped_at_hex = d.get("stopped_at_hex", {}) as Dictionary
		e.attempted_to_hex = d.get("attempted_to_hex", {}) as Dictionary
		e.blocked_by = d.get("blocked_by", "") as String
		e.blocker_actor_id = d.get("blocker_actor_id", "") as String
		e.source_actor_id = d.get("source_actor_id", "") as String
		e.actual_distance = d.get("actual_distance", 0) as int
		e.action_lock_duration_ms = d.get("action_lock_duration_ms", 0.0) as float
		e.collision_action_lock_bonus_ms = d.get("collision_action_lock_bonus_ms", 0.0) as float
		return e

	static func is_match(d: Dictionary) -> bool:
		return d.get("kind") == "push_blocked"


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
