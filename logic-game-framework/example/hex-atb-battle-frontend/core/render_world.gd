## RenderWorld - 渲染状态管理
##
## 管理战斗回放的渲染状态，将 VisualAction 应用到状态上。
##
## 职责分离：
## - ActionScheduler 管理"时序"（什么时候执行）
## - RenderWorld 管理"状态"（当前值是什么）
class_name FrontendRenderWorld
extends RefCounted


# ========== 信号 ==========

## 角色状态变化信号
signal actor_state_changed(actor_id: String, state: FrontendActorRenderState)

## 飘字创建信号
signal floating_text_created(data: FrontendRenderData.FloatingText)

## 角色死亡信号
signal actor_died(actor_id: String)

## 攻击特效创建信号
signal attack_vfx_created(data: FrontendRenderData.AttackVfx)

## 攻击特效更新信号
signal attack_vfx_updated(vfx_id: String, progress: float, scale_factor: float, alpha: float)

## 攻击特效移除信号
signal attack_vfx_removed(vfx_id: String)

## 投射物创建信号
signal projectile_created(data: FrontendRenderData.Projectile)

## 投射物更新信号
signal projectile_updated(projectile_id: String, position: Vector3, direction: Vector3)

## 投射物移除信号
signal projectile_removed(projectile_id: String)


# ========== 内部状态 ==========

## Actor 状态 Map（actor_id -> FrontendActorRenderState）
var _actors: Dictionary = {}

## 插值位置 Map（actor_id -> Vector2）用于移动动画
var _interpolated_positions: Dictionary = {}

## 活跃的飘字
var _floating_texts: Array[FrontendRenderData.FloatingText] = []

## 活跃的程序化特效
var _procedural_effects: Array[FrontendRenderData.ProceduralEffect] = []

## 活跃的攻击特效
var _attack_vfx: Dictionary = {}  # vfx_id -> FrontendRenderData.AttackVfx

## 活跃的投射物
var _projectiles: Dictionary = {}  # projectile_id -> FrontendRenderData.Projectile

## 震屏状态
var _screen_shake: FrontendRenderData.ScreenShake = FrontendRenderData.ScreenShake.new()

## 六边形网格布局
var _layout: GridLayout

## 动画配置
var _animation_config: FrontendAnimationConfig

## 位置格式配置（type -> format）
var _position_formats: Dictionary = {}

## 实例 ID 计数器
var _next_instance_id: int = 0

## 内部世界时间（毫秒）
var _world_time_ms: int = 0

## 脏标记 Map（actor_id -> bool）用于批量触发信号 (修复 M1)
var _dirty_actors: Dictionary = {}


# ========== 构造函数 ==========

func _init(
	animation_config: FrontendAnimationConfig = null
) -> void:
	_animation_config = animation_config if animation_config != null else FrontendAnimationConfig.create_default()


# ========== 初始化 ==========

## 从回放数据初始化角色状态
func initialize_from_replay(record: ReplayData.BattleRecord) -> void:
	_actors.clear()
	_interpolated_positions.clear()
	_floating_texts.clear()
	_procedural_effects.clear()
	_screen_shake = FrontendRenderData.ScreenShake.new()
	
	# 从 configs 读取 positionFormats
	_position_formats = record.configs.get("positionFormats", {})
	
	# 从 mapConfig 创建 GridLayout
	if not record.map_config.is_empty():
		var grid_config := GridMapConfig.from_dict(record.map_config)
		_layout = GridLayout.new(
			grid_config.grid_type,
			grid_config.size,
			Vector2.ZERO,
			grid_config.orientation,
			Vector2.ONE
		)
	
	for actor_init: ReplayData.ActorInitData in record.initial_actors:
		_initialize_actor_from_init_data(actor_init)
	
	# 初始化完成后触发状态同步 (修复 M3)
	for actor_id in _actors.keys():
		actor_state_changed.emit(actor_id, _actors[actor_id])


## 初始化单个角色
func _initialize_actor_from_init_data(actor_init: ReplayData.ActorInitData) -> void:
	if actor_init.id.is_empty():
		return
	
	var position_arr: Array = actor_init.position  # 元素可能是 int/float，保持无类型
	var hex_pos := _extract_hex_position(position_arr, actor_init.type)
	
	var actor_state := FrontendActorRenderState.new()
	actor_state.id = actor_init.id
	actor_state.type = actor_init.type
	actor_state.display_name = actor_init.display_name
	actor_state.team = actor_init.team
	actor_state.position = hex_pos
	actor_state.visual_hp = actor_init.attributes.get("hp", 100.0) as float
	actor_state.max_hp = actor_init.attributes.get("maxHp", actor_init.attributes.get("max_hp", 100.0)) as float
	actor_state.is_alive = true
	actor_state.flash_progress = 0.0
	actor_state.tint_color = Color.WHITE
	
	_actors[actor_init.id] = actor_state
	_interpolated_positions[actor_init.id] = Vector2(hex_pos.q, hex_pos.r)


## 从位置数组提取六边形坐标
## 根据 positionFormats 配置解释 position 数组的含义
func _extract_hex_position(position_arr: Array, actor_type: String) -> HexCoord:
	if position_arr.is_empty():
		return HexCoord.zero()
	
	# 查找该类型的位置格式，默认为 "world"
	var format: String = _position_formats.get(actor_type, "world")
	
	if format == "hex":
		# position 是 [q, r, z]，直接取 q, r
		var q := int(position_arr[0]) if position_arr.size() > 0 else 0
		var r := int(position_arr[1]) if position_arr.size() > 1 else 0
		return HexCoord.new(q, r)
	else:
		# position 是 [x, y, z] 世界坐标，需要转换为 hex
		var world_pos := Vector3(
			position_arr[0] if position_arr.size() > 0 else 0.0,
			position_arr[1] if position_arr.size() > 1 else 0.0,
			position_arr[2] if position_arr.size() > 2 else 0.0
		)
		var axial: Vector2i = _layout.pixel_to_coord(Vector2(world_pos.x, world_pos.z))
		return HexCoord.from_axial(axial)


# ========== 动作应用 ==========

## 应用活跃动作到状态
func apply_actions(active_actions: Array[FrontendActionScheduler.ActiveAction]) -> void:
	for active_action: FrontendActionScheduler.ActiveAction in active_actions:
		# 跳过延迟中的动作
		if active_action.is_delaying:
			continue
		_apply_action(active_action)


## 应用单个动作
func _apply_action(active_action: FrontendActionScheduler.ActiveAction) -> void:
	var action: FrontendVisualAction = active_action.action
	var progress: float = active_action.progress
	
	match action.type:
		FrontendVisualAction.ActionType.MOVE:
			_apply_move_action(action, progress)
		FrontendVisualAction.ActionType.UPDATE_HP:
			_apply_update_hp_action(action, progress)
		FrontendVisualAction.ActionType.FLOATING_TEXT:
			_apply_floating_text_action(action, active_action.id)
		FrontendVisualAction.ActionType.PROCEDURAL_VFX:
			_apply_procedural_vfx_action(action, active_action.id, progress)
		FrontendVisualAction.ActionType.DEATH:
			_apply_death_action(action, progress)
		FrontendVisualAction.ActionType.ATTACK_VFX:
			_apply_attack_vfx_action(action, active_action.id, progress)
		FrontendVisualAction.ActionType.PROJECTILE:
			_apply_projectile_action(action, active_action.id, progress)


## 应用移动动作
func _apply_move_action(action: FrontendMoveAction, progress: float) -> void:
	var interpolated_pos := action.get_interpolated_hex(progress)
	_interpolated_positions[action.actor_id] = interpolated_pos
	
	# 动画完成时更新 Actor 的实际位置
	if progress >= 1.0:
		var actor: FrontendActorRenderState = _actors.get(action.actor_id)
		if actor != null:
			actor.position = action.to_hex
			actor_state_changed.emit(action.actor_id, actor)


## 应用血条更新动作
func _apply_update_hp_action(action: FrontendUpdateHPAction, progress: float) -> void:
	var actor: FrontendActorRenderState = _actors.get(action.actor_id)
	if actor == null:
		print("[Frontend:RenderWorld] ⚠️ UpdateHP 找不到 actor: %s" % action.actor_id)
		return
	
	# 线性插值 HP
	actor.visual_hp = action.get_interpolated_hp(progress)
	
	# 动画完成时确保精确值
	if progress >= 1.0:
		actor.visual_hp = action.to_hp
		actor.is_alive = action.to_hp > 0
		print("[Frontend:RenderWorld] HP更新完成: actor=%s hp=%.0f->%.0f alive=%s" % [
			action.actor_id, action.from_hp, action.to_hp, actor.is_alive
		])
	
	_dirty_actors[action.actor_id] = true


## 应用飘字动作
func _apply_floating_text_action(action: FrontendFloatingTextAction, action_id: String) -> void:
	# 检查是否已存在（避免重复添加）
	for text in _floating_texts:
		if text.id == action_id:
			return
	
	print("[Frontend:RenderWorld] 飘字: actor=%s text='%s' pos=%s" % [
		action.actor_id, action.text, action.position
	])
	
	var text_data := FrontendRenderData.FloatingText.new()
	text_data.id = action_id
	text_data.actor_id = action.actor_id
	text_data.text = action.text
	text_data.color = action.color
	text_data.position = action.position
	text_data.start_time = _world_time_ms
	text_data.duration = action.duration
	text_data.style = action.style
	
	_floating_texts.append(text_data)
	floating_text_created.emit(text_data)


## 应用程序化特效动作
func _apply_procedural_vfx_action(action: FrontendProceduralVFXAction, action_id: String, progress: float) -> void:
	match action.effect:
		FrontendProceduralVFXAction.EffectType.HIT_FLASH:
			if not action.actor_id.is_empty():
				var actor: FrontendActorRenderState = _actors.get(action.actor_id)
				if actor != null:
					actor.flash_progress = action.get_flash_intensity(progress)
					_dirty_actors[action.actor_id] = true
		
		FrontendProceduralVFXAction.EffectType.SHAKE:
			var offset := action.get_shake_offset(progress)
			_screen_shake = FrontendRenderData.ScreenShake.new()
			_screen_shake.offset_x = offset.x
			_screen_shake.offset_y = offset.y
		
		FrontendProceduralVFXAction.EffectType.COLOR_TINT:
			if not action.actor_id.is_empty():
				var actor: FrontendActorRenderState = _actors.get(action.actor_id)
				if actor != null:
					actor.tint_color = action.tint_color if progress < 1.0 else Color.WHITE
					_dirty_actors[action.actor_id] = true
	
	# 添加到程序化特效列表（避免重复）
	for effect in _procedural_effects:
		if effect.id == action_id:
			return
	
	var effect_data := FrontendRenderData.ProceduralEffect.new()
	effect_data.id = action_id
	effect_data.effect = action.effect
	effect_data.actor_id = action.actor_id
	effect_data.start_time = _world_time_ms
	effect_data.duration = action.duration
	effect_data.intensity = action.intensity
	effect_data.color = action.tint_color
	_procedural_effects.append(effect_data)


## 应用死亡动作
func _apply_death_action(action: FrontendDeathAction, progress: float) -> void:
	var actor: FrontendActorRenderState = _actors.get(action.actor_id)
	if actor == null:
		print("[Frontend:RenderWorld] ⚠️ Death 找不到 actor: %s" % action.actor_id)
		return
	
	actor.is_alive = false
	actor.visual_hp = 0.0
	actor.death_progress = progress
	
	if progress >= 1.0:
		print("[Frontend:RenderWorld] 死亡动画完成: actor=%s" % action.actor_id)
		actor_died.emit(action.actor_id)
	
	actor_state_changed.emit(action.actor_id, actor)


## 应用攻击特效动作
func _apply_attack_vfx_action(action: FrontendAttackVFXAction, action_id: String, progress: float) -> void:
	# 首次创建
	if not _attack_vfx.has(action_id):
		var vfx_data := FrontendRenderData.AttackVfx.new()
		vfx_data.id = action_id
		vfx_data.source_actor_id = action.source_actor_id
		vfx_data.target_actor_id = action.target_actor_id
		vfx_data.source_position = action.source_position
		vfx_data.target_position = action.target_position
		vfx_data.vfx_type = action.vfx_type
		vfx_data.vfx_color = action.vfx_color
		vfx_data.is_critical = action.is_critical
		vfx_data.direction = action.get_direction()
		vfx_data.distance = action.get_distance()
		vfx_data.start_time = _world_time_ms
		vfx_data.duration = action.duration
		_attack_vfx[action_id] = vfx_data
		attack_vfx_created.emit(vfx_data)
	
	# 更新进度
	var scale_factor := action.get_vfx_scale(progress)
	var alpha := action.get_vfx_alpha(progress)
	attack_vfx_updated.emit(action_id, progress, scale_factor, alpha)
	
	# 完成时移除
	if progress >= 1.0:
		_attack_vfx.erase(action_id)
		attack_vfx_removed.emit(action_id)


## 应用投射物动作
func _apply_projectile_action(action: FrontendProjectileAction, action_id: String, progress: float) -> void:
	# 首次创建
	if not _projectiles.has(action_id):
		var projectile_data := FrontendRenderData.Projectile.new()
		projectile_data.id = action_id
		projectile_data.projectile_id = action.projectile_id
		projectile_data.source_actor_id = action.source_actor_id
		projectile_data.target_actor_id = action.target_actor_id
		projectile_data.start_position = action.start_position
		projectile_data.target_position = action.target_position
		projectile_data.projectile_type = action.projectile_type
		projectile_data.projectile_color = action.projectile_color
		projectile_data.projectile_size = action.projectile_size
		projectile_data.direction = action.get_direction()
		projectile_data.start_time = _world_time_ms
		projectile_data.duration = action.duration
		_projectiles[action_id] = projectile_data
		projectile_created.emit(projectile_data)
	
	# 更新位置
	var current_position := action.get_current_position(progress)
	var direction := action.get_direction()
	projectile_updated.emit(action_id, current_position, direction)
	
	# 完成时移除
	if progress >= 1.0:
		_projectiles.erase(action_id)
		projectile_removed.emit(action_id)


# ========== 清理 ==========

## 清理过期效果
func cleanup(now_ms: int) -> void:
	# 清理过期飘字
	_floating_texts = _floating_texts.filter(func(text: FrontendRenderData.FloatingText) -> bool:
		return now_ms - text.start_time < text.duration
	)
	
	# 清理过期程序化特效
	_procedural_effects = _procedural_effects.filter(func(effect: FrontendRenderData.ProceduralEffect) -> bool:
		return now_ms - effect.start_time < effect.duration
	)
	
	# 清理震屏
	var has_active_shake := _procedural_effects.any(func(e: FrontendRenderData.ProceduralEffect) -> bool:
		return e.effect == FrontendProceduralVFXAction.EffectType.SHAKE
	)
	if not has_active_shake:
		_screen_shake = FrontendRenderData.ScreenShake.new()
	
	# 清理 Actor 的临时效果
	for actor_id: String in _actors.keys():
		var actor: FrontendActorRenderState = _actors[actor_id]
		
		var has_active_flash := _procedural_effects.any(func(e: FrontendRenderData.ProceduralEffect) -> bool:
			return e.effect == FrontendProceduralVFXAction.EffectType.HIT_FLASH and e.actor_id == actor_id
		)
		if not has_active_flash:
			actor.flash_progress = 0.0
		
		var has_active_tint := _procedural_effects.any(func(e: FrontendRenderData.ProceduralEffect) -> bool:
			return e.effect == FrontendProceduralVFXAction.EffectType.COLOR_TINT and e.actor_id == actor_id
		)
		if not has_active_tint:
			actor.tint_color = Color.WHITE


# ========== 状态获取 ==========

## 获取 Actor 状态的深拷贝 Map（actor_id -> FrontendActorRenderState）
func get_actors_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for actor_id: String in _actors.keys():
		var actor: FrontendActorRenderState = _actors[actor_id]
		snapshot[actor_id] = actor.duplicate()
	return snapshot


## 创建 VisualizerContext（只读视图）
func as_context() -> FrontendVisualizerContext:
	return FrontendVisualizerContext.new(
		_actors,
		_interpolated_positions,
		_animation_config,
		_layout
	)


## 获取角色世界坐标
func get_actor_world_position(actor_id: String) -> Vector3:
	if _interpolated_positions.has(actor_id):
		var pos: Vector2 = _interpolated_positions[actor_id]
		# hex→pixel 是线性变换，对浮点坐标直接用两端 lerp 即可精确插值
		var q0 := floori(pos.x)
		var r0 := floori(pos.y)
		var frac_q := pos.x - q0
		var frac_r := pos.y - r0
		# 沿 q 轴插值，再沿 r 轴插值（双线性，对线性函数精确）
		var p00 := _layout.coord_to_pixel(Vector2i(q0, r0))
		var p10 := _layout.coord_to_pixel(Vector2i(q0 + 1, r0))
		var p01 := _layout.coord_to_pixel(Vector2i(q0, r0 + 1))
		var pixel := p00 + (p10 - p00) * frac_q + (p01 - p00) * frac_r
		return Vector3(pixel.x, 0.0, pixel.y)
	
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor == null:
		return Vector3.ZERO
	
	var pixel := _layout.coord_to_pixel(actor.position.to_axial())
	return Vector3(pixel.x, 0.0, pixel.y)


## 获取震屏偏移
func get_screen_shake_offset() -> Vector2:
	return _screen_shake.to_vector2()


# ========== 重置 ==========

## 重置到初始状态
func reset_to(record: ReplayData.BattleRecord) -> void:
	_world_time_ms = 0
	initialize_from_replay(record)


## 推进内部世界时间
func advance_time(delta_ms: int) -> void:
	_world_time_ms += delta_ms


## 获取内部世界时间
func get_world_time() -> int:
	return _world_time_ms


## 批量触发脏标记的 Actor 状态变化信号
func flush_dirty_actors() -> void:
	for actor_id: String in _dirty_actors.keys():
		if _actors.has(actor_id):
			actor_state_changed.emit(actor_id, _actors[actor_id])
	_dirty_actors.clear()


# ========== 直接状态更新 ==========

## 直接更新 Actor HP（无动画）
func set_actor_hp(actor_id: String, hp: float) -> void:
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor != null:
		actor.visual_hp = hp
		actor.is_alive = hp > 0
		actor_state_changed.emit(actor_id, actor)


## 直接更新 Actor 位置（无动画）
func set_actor_position(actor_id: String, hex: HexCoord) -> void:
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor != null:
		actor.position = hex
		_interpolated_positions[actor_id] = Vector2(hex.q, hex.r)
		actor_state_changed.emit(actor_id, actor)


## 标记 Actor 死亡
func set_actor_dead(actor_id: String) -> void:
	var actor: FrontendActorRenderState = _actors.get(actor_id)
	if actor != null:
		actor.is_alive = false
		actor.visual_hp = 0.0
		actor_state_changed.emit(actor_id, actor)
		actor_died.emit(actor_id)
