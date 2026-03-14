## BattleReplayScene - 战斗回放主场景
##
## 管理整个战斗回放的 3D 场景，包含：
## - BattleDirector（回放控制）
## - 单位管理
## - 相机控制
## - UI 控制
class_name FrontendBattleReplayScene
extends Node3D


# ========== 导出属性 ==========

## 单位视图场景（可选，如果不设置则使用默认）
@export var unit_view_scene: PackedScene


# ========== 节点引用 ==========

var _director: FrontendBattleDirector
var _units_root: Node3D
var _effects_root: Node3D
var _camera_rig: LomoCameraRig
var _ui_layer: CanvasLayer
var _hex_grid_renderer: GridMapRenderer3D

## 单位视图 Map（actor_id -> UnitView）
var _unit_views: Dictionary = {}

## 攻击特效视图 Map（vfx_id -> AttackVFXView）
var _attack_vfx_views: Dictionary = {}

## 投射物视图 Map（projectile_id -> ProjectileView）
var _projectile_views: Dictionary = {}

## 六边形网格世界模型（用于渲染）
var _hex_world: GridMapModel

## 位置格式配置（type -> format）
var _position_formats: Dictionary = {}


# ========== 初始化 ==========

func _ready() -> void:
	_setup_scene_structure()
	_setup_camera()
	_setup_lighting()
	_setup_hex_grid_renderer()


## 设置场景结构
func _setup_scene_structure() -> void:
	# 创建 BattleDirector
	_director = FrontendBattleDirector.new()
	_director.name = "BattleDirector"
	add_child(_director)
	
	# 连接信号
	_director.actor_state_changed.connect(_on_actor_state_changed)
	_director.floating_text_created.connect(_on_floating_text_created)
	_director.actor_died.connect(_on_actor_died)
	_director.frame_changed.connect(_on_frame_changed)
	_director.playback_ended.connect(_on_playback_ended)
	_director.attack_vfx_created.connect(_on_attack_vfx_created)
	_director.attack_vfx_updated.connect(_on_attack_vfx_updated)
	_director.attack_vfx_removed.connect(_on_attack_vfx_removed)
	_director.projectile_created.connect(_on_projectile_created)
	_director.projectile_updated.connect(_on_projectile_updated)
	_director.projectile_removed.connect(_on_projectile_removed)
	
	# 创建单位根节点
	_units_root = Node3D.new()
	_units_root.name = "UnitsRoot"
	add_child(_units_root)
	
	# 创建特效根节点
	_effects_root = Node3D.new()
	_effects_root.name = "EffectsRoot"
	add_child(_effects_root)
	
	# 创建 UI 层
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	add_child(_ui_layer)


func _exit_tree() -> void:
	# 断开 Director 信号连接
	if _director:
		_director.actor_state_changed.disconnect(_on_actor_state_changed)
		_director.floating_text_created.disconnect(_on_floating_text_created)
		_director.actor_died.disconnect(_on_actor_died)
		_director.frame_changed.disconnect(_on_frame_changed)
		_director.playback_ended.disconnect(_on_playback_ended)
		_director.attack_vfx_created.disconnect(_on_attack_vfx_created)
		_director.attack_vfx_updated.disconnect(_on_attack_vfx_updated)
		_director.attack_vfx_removed.disconnect(_on_attack_vfx_removed)
		_director.projectile_created.disconnect(_on_projectile_created)
		_director.projectile_updated.disconnect(_on_projectile_updated)
		_director.projectile_removed.disconnect(_on_projectile_removed)


## 设置相机（使用 LomoCameraRig）
func _setup_camera() -> void:
	var camera_scene := preload("res://addons/lomolib/camera/lomo_camera_rig.tscn")
	_camera_rig = camera_scene.instantiate() as LomoCameraRig
	_camera_rig.name = "CameraRig"
	
	# 配置相机参数（适合战斗场景）
	_camera_rig.default_arm_length = 20.0
	_camera_rig.min_zoom = 8.0
	_camera_rig.max_zoom = 40.0
	_camera_rig.default_pitch = -50.0
	_camera_rig.move_speed = 15.0
	
	add_child(_camera_rig)
	_camera_rig.make_current()


## 设置光照
func _setup_lighting() -> void:
	# 方向光
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "DirectionalLight"
	dir_light.position = Vector3(5, 10, 5)
	dir_light.rotation_degrees = Vector3(-45, 45, 0)
	dir_light.light_energy = 1.0
	dir_light.shadow_enabled = true
	add_child(dir_light)
	
	# 环境光
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	world_env.environment = env
	add_child(world_env)


## 设置六边形网格渲染器
func _setup_hex_grid_renderer() -> void:
	_hex_grid_renderer = GridMapRenderer3D.new()
	_hex_grid_renderer.name = "GridMapRenderer"
	# 配置渲染器颜色
	_hex_grid_renderer.grid_color = Color(0.4, 0.45, 0.5, 0.8)
	_hex_grid_renderer.highlight_color = Color.YELLOW
	_hex_grid_renderer.fill_color = Color(0.2, 0.6, 1.0, 0.2)
	add_child(_hex_grid_renderer)


## 从回放数据设置六边形网格
func _setup_hex_grid_from_replay(record: ReplayData.BattleRecord) -> void:
	var grid_config: GridMapConfig
	if record.map_config.is_empty():
		print("[BattleReplayScene] No mapConfig in replay data, using default grid")
		grid_config = GridMapConfig.new()
		grid_config.grid_type = GridMapConfig.GridType.HEX
		grid_config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		grid_config.rows = 9
		grid_config.columns = 9
		grid_config.size = 10.0
		grid_config.orientation = GridMapConfig.Orientation.FLAT
	else:
		print("[BattleReplayScene] Setting up hex grid: %s" % record.map_config)
		grid_config = GridMapConfig.from_dict(record.map_config)
		grid_config.grid_type = GridMapConfig.GridType.HEX
		grid_config.origin = Vector2.ZERO
	
	# 创建 GridMapModel 并初始化
	_hex_world = GridMapModel.new()
	_hex_world.initialize(grid_config)
	
	# 设置渲染器的数据模型并渲染
	_hex_grid_renderer.set_model(_hex_world)
	_hex_grid_renderer.render_grid()


# ========== 公共方法 ==========

## 加载并播放回放
func load_and_play(record: ReplayData.BattleRecord) -> void:
	load_replay(record)
	_director.play()


## 加载回放（不自动播放）
func load_replay(record: ReplayData.BattleRecord) -> void:
	# 读取 positionFormats 配置
	_position_formats = record.configs.get("positionFormats", {})
	
	_director.load_replay(record)
	_setup_hex_grid_from_replay(record)
	_spawn_units(record)
	_clear_effects()


## 播放
func play() -> void:
	_director.play()


## 暂停
func pause() -> void:
	_director.pause()


## 切换播放/暂停
func toggle() -> void:
	_director.toggle()


## 重置
func reset() -> void:
	_director.reset()
	_reset_unit_views()
	_clear_effects()


## 设置播放速度
func set_speed(new_speed: float) -> void:
	_director.set_speed(new_speed)


## 获取 Director
func get_director() -> FrontendBattleDirector:
	return _director


# ========== 内部方法 ==========

## 生成单位
func _spawn_units(record: ReplayData.BattleRecord) -> void:
	# 清除现有单位
	for child: Node in _units_root.get_children():
		child.queue_free()
	_unit_views.clear()
	
	print("[BattleReplayScene] Spawning %d units" % record.initial_actors.size())
	
	for actor_init: ReplayData.ActorInitData in record.initial_actors:
		if actor_init.id.is_empty():
			continue
		
		# 创建单位视图
		var unit_view: FrontendUnitView
		if unit_view_scene:
			unit_view = unit_view_scene.instantiate() as FrontendUnitView
		else:
			unit_view = FrontendUnitView.new()
		
		unit_view.name = actor_init.id  # 设置节点名称 (修复 M2)
		_units_root.add_child(unit_view)
		_unit_views[actor_init.id] = unit_view
		
		# 初始化单位
		var max_hp: float = actor_init.attributes.get("maxHp", actor_init.attributes.get("max_hp", 100.0)) as float
		var current_hp: float = actor_init.attributes.get("hp", 100.0) as float
		
		unit_view.initialize(actor_init.id, actor_init.display_name, actor_init.team, max_hp, current_hp)
		
		# 设置位置
		var position_arr: Array = actor_init.position  # 元素可能是 int/float
		var world_pos := _extract_world_position(position_arr, actor_init.type)
		unit_view.set_world_position(world_pos)


## 从位置数组提取世界坐标
## 根据 positionFormats 配置解释 position 数组的含义
## position_arr 元素可能是 int/float，保持无类型
func _extract_world_position(position_arr: Array, actor_type: String) -> Vector3:
	if position_arr.is_empty():
		return Vector3.ZERO
	
	# 查找该类型的位置格式，默认为 "world"
	var format: String = _position_formats.get(actor_type, "world")
	
	if format == "hex" and _hex_world != null:
		# position 是 [q, r, z]，转换为世界坐标
		var q := int(position_arr[0]) if position_arr.size() > 0 else 0
		var r := int(position_arr[1]) if position_arr.size() > 1 else 0
		var hex_coord := HexCoord.new(q, r)
		var pixel: Vector2 = _hex_world.coord_to_world(hex_coord)
		return Vector3(pixel.x, 0.0, pixel.y)
	else:
		# position 是 [x, y, z] 世界坐标，直接使用
		return Vector3(
			position_arr[0] if position_arr.size() > 0 else 0.0,
			position_arr[1] if position_arr.size() > 1 else 0.0,
			position_arr[2] if position_arr.size() > 2 else 0.0
		)


## 重置单位视图
func _reset_unit_views() -> void:
	var actors := _director.get_actors_snapshot()
	
	for actor_id: String in actors.keys():
		var actor_state: FrontendActorRenderState = actors[actor_id]
		if _unit_views.has(actor_id):
			var unit_view: FrontendUnitView = _unit_views[actor_id]
			unit_view.update_state(actor_state)
			unit_view.visible = true
			unit_view.scale = Vector3.ONE


## 清理所有特效节点
func _clear_effects() -> void:
	for child: Node in _effects_root.get_children():
		child.queue_free()


## 更新所有单位位置（移动动画期间单位位置平滑更新）
func _update_all_unit_positions() -> void:
	for actor_id: String in _unit_views.keys():
		var unit_view: FrontendUnitView = _unit_views[actor_id]
		var world_pos := _director.get_actor_world_position(actor_id)
		unit_view.set_world_position(world_pos)


# ========== 信号处理 ==========

func _on_actor_state_changed(actor_id: String, state: FrontendActorRenderState) -> void:
	if _unit_views.has(actor_id):
		var unit_view: FrontendUnitView = _unit_views[actor_id]
		unit_view.update_state(state)
		
		# 更新位置
		var world_pos := _director.get_actor_world_position(actor_id)
		unit_view.set_world_position(world_pos)


func _on_floating_text_created(data: FrontendRenderData.FloatingText) -> void:
	var floating_text := FrontendFloatingTextView.new()
	_effects_root.add_child(floating_text)
	
	floating_text.initialize(data.text, data.color, data.position, data.style, data.duration)


func _on_actor_died(actor_id: String) -> void:
	print("[BattleReplayScene] Actor died: %s" % actor_id)


func _on_frame_changed(_current_frame: int, _total_frames: int) -> void:
	# 可以在这里更新 UI
	pass


func _on_playback_ended() -> void:
	print("[BattleReplayScene] Playback ended")


# ========== 攻击特效信号处理 ==========

func _on_attack_vfx_created(data: FrontendRenderData.AttackVfx) -> void:
	if data.id.is_empty():
		return
	
	var vfx_view := FrontendAttackVFXView.new()
	vfx_view.name = "AttackVFX_" + data.id
	_effects_root.add_child(vfx_view)
	_attack_vfx_views[data.id] = vfx_view
	
	# 初始化特效
	vfx_view.global_position = data.source_position
	vfx_view.initialize(data.id, data.vfx_type, data.vfx_color, data.direction, data.distance, data.is_critical)


func _on_attack_vfx_updated(vfx_id: String, _progress: float, scale_factor: float, alpha: float) -> void:
	if _attack_vfx_views.has(vfx_id):
		var vfx_view: FrontendAttackVFXView = _attack_vfx_views[vfx_id]
		vfx_view.update_progress(_progress, scale_factor, alpha)


func _on_attack_vfx_removed(vfx_id: String) -> void:
	if _attack_vfx_views.has(vfx_id):
		var vfx_view: FrontendAttackVFXView = _attack_vfx_views[vfx_id]
		vfx_view.cleanup()
		_attack_vfx_views.erase(vfx_id)


# ========== 投射物信号处理 ==========

func _on_projectile_created(data: FrontendRenderData.Projectile) -> void:
	if data.id.is_empty():
		return
	
	var projectile_view := FrontendProjectileView.new()
	projectile_view.name = "Projectile_" + data.id
	_effects_root.add_child(projectile_view)
	_projectile_views[data.id] = projectile_view
	
	# 初始化投射物
	projectile_view.global_position = data.start_position
	projectile_view.initialize(data.id, data.projectile_type, data.projectile_color, data.projectile_size, data.direction)


func _on_projectile_updated(projectile_id: String, pos: Vector3, dir: Vector3) -> void:
	if _projectile_views.has(projectile_id):
		var projectile_view: FrontendProjectileView = _projectile_views[projectile_id]
		projectile_view.update_position(pos)
		projectile_view.set_direction(dir)


func _on_projectile_removed(projectile_id: String) -> void:
	if _projectile_views.has(projectile_id):
		var projectile_view: FrontendProjectileView = _projectile_views[projectile_id]
		projectile_view.cleanup()
		_projectile_views.erase(projectile_id)


func _process(_delta: float) -> void:
	_update_all_unit_positions()
	
	# 震屏效果（通过 LomoCameraRig 的位置偏移实现）
	var shake_offset := _director.get_screen_shake_offset()
	if shake_offset != Vector2.ZERO:
		var base_pos := _camera_rig.global_position
		_camera_rig.global_position = base_pos + Vector3(shake_offset.x * 0.1, 0, shake_offset.y * 0.1)


## 获取相机 Rig（供外部访问）
func get_camera_rig() -> LomoCameraRig:
	return _camera_rig
