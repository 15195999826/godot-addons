## RtsBattleEvents - RTS 战斗事件常量与字段定义
##
## RTS 例子特有的事件 kind, 不进 LGF core / stdlib。
## 与 hex 例子的 HexBattlePreEvents 平行: pre_damage 是 buff / passive 的 hook 入口,
## post_damage 用来让 thorns / lifesteal 之类的被动观察到伤害结果(M0 留空, M1 接入)。
##
## 字段命名走 LGF 的 snake_case 约定; sourceId / targetId 用 LGF 的全 actor id 字符串。
class_name RtsBattleEvents
extends RefCounted


# Pre 阶段
const PRE_DAMAGE_EVENT := "rts_pre_damage"

# Post 阶段
const POST_DAMAGE_EVENT := "rts_post_damage"
const ATTACK_RESOLVED_EVENT := "rts_attack_resolved"  # 用于 logger / AC3 兵种行为断言
const ACTOR_DIED_EVENT := "rts_actor_died"

# M7d - motion abort 反馈给 activity (failed_movements >= 35 时 motion 触发)
const MOTION_MOVE_FAILED_EVENT := "rts_motion_move_failed"


## 构造 PreDamage event(供 attack action 调 EventProcessor.process_pre_event 用)
static func make_pre_damage(source_id: String, target_id: String, damage: float) -> Dictionary:
	return {
		"kind": PRE_DAMAGE_EVENT,
		"source_actor_id": source_id,
		"target_actor_id": target_id,
		"damage": damage,
	}


## 构造 PostDamage event(实际伤害已应用后广播给所有存活 actor)
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


## 构造 AttackResolved event(给 logger / AC3 兵种行为断言用)
static func make_attack_resolved(
	source_id: String,
	target_id: String,
	attacker_pos: Vector2,
	target_pos: Vector2,
	attacker_unit_class: int,  # RtsUnitClassConfig.UnitClass(int)
	damage: float,
) -> Dictionary:
	return {
		"kind": ATTACK_RESOLVED_EVENT,
		"source_actor_id": source_id,
		"target_actor_id": target_id,
		"attacker_pos_x": attacker_pos.x,
		"attacker_pos_y": attacker_pos.y,
		"target_pos_x": target_pos.x,
		"target_pos_y": target_pos.y,
		"attacker_unit_class": attacker_unit_class,
		"distance": attacker_pos.distance_to(target_pos),
		"damage": damage,
	}


static func make_actor_died(actor_id: String, killer_id: String) -> Dictionary:
	return {
		"kind": ACTOR_DIED_EVENT,
		"actor_id": actor_id,
		"killer_id": killer_id,
	}


## 构造 MotionMoveFailed event (M7d) — RtsMotionComponent 在 motion._failed_movements 累达
## MAX_FAILED_MOVEMENTS=35 触发 abort 时 emit 给 owner_actor。activity 监听后:
##   - attack: re-acquire target / abort
##   - harvest: reset 状态 / 找新 node
##   - move_to: end activity (玩家 click 到不可达点)
##
## **fail_count** 字段记最后累计值供 debug;**move_request_kind** 让 activity 决定是否需 retry。
static func make_motion_move_failed(actor_id: String, fail_count: int, move_request_kind: int) -> Dictionary:
	return {
		"kind": MOTION_MOVE_FAILED_EVENT,
		"actor_id": actor_id,
		"fail_count": fail_count,
		"move_request_kind": move_request_kind,
	}
