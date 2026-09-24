## ProjectileVisualizer - 投射物事件转换器
##
## 将投射物相关事件翻译为视觉动作：
## - projectile_launched: 创建投射物飞行动画
## - projectile_hit: 命中特效
## - projectile_miss: 消散特效
class_name FrontendProjectileVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "ProjectileVisualizer"


## 检查是否为投射物事件
func can_handle(event: Dictionary) -> bool:
	var kind := get_event_kind(event)
	return kind == ProjectileEvents.PROJECTILE_LAUNCHED_EVENT or kind == ProjectileEvents.PROJECTILE_HIT_EVENT or kind == ProjectileEvents.PROJECTILE_MISS_EVENT


## 翻译投射物事件为视觉动作
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var kind := get_event_kind(event)
	
	match kind:
		ProjectileEvents.PROJECTILE_LAUNCHED_EVENT:
			return _translate_launched(event, context)
		ProjectileEvents.PROJECTILE_HIT_EVENT:
			return _translate_hit(event, context)
		ProjectileEvents.PROJECTILE_MISS_EVENT:
			return _translate_miss(event, context)
		_:
			return []


## 翻译投射物发射事件
func _translate_launched(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	
	var projectile_id := get_string_field(event, "projectile_id")
	var source_actor_id := get_string_field(event, "source_actor_id")
	var target_actor_id := get_string_field(event, "target_actor_id")
	var speed := get_float_field(event, "speed", 20.0)
	# 优先使用 visual_type（表演层视觉类型），否则使用 projectile_type（逻辑层行为类型）
	var visual_type_str := get_string_field(event, "visual_type", "")
	if visual_type_str.is_empty():
		visual_type_str = get_string_field(event, "projectile_type", "energy")
	
	# 起止位置:账本上有这个 actor 就取它的逻辑坐标(含在飞插值),否则用事件里逻辑层给的位置
	var start_position := _resolve_position(event, "start_position", source_actor_id, context)
	var target_position := _resolve_position(event, "target_position", target_actor_id, context)

	# 飞行时间 = 逻辑平面距离 / 速度(hex 逻辑层的投射物本来就在 (q, r) 平面上飞,speed 也是这个平面的);
	# 最小 300ms,确保投射物可见
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


## 位置优先取账本(actor 的在飞插值),账本没有这个 actor 再读事件字段(逻辑层给的逻辑平面坐标)
func _resolve_position(event: Dictionary, field: String, actor_id: String, context: FrontendVisualizerContext) -> Vector2:
	if actor_id != "" and context.has_actor(actor_id):
		return context.get_actor_position(actor_id)
	return _get_position_from_event(event, field)


## 从事件字段读逻辑平面坐标:{"x", "y"} / [x, y, ...] / 二维或三维向量都只取前两分量
## (hex 逻辑层把投射物位置打包成三维向量 (q, r, 0))
func _get_position_from_event(event: Dictionary, field: String) -> Vector2:
	var pos_data: Variant = event.get(field, null)
	if pos_data == null:
		return Vector2.ZERO

	if pos_data is Dictionary:
		var pos_dict := pos_data as Dictionary
		return Vector2(
			pos_dict.get("x", 0.0) as float,
			pos_dict.get("y", 0.0) as float
		)

	if pos_data is Array:
		var pos_arr := pos_data as Array
		return Vector2(
			pos_arr[0] if pos_arr.size() > 0 else 0.0,
			pos_arr[1] if pos_arr.size() > 1 else 0.0
		)

	var value_type := typeof(pos_data)
	if value_type == TYPE_VECTOR2 or value_type == TYPE_VECTOR3:
		return Vector2(pos_data.x, pos_data.y)

	return Vector2.ZERO


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
