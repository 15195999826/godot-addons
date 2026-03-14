class_name ProjectileEvents
## 纯静态工具类：投射物事件工厂

const PROJECTILE_LAUNCHED_EVENT := "projectileLaunched"
const PROJECTILE_HIT_EVENT := "projectileHit"
const PROJECTILE_MISS_EVENT := "projectileMiss"
const PROJECTILE_DESPAWN_EVENT := "projectileDespawn"
const PROJECTILE_PIERCE_EVENT := "projectilePierce"

## target_position: Vector3.ZERO 表示无目标位置
static func create_projectile_launched_event(projectile_id: String, source_actor_id: String, start_position: Vector3, projectile_type: String, speed: float, target_actor_id: String = "", target_position: Vector3 = Vector3.ZERO) -> Dictionary:
	var payload := {
		"kind": PROJECTILE_LAUNCHED_EVENT,
		"projectileId": projectile_id,
		"source_actor_id": source_actor_id,
		"startPosition": start_position,
		"projectileType": projectile_type,
		"speed": speed,
	}
	if target_actor_id != "":
		payload["target_actor_id"] = target_actor_id
	if target_position != Vector3.ZERO:
		payload["targetPosition"] = target_position
	return payload

static func create_projectile_hit_event(projectile_id: String, source_actor_id: String, target_actor_id: String, hit_position: Vector3, fly_time: float, fly_distance: float, ability_config_id: String = "", options: Dictionary = {}) -> Dictionary:
	var payload := {
		"kind": PROJECTILE_HIT_EVENT,
		"projectileId": projectile_id,
		"source_actor_id": source_actor_id,
		"target_actor_id": target_actor_id,
		"hitPosition": hit_position,
		"flyTime": fly_time,
		"flyDistance": fly_distance,
	}
	if ability_config_id != "":
		payload["ability_config_id"] = ability_config_id
	for key in options.keys():
		payload[key] = options[key]
	return payload

static func create_projectile_miss_event(projectile_id: String, source_actor_id: String, reason: String, final_position: Vector3, fly_time: float, target_actor_id: String = "", ability_config_id: String = "") -> Dictionary:
	var payload := {
		"kind": PROJECTILE_MISS_EVENT,
		"projectileId": projectile_id,
		"source_actor_id": source_actor_id,
		"reason": reason,
		"finalPosition": final_position,
		"flyTime": fly_time,
	}
	if target_actor_id != "":
		payload["target_actor_id"] = target_actor_id
	if ability_config_id != "":
		payload["ability_config_id"] = ability_config_id
	return payload

static func create_projectile_despawn_event(projectile_id: String, source_actor_id: String, reason: String) -> Dictionary:
	return {
		"kind": PROJECTILE_DESPAWN_EVENT,
		"projectileId": projectile_id,
		"source_actor_id": source_actor_id,
		"reason": reason,
	}

## damage: -1.0 表示无伤害数据
static func create_projectile_pierce_event(projectile_id: String, source_actor_id: String, target_actor_id: String, pierce_position: Vector3, pierce_count: int, damage: float = -1.0, ability_config_id: String = "") -> Dictionary:
	var payload := {
		"kind": PROJECTILE_PIERCE_EVENT,
		"projectileId": projectile_id,
		"source_actor_id": source_actor_id,
		"target_actor_id": target_actor_id,
		"piercePosition": pierce_position,
		"pierceCount": pierce_count,
	}
	if damage >= 0.0:
		payload["damage"] = damage
	if ability_config_id != "":
		payload["ability_config_id"] = ability_config_id
	return payload

static func is_projectile_launched_event(event: Dictionary) -> bool:
	return _is_kind(event, PROJECTILE_LAUNCHED_EVENT)

static func is_projectile_hit_event(event: Dictionary) -> bool:
	return _is_kind(event, PROJECTILE_HIT_EVENT)

static func is_projectile_miss_event(event: Dictionary) -> bool:
	return _is_kind(event, PROJECTILE_MISS_EVENT)

static func is_projectile_despawn_event(event: Dictionary) -> bool:
	return _is_kind(event, PROJECTILE_DESPAWN_EVENT)

static func is_projectile_pierce_event(event: Dictionary) -> bool:
	return _is_kind(event, PROJECTILE_PIERCE_EVENT)


static func _is_kind(event: Dictionary, kind: String) -> bool:
	return event.get("kind", "") == kind
