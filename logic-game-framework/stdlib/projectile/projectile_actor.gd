class_name ProjectileActor
extends Actor

const PROJECTILE_TYPE_BULLET := "bullet"
const PROJECTILE_TYPE_HITSCAN := "hitscan"
const PROJECTILE_TYPE_MOBA := "moba"

const STATE_IDLE := "idle"
const STATE_FLYING := "flying"
const STATE_HIT := "hit"
const STATE_MISSED := "missed"
const STATE_DESPAWNED := "despawned"

## Config key 常量
const CFG_PROJECTILE_TYPE := "projectileType"
const CFG_VISUAL_TYPE := "visualType"  ## 表演层视觉类型（arrow, fireball, energy 等）
const CFG_SPEED := "speed"  ## 单位/秒
const CFG_MAX_LIFETIME := "maxLifetime"  ## 毫秒
const CFG_PIERCING := "piercing"
const CFG_MAX_PIERCE_COUNT := "maxPierceCount"
const CFG_HIT_DISTANCE := "hitDistance"
const CFG_DAMAGE := "damage"
const CFG_DAMAGE_TYPE := "damageType"

const DEFAULT_CONFIG := {
	"projectileType": PROJECTILE_TYPE_BULLET,
	"speed": 500.0,
	"maxLifetime": 5000.0,
}

var config: Dictionary = {}
var _position: Vector3 = Vector3.ZERO

var _projectile_state: String = STATE_IDLE
var _launch_params: Dictionary = {}
var _fly_time: float = 0.0
var _fly_distance: float = 0.0
var _pierce_count: int = 0
var _hit_targets: Dictionary = {}

func _init(config_value: Dictionary = {}):
	type = "Projectile"
	config = DEFAULT_CONFIG.duplicate(true)
	config.merge(config_value, true)


## 覆盖基类方法，返回投射物位置
func _get_position() -> Vector3:
	return _position

func get_projectile_state() -> String:
	return _projectile_state

func get_projectile_type() -> String:
	return config.get(CFG_PROJECTILE_TYPE, PROJECTILE_TYPE_BULLET) as String

func is_flying() -> bool:
	return _projectile_state == STATE_FLYING

func get_launch_params() -> Dictionary:
	return _launch_params

func get_source_actor_id() -> String:
	return _launch_params.get("source_actor_id", "") as String

func get_ability_config_id() -> String:
	return _launch_params.get("ability_config_id", "") as String

func get_target_actor_id() -> String:
	return _launch_params.get("target_actor_id", "") as String

func get_fly_time() -> float:
	return _fly_time

func get_fly_distance() -> float:
	return _fly_distance

func get_pierce_count() -> int:
	return _pierce_count

func get_hit_targets() -> Array[String]:
	var result: Array[String] = []
	result.assign(_hit_targets.keys())
	return result

func launch(params: Dictionary) -> void:
	if _projectile_state != STATE_IDLE:
		return

	_launch_params = params.duplicate(true)
	if params.has("startPosition") and params["startPosition"] is Vector3:
		_position = params["startPosition"]

	_projectile_state = STATE_FLYING
	_fly_time = 0.0
	_fly_distance = 0.0
	_pierce_count = 0
	_hit_targets.clear()

	if get_projectile_type() == PROJECTILE_TYPE_HITSCAN:
		if params.has("targetPosition") and params["targetPosition"] is Vector3:
			_position = params["targetPosition"]

## 每帧更新投射物状态
##
## 【已知问题：高速投射物穿透】
## 当一帧内移动距离 > 碰撞半径时，投射物可能直接穿过目标。
##
## 简化修复方案（无需 Raycasting）：
##   在 ProjectileSystem._update_projectile() 的碰撞检测前，
##   比较本帧移动距离与碰撞半径：
##     var move_distance = speed * dt / 1000.0
##     var hit_distance = projectile.config.get(CFG_HIT_DISTANCE, 50.0)
##     if move_distance > hit_distance:
##         # 将本帧拆分为多个子步（substep），每步移动 ≤ hit_distance
##         var steps = ceili(move_distance / hit_distance)
##         var sub_dt = dt / steps
##         for i in range(steps):
##             projectile.update_position(sub_dt)
##             var collision = collision_detector.detect(projectile, targets)
##             if collision.hit: break
##
##   优点：实现简单，无需引入射线检测
##   缺点：高速投射物每帧多次碰撞检测，但通常只需 2-3 次子步
func update(dt: float) -> bool:
	if _projectile_state != STATE_FLYING:
		return false

	if get_projectile_type() == PROJECTILE_TYPE_HITSCAN:
		return false

	_fly_time += dt
	if _fly_time >= (config.get(CFG_MAX_LIFETIME, 0.0) as float):
		miss("timeout")
		return false

	update_position(dt)
	return true

func update_position(dt: float) -> void:
	if _launch_params.is_empty():
		return

	var dt_seconds := dt / 1000.0
	var move_distance := (config.get(CFG_SPEED, 0.0) as float) * dt_seconds
	_fly_distance += move_distance

	var movement := Vector3.ZERO
	var dir_value: Variant = _launch_params.get("direction")
	if dir_value is Vector3 and (dir_value as Vector3) != Vector3.ZERO:
		var dir_vec: Vector3 = dir_value
		movement = dir_vec.normalized() * move_distance
	else:
		var target_pos := _resolve_target_position()
		if target_pos != Vector3.ZERO or _launch_params.has("targetPosition"):
			var direction_vec: Vector3 = target_pos - _position
			var distance_to_target := direction_vec.length()
			if distance_to_target > 0.0:
				var actual_move := min(move_distance, distance_to_target)
				movement = direction_vec.normalized() * actual_move

	_position += movement


## 获取目标的实时位置
## MOBA 追踪型投射物会查询目标 Actor 的实时 position，
## 其他类型退回到 launch_params 中的静态 targetPosition
func _resolve_target_position() -> Vector3:
	if get_projectile_type() == PROJECTILE_TYPE_MOBA:
		var target_actor_id := get_target_actor_id()
		if target_actor_id != "":
			var instance := get_owner_gameplay_instance()
			if instance != null:
				var target := instance.get_actor(target_actor_id)
				if target != null:
					return target.position
	var static_pos: Variant = _launch_params.get("targetPosition")
	if static_pos is Vector3:
		return static_pos
	return Vector3.ZERO


func get_distance_to_target() -> float:
	var target_pos := _resolve_target_position()
	if target_pos == Vector3.ZERO and not _launch_params.has("targetPosition"):
		return INF
	return _position.distance_to(target_pos)

func hit(target_id: String) -> bool:
	if _projectile_state != STATE_FLYING:
		return false

	_hit_targets[target_id] = true

	if config.get(CFG_PIERCING, false) as bool:
		_pierce_count += 1
		var max_pierce: Variant = config.get(CFG_MAX_PIERCE_COUNT, null)
		var max_pierce_count := INF if max_pierce == null else int(max_pierce)
		if _pierce_count < max_pierce_count:
			return true

	_projectile_state = STATE_HIT
	return false

func miss(_reason: String = "no_target") -> void:
	if _projectile_state != STATE_FLYING:
		return
	_projectile_state = STATE_MISSED

func despawn() -> void:
	_projectile_state = STATE_DESPAWNED
	on_despawn()

func has_hit_target(target_id: String) -> bool:
	return _hit_targets.has(target_id)

func should_moba_hit() -> bool:
	if get_projectile_type() != PROJECTILE_TYPE_MOBA:
		return false
	var hit_distance := config.get(CFG_HIT_DISTANCE, 50.0) as float
	return get_distance_to_target() <= hit_distance

func serialize() -> Dictionary:
	var data := serialize_base()
	data["config"] = config
	data["position"] = _position
	data["projectileState"] = _projectile_state
	data["launchParams"] = _launch_params
	data["flyTime"] = _fly_time
	data["flyDistance"] = _fly_distance
	data["pierceCount"] = _pierce_count
	data["hitTargets"] = _hit_targets.keys()
	return data
