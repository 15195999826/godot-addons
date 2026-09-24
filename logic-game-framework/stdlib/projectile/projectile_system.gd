class_name ProjectileSystem
extends System

var collision_detector: CollisionDetector
var pending_removal: Dictionary = {}
var auto_remove: bool = true

## 投射物结局（HIT / MISS / PIERCE）在产出点推所注册 instance 的 event_collector（录像，一次）并当场**定向投递回发射它的
## ability**（EventProcessor.deliver_to_ability，回执 = 载体上的 source_actor_id + source_ability_id），不按 kind 广播：
## 原始命中不是可靠的游戏事实（发射定结果的游戏对没掷中的弹也发 HIT），公开事实由发射技能的命中链结算后自己产出，旁观者听结算事件。
## 与 Action 内伤害同语义：命中当刻结算，发射技能的反应落在该事件与 despawn 之间；同 tick 多发弹体逐发结算；
## 命中的弹体在 handler 期间仍在注册表，auto_remove 到本 tick 末才 remove。despawn 只录不投。
## instance 经 get_instance() 取、不另存一份；未注册即静默短路。
func _init(detector: CollisionDetector = null, auto_remove_val: bool = true) -> void:
	super(System.SystemPriority.NORMAL)
	type = "ProjectileSystem"

	collision_detector = detector if detector else DistanceCollisionDetector.new(50.0)
	auto_remove = auto_remove_val

func tick(actors: Array[Actor], dt: float) -> void:
	var projectiles: Array[ProjectileActor] = []
	var potential_targets: Array[Actor] = []

	for actor in actors:
		if actor is ProjectileActor and actor.is_flying():
			projectiles.append(actor)
		elif actor is Actor:
			potential_targets.append(actor)

	for projectile in projectiles:
		_update_projectile(projectile, potential_targets, dt)

	if auto_remove:
		_process_pending_removal(actors)

func _update_projectile(projectile: ProjectileActor, potential_targets: Array[Actor], dt: float) -> void:
	if projectile.get_projectile_type() == ProjectileActor.PROJECTILE_TYPE_HITSCAN:
		_process_hitscan(projectile, potential_targets)
		return

	var still_flying := projectile.update(dt)

	if not still_flying:
		if projectile.get_projectile_state() == ProjectileActor.STATE_MISSED:
			_emit_miss_event(projectile, "timeout")
		_mark_for_removal(projectile)
		return

	var valid_targets := _filter_valid_targets(projectile, potential_targets)
	var collision := collision_detector.detect(projectile, valid_targets)

	if collision.get("hit", false) and collision.get("target_actor_id", "") != "":
		_process_hit(projectile, collision)

func _process_hitscan(projectile: ProjectileActor, potential_targets: Array[Actor]) -> void:
	var valid_targets := _filter_valid_targets(projectile, potential_targets)

	# 有指定目标时，在已过滤的有效目标中查找
	var target_actor_id := projectile.get_target_actor_id()
	if target_actor_id != "":
		var target_actor: Actor = null
		for actor in valid_targets:
			if actor.id == target_actor_id:
				target_actor = actor
				break
		if target_actor:
			var hit_position := projectile.position
			projectile.hit(target_actor_id)
			_emit_hit_event(projectile, target_actor_id, hit_position)
			_mark_for_removal(projectile)
			return

	# 无指定目标或指定目标不在有效列表中，用碰撞检测
	var collision := collision_detector.detect(projectile, valid_targets)
	if collision.get("hit", false) and collision.get("target_actor_id", "") != "":
		var hit_target_actor_id := collision.get("target_actor_id", "") as String
		projectile.hit(hit_target_actor_id)
		var collision_hit_position := collision.get("hit_position", Vector3.ZERO) as Vector3
		_emit_hit_event(projectile, hit_target_actor_id, collision_hit_position)
	else:
		projectile.miss("no_target")
		_emit_miss_event(projectile, "no_target")

	_mark_for_removal(projectile)

func _process_hit(projectile: ProjectileActor, collision: Dictionary) -> void:
	var target_actor_id := collision.get("target_actor_id", "") as String
	var hit_position_raw := collision.get("hit_position", null)

	if target_actor_id == "" or not (hit_position_raw is Vector3):
		return

	var hit_position := hit_position_raw as Vector3
	var continue_flying := projectile.hit(target_actor_id)

	if continue_flying:
		_emit_pierce_event(projectile, target_actor_id, hit_position)
	else:
		_emit_hit_event(projectile, target_actor_id, hit_position)
		_mark_for_removal(projectile)

func _filter_valid_targets(projectile: ProjectileActor, potential_targets: Array[Actor]) -> Array[Actor]:
	var source_actor_id := projectile.get_source_actor_id()

	var valid: Array[Actor] = []
	for target in potential_targets:
		if not (target is Actor):
			continue

		if source_actor_id != "" and target.id == source_actor_id:
			continue

		if projectile.has_hit_target(target.id):
			continue

		valid.append(target)

	return valid

func _mark_for_removal(projectile: ProjectileActor) -> void:
	pending_removal[projectile.id] = true

func _process_pending_removal(_actors: Array[Actor]) -> void:
	if pending_removal.is_empty():
		return
	var instance := get_instance()
	if instance == null:
		pending_removal.clear()
		return
	for actor_id in pending_removal:
		instance.remove_actor(actor_id)
	pending_removal.clear()

func _emit_hit_event(projectile: ProjectileActor, target_actor_id: String, hit_position: Vector3) -> void:
	var instance := get_instance()
	if instance == null:
		return

	var source_actor_id := _get_source_id(projectile)
	var options: Dictionary = {
		"damage": projectile.config.get(ProjectileActor.CFG_DAMAGE),
		"damage_type": projectile.config.get(ProjectileActor.CFG_DAMAGE_TYPE),
	}
	# Phase 01 Chain Lightning: 把 custom_data 透传到 projectile_hit event payload,
	# 与 projectile_launched 对齐, 让 hit timeline 内的 DamageAction 通过
	# ctx.get_original_event().custom_data 取到 chain_id / hit_index / damage / visited。
	var custom_data := _projectile_custom_data(projectile)
	if not custom_data.is_empty():
		options["custom_data"] = custom_data
	var event := ProjectileEvents.create_projectile_hit_event(
		projectile.id,
		source_actor_id,
		target_actor_id,
		hit_position,
		projectile.get_fly_time(),
		projectile.get_fly_distance(),
		projectile.get_ability_config_id(),
		options
	)

	instance.event_collector.push(event)
	_deliver_outcome(instance, projectile, event)

	var despawn_event := ProjectileEvents.create_projectile_despawn_event(
		projectile.id,
		source_actor_id,
		"hit"
	)
	instance.event_collector.push(despawn_event)

func _emit_miss_event(projectile: ProjectileActor, reason: String) -> void:
	var instance := get_instance()
	if instance == null:
		return

	var source_actor_id := _get_source_id(projectile)
	var final_position := projectile.position

	var event := ProjectileEvents.create_projectile_miss_event(
		projectile.id,
		source_actor_id,
		reason,
		final_position,
		projectile.get_fly_time(),
		projectile.get_target_actor_id(),
		projectile.get_ability_config_id()
	)

	instance.event_collector.push(event)
	_deliver_outcome(instance, projectile, event)

	var despawn_event := ProjectileEvents.create_projectile_despawn_event(
		projectile.id,
		source_actor_id,
		"miss"
	)

	instance.event_collector.push(despawn_event)

func _emit_pierce_event(projectile: ProjectileActor, target_actor_id: String, pierce_position: Vector3) -> void:
	var instance := get_instance()
	if instance == null:
		return

	var source_actor_id := _get_source_id(projectile)
	var event := ProjectileEvents.create_projectile_pierce_event(
		projectile.id,
		source_actor_id,
		target_actor_id,
		pierce_position,
		projectile.get_pierce_count(),
		projectile.config.get(ProjectileActor.CFG_DAMAGE, -1.0) as float,
		projectile.get_ability_config_id()
	)

	instance.event_collector.push(event)
	_deliver_outcome(instance, projectile, event)


func _get_source_id(projectile: ProjectileActor) -> String:
	var source_actor_id := projectile.get_source_actor_id()
	if source_actor_id == "":
		return "unknown"
	return source_actor_id


## 结局只投给发射它的 ability 实例。没回执的弹是编程错误（载体铁律：行为全挂施法者 ability 上，LaunchProjectileAction 自动填，
## 项目自己 launch 的照填）：已录进 collector，不投、断言。
func _deliver_outcome(instance: GameplayInstance, projectile: ProjectileActor, event: Dictionary) -> void:
	var source_ability_id := projectile.get_source_ability_id()
	if source_ability_id == "":
		Log.assert_crash(false, "ProjectileSystem",
			"projectile '%s' 没有回执（launch 参数缺 source_ability_id），'%s' 无处投递" % [projectile.id, str(event.get("kind", ""))])
		return
	instance.event_processor.deliver_to_ability(event, projectile.get_source_actor_id(), source_ability_id)


## Phase 01 Chain Lightning helper: 从 projectile.launch_params 提取 custom_data。
## 不存在或非 Dictionary 返回空 dict; 拷贝避免外部修改原 launch_params。
func _projectile_custom_data(projectile: ProjectileActor) -> Dictionary:
	var params := projectile.get_launch_params()
	var custom_data: Variant = params.get("custom_data", null)
	if not (custom_data is Dictionary):
		return {}
	return (custom_data as Dictionary).duplicate(true)

func get_active_projectiles(actors: Array[Actor]) -> Array[ProjectileActor]:
	var projectiles: Array[ProjectileActor] = []
	for actor in actors:
		if actor is ProjectileActor and actor.is_flying():
			projectiles.append(actor)
	return projectiles

func get_pending_removal_ids() -> Dictionary:
	return pending_removal.duplicate()

func force_hit(projectile: ProjectileActor, target_actor_id: String, hit_position: Vector3) -> void:
	if not projectile.is_flying():
		return

	projectile.hit(target_actor_id)
	_emit_hit_event(projectile, target_actor_id, hit_position)
	_mark_for_removal(projectile)

func force_miss(projectile: ProjectileActor, reason: String = "forced") -> void:
	if not projectile.is_flying():
		return

	projectile.miss(reason)
	_emit_miss_event(projectile, reason)
	_mark_for_removal(projectile)
