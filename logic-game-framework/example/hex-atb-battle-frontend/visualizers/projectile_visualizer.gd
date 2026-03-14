## ProjectileVisualizer - 投射物事件转换器
##
## 将投射物相关事件翻译为视觉动作：
## - projectileLaunched: 创建投射物飞行动画
## - projectileHit: 命中特效
## - projectileMiss: 消散特效
class_name FrontendProjectileVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "ProjectileVisualizer"


## 检查是否为投射物事件
func can_handle(event: Dictionary) -> bool:
	var kind := get_event_kind(event)
	return kind == "projectileLaunched" or kind == "projectileHit" or kind == "projectileMiss"


## 翻译投射物事件为视觉动作
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var kind := get_event_kind(event)
	
	match kind:
		"projectileLaunched":
			return _translate_launched(event, context)
		"projectileHit":
			return _translate_hit(event, context)
		"projectileMiss":
			return _translate_miss(event, context)
		_:
			return []


## 翻译投射物发射事件
func _translate_launched(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	
	var projectile_id := get_string_field(event, "projectileId")
	var source_actor_id := get_string_field(event, "source_actor_id")
	var target_actor_id := get_string_field(event, "target_actor_id")
	var speed := get_float_field(event, "speed", 20.0)
	# 优先使用 visualType（表演层视觉类型），否则使用 projectileType（逻辑层行为类型）
	var visual_type_str := get_string_field(event, "visualType", "")
	if visual_type_str.is_empty():
		visual_type_str = get_string_field(event, "projectileType", "energy")
	
	# 获取起始位置（优先使用 actor 位置，因为事件中的位置可能是 hex 坐标）
	var start_position := Vector3.ZERO
	if source_actor_id != "":
		start_position = context.get_actor_position(source_actor_id)
	if start_position == Vector3.ZERO:
		start_position = _get_position_from_event(event, "startPosition", context)
	
	# 获取目标位置（优先使用 actor 位置）
	var target_position := Vector3.ZERO
	if target_actor_id != "":
		target_position = context.get_actor_position(target_actor_id)
	if target_position == Vector3.ZERO:
		target_position = _get_position_from_event(event, "targetPosition", context)
	
	# 计算飞行时间（最小 300ms，确保投射物可见）
	var raw_duration := FrontendProjectileAction.calculate_duration(start_position, target_position, speed)
	var duration := maxf(raw_duration, 300.0)  # 最小 300ms
	
	# 解析投射物类型
	var projectile_type := _parse_projectile_type(visual_type_str)
	var projectile_color := _get_projectile_color(visual_type_str)
	
	var actions: Array[FrontendVisualAction] = []
	
	# 创建投射物飞行动作
	var projectile_action := FrontendProjectileAction.new(
		projectile_id,
		source_actor_id,
		start_position,
		target_position,
		duration,
		target_actor_id,
		projectile_type,
		projectile_color,
		config.projectile_size,
		speed
	)
	actions.append(projectile_action)
	
	return actions


## 翻译投射物命中事件
func _translate_hit(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	
	var target_actor_id := get_string_field(event, "target_actor_id")
	var hit_position := _get_position_from_event(event, "hitPosition", context)
	if hit_position == Vector3.ZERO and target_actor_id != "":
		hit_position = context.get_actor_position(target_actor_id)
	
	var actions: Array[FrontendVisualAction] = []
	
	# 命中闪白特效
	if target_actor_id != "":
		var hit_flash := FrontendProceduralVFXAction.new(
			FrontendProceduralVFXAction.EffectType.HIT_FLASH,
			config.projectile_hit_vfx_duration,
			target_actor_id
		)
		actions.append(hit_flash)
	
	return actions


## 翻译投射物未命中事件
func _translate_miss(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	# 未命中时可以添加消散特效，暂时不做处理
	return []


## 从事件中获取 Vector3 位置
func _get_position_from_event(event: Dictionary, field: String, _context: FrontendVisualizerContext) -> Vector3:
	var pos_data: Variant = event.get(field, null)
	if pos_data == null:
		return Vector3.ZERO
	
	# 支持 Vector3 格式 {"x": float, "y": float, "z": float}
	if pos_data is Dictionary:
		var pos_dict := pos_data as Dictionary
		return Vector3(
			pos_dict.get("x", 0.0) as float,
			pos_dict.get("y", 0.0) as float,
			pos_dict.get("z", 0.0) as float
		)
	
	# 支持 Array 格式 [x, y, z]
	if pos_data is Array:
		var pos_arr := pos_data as Array
		return Vector3(
			pos_arr[0] if pos_arr.size() > 0 else 0.0,
			pos_arr[1] if pos_arr.size() > 1 else 0.0,
			pos_arr[2] if pos_arr.size() > 2 else 0.0
		)
	
	# 直接是 Vector3
	if pos_data is Vector3:
		return pos_data as Vector3
	
	return Vector3.ZERO


## 解析投射物类型字符串
func _parse_projectile_type(type_str: String) -> FrontendProjectileAction.ProjectileType:
	match type_str.to_lower():
		"arrow":
			return FrontendProjectileAction.ProjectileType.ARROW
		"fireball":
			return FrontendProjectileAction.ProjectileType.FIREBALL
		_:
			return FrontendProjectileAction.ProjectileType.ENERGY


## 根据类型获取投射物颜色
func _get_projectile_color(type_str: String) -> Color:
	match type_str.to_lower():
		"arrow":
			return Color(0.6, 0.4, 0.2)  # 棕色
		"fireball":
			return Color(1.0, 0.4, 0.1)  # 橙红色
		"ice":
			return Color(0.3, 0.7, 1.0)  # 冰蓝色
		"lightning":
			return Color(1.0, 1.0, 0.3)  # 黄色
		_:
			return Color(0.3, 0.7, 1.0)  # 默认蓝色
