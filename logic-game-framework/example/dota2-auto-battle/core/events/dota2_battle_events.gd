## Dota2BattleEvents - dota2-auto-battle 战斗事件词汇（canonical）
##
## logic-view-contract.md 是事件词汇的 single source of truth；本文件落地那份词汇，
## 其它代码引用这里的常量而不是各自造别名。事件 = 本 logic tick 内"发生过的事实"，
## 过去时命名，actor 用 id: String，坐标用 x/y float（连续 Vector2）。
##
## 与 hex HexBattlePreEvents / rts RtsBattleEvents 平行：pre_damage 是 buff/passive 的
## hook 入口，post_damage 让未来 thorns/lifesteal 之类被动观察伤害结果（M1 留空 handler，
## 边界先在）。DOTA2 专属策略不下沉 LGF core。
class_name Dota2BattleEvents
extends RefCounted


# ========== Canonical 事件 kind（logic-view-contract.md）==========

const UNIT_SPAWNED := "dota2_unit_spawned"
const INTENT_STARTED := "dota2_intent_started"
const INTENT_COMPLETED := "dota2_intent_completed"
const INTENT_FAILED := "dota2_intent_failed"
const TARGET_ACQUIRED := "dota2_target_acquired"
const ATTACK_STARTED := "dota2_attack_started"
const ATTACK_LANDED := "dota2_attack_landed"
const DAMAGE_APPLIED := "dota2_damage_applied"
const UNIT_DIED := "dota2_unit_died"
const UNIT_REMOVED := "dota2_unit_removed"

# ========== EventProcessor pre/post 管线（buff/passive hook 边界）==========

const PRE_DAMAGE_EVENT := "dota2_pre_damage"
const POST_DAMAGE_EVENT := "dota2_post_damage"


# ========== 生命周期 ==========

static func make_unit_spawned(
	actor_id: String,
	team_id: int,
	unit_type_id: String,
	pos: Vector2,
	max_hp: float,
) -> Dictionary:
	return {
		"kind": UNIT_SPAWNED,
		"actor_id": actor_id,
		"team_id": team_id,
		"unit_type_id": unit_type_id,
		"x": pos.x,
		"y": pos.y,
		"max_hp": max_hp,
	}


static func make_unit_died(actor_id: String, killer_id: String) -> Dictionary:
	return {
		"kind": UNIT_DIED,
		"actor_id": actor_id,
		"killer_id": killer_id,
	}


static func make_unit_removed(actor_id: String) -> Dictionary:
	return {
		"kind": UNIT_REMOVED,
		"actor_id": actor_id,
	}


# ========== Intent 生命周期（controller 拥有，systems 报告事实）==========

static func make_intent_started(
	actor_id: String,
	intent_id: int,
	intent_kind: String,
	target_id: String,
) -> Dictionary:
	return {
		"kind": INTENT_STARTED,
		"actor_id": actor_id,
		"intent_id": intent_id,
		"intent_kind": intent_kind,
		"target_id": target_id,
	}


static func make_intent_completed(
	actor_id: String,
	intent_id: int,
	intent_kind: String,
	reason: String,
) -> Dictionary:
	return {
		"kind": INTENT_COMPLETED,
		"actor_id": actor_id,
		"intent_id": intent_id,
		"intent_kind": intent_kind,
		"reason": reason,
	}


static func make_intent_failed(
	actor_id: String,
	intent_id: int,
	intent_kind: String,
	reason: String,
) -> Dictionary:
	return {
		"kind": INTENT_FAILED,
		"actor_id": actor_id,
		"intent_id": intent_id,
		"intent_kind": intent_kind,
		"reason": reason,
	}


# ========== Targeting ==========

static func make_target_acquired(
	actor_id: String,
	target_id: String,
	distance: float,
) -> Dictionary:
	return {
		"kind": TARGET_ACQUIRED,
		"actor_id": actor_id,
		"target_id": target_id,
		"distance": distance,
	}


# ========== 基础攻击（走 Ability/Timeline/Action 路径）==========

static func make_attack_started(
	source_id: String,
	target_id: String,
	ability_config_id: String,
) -> Dictionary:
	return {
		"kind": ATTACK_STARTED,
		"source_actor_id": source_id,
		"target_actor_id": target_id,
		"ability_config_id": ability_config_id,
	}


static func make_attack_landed(
	source_id: String,
	target_id: String,
	damage: float,
) -> Dictionary:
	return {
		"kind": ATTACK_LANDED,
		"source_actor_id": source_id,
		"target_actor_id": target_id,
		"damage": damage,
	}


static func make_damage_applied(
	source_id: String,
	target_id: String,
	damage: float,
	target_hp_after: float,
) -> Dictionary:
	return {
		"kind": DAMAGE_APPLIED,
		"source_actor_id": source_id,
		"target_actor_id": target_id,
		"damage": damage,
		"target_hp_after": target_hp_after,
	}


# ========== EventProcessor pre/post（M1 handler 留空，边界先在）==========

static func make_pre_damage(source_id: String, target_id: String, damage: float) -> Dictionary:
	return {
		"kind": PRE_DAMAGE_EVENT,
		"source_actor_id": source_id,
		"target_actor_id": target_id,
		"damage": damage,
	}


static func make_post_damage(
	source_id: String,
	target_id: String,
	damage_applied: float,
	target_hp_after: float,
) -> Dictionary:
	return {
		"kind": POST_DAMAGE_EVENT,
		"source_actor_id": source_id,
		"target_actor_id": target_id,
		"damage": damage_applied,
		"target_hp_after": target_hp_after,
	}
