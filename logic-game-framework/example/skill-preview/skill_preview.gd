## SkillPreview - 技能预览开发者工具
##
## 打开 skill_preview.tscn F6:
## - 左侧面板: Preset / Map / Skill / Actors (unified) / Target / Controls
## - 3D viewport: 编辑模式下 WorldView 响应式渲染 actors 摆位, 右键点格子 /
##   actor 弹 PopupMenu
## - 点 START: world.queue_preview + world.start_battle -> SkillPreviewProcedure
##   -> battle_finished -> FrontendBattleAnimator.play 在已有 unit view 上叠加
##   VFX / 飘字 / 死亡动画
##
## 响应式架构 (阶段 3):
##   - 一个 skill_preview session 一个常驻 SkillPreviewWorldGI
##   - 一个常驻 FrontendWorldView bind 到 world, 订阅 mutation signal 管 view 生命周期
##   - 一个常驻 FrontendBattleAnimator 播放 battle_finished 产出的 timeline
##   - 编辑态增删 actor 走 world.add_actor / remove_actor, WorldView 自动刷新
##   - 战斗期间 damage_utils 会 remove_actor 死者, 对应 view 被 WorldView 响应式回收
##     (死亡动画缺憾留给阶段 4/5 的 ReplayPlayer 方案根治)
##
## 数据模型:
##   actors: Array[Dictionary] —— 每条 {role: "caster"|"dummy", team: "A"|"B",
##           class, pos: [q,r], hp, atk}。role=="caster" 唯一且必是 team A。
##   map:    {radius: int, orientation: "pointy"|"flat", hex_size: float}
##   skill:  {active_id: String, passive_ids: Array[String]}
##   target: {mode: "auto"|"enemy_index"|"ally_index"|"fixed_pos", index, pos}
##   controls: {max_ticks, speed}
extends Node


const PRESET_DIR := "user://skill_preview_presets"
const BUILTIN_PRESET_DIR := "res://addons/logic-game-framework/example/skill-preview/presets"

const CLASS_NAMES: Array[String] = [
	"WARRIOR", "PRIEST", "ARCHER", "MAGE", "BERSERKER", "ASSASSIN",
]

const TARGET_MODE_NAMES: Array[String] = [
	"auto", "enemy_index", "ally_index", "fixed_pos",
]

const TICK_INTERVAL_MS := 100
const INSPECTOR_MARGIN := 12.0
const INSPECTOR_WIDTH := 348.0
const INSPECTOR_PLAYBACK_WIDTH := 320.0
const WORKSPACE_GAP := 12.0
const DRAWER_COLLAPSED_HEIGHT := 44.0
const DRAWER_EXPANDED_HEIGHT := 280.0


# ========== Scene 节点 (unique names) ==========

@onready var _left_panel: PanelContainer = get_node("ConfigUI/Root/LeftPanel") as PanelContainer
@onready var _inspector_tabs: TabContainer = %InspectorTabs

@onready var _preset_load_option: OptionButton = %PresetLoadOption
@onready var _preset_save_button: Button = %PresetSaveButton

@onready var _map_radius_input: SpinBox = %MapRadiusInput
@onready var _map_orientation_option: OptionButton = %MapOrientationOption
@onready var _map_hex_size_input: SpinBox = %MapHexSizeInput

@onready var _skill_active_option: OptionButton = %SkillActiveOption
@onready var _passives_container: VBoxContainer = %PassivesContainer

@onready var _actors_container: VBoxContainer = %ActorsContainer
@onready var _actor_add_enemy_button: Button = %ActorAddEnemyButton
@onready var _actor_add_ally_button: Button = %ActorAddAllyButton

@onready var _target_mode_option: OptionButton = %TargetModeOption
@onready var _target_index_input: SpinBox = %TargetIndexInput
@onready var _target_q_input: SpinBox = %TargetQInput
@onready var _target_r_input: SpinBox = %TargetRInput
@onready var _target_index_row: HBoxContainer = %TargetIndexRow
@onready var _target_pos_row: HBoxContainer = %TargetPosRow

@onready var _max_ticks_input: SpinBox = %MaxTicksInput
@onready var _speed_input: SpinBox = %SpeedInput

@onready var _start_button: Button = %StartButton
@onready var _reset_button: Button = %ResetButton
@onready var _status_label: Label = %StatusLabel

@onready var _console_panel: PanelContainer = %BottomPanel
@onready var _console_toggle_button: Button = %ConsoleToggleButton
@onready var _console_summary_label: Label = %ConsoleSummaryLabel
@onready var _console_log: RichTextLabel = %ConsoleLog

@onready var _hex_popup: PopupMenu = %HexPopupMenu


# ========== 状态 ==========

## 数据模型: caster 永远在 [0] 位置,其后跟随 dummies
var _actors: Array[Dictionary] = []

## 常驻响应式栈
var _world: SkillPreviewWorldGI
var _world_view: FrontendWorldView
var _animator: FrontendBattleAnimator
var _camera_rig: LomoCameraRig
var _player_controller: LomoPlayerController

## true: 战斗 procedure 运行中 / animator 播放中, 禁止编辑 UI 修改 world
var _is_playing: bool = false
var _playback_mode: bool = false
var _console_expanded: bool = false
var _selected_actor_idx: int = 0
var _actors_ui_rebuild_queued: bool = false

## Passive 被动 Checkbox 缓存,顺序对齐 HexBattleSkillIndex.passives()
var _passive_checks: Array[CheckBox] = []

## PopupMenu 上下文(右键点的格子 / actor idx)
var _popup_hex: HexCoord = null
var _popup_actor_idx: int = -1

## 约定字段 -> actor_id 映射: 编辑态按数据模型 idx 分配稳定 id(caster / ally_N / enemy_N)。
## 每次 _reset_world_to_model 重新生成并写入 add_actor 前的 _display_name 提示;
## 真实 actor id 由 WorldGI.add_actor 分配(形如 world_N:Character_M), 通过
## display_name 反查的 _role_id_to_actor_id 维护供 queue_preview 使用。
##
## 增量编辑路径(_remove_actor_at / class 切换)需要从 _actors[idx] 反查 actor_id,
## 但 _role_id_for(idx) 在 idx 变化后会重新编号(删 enemy_2 后 enemy_3 → enemy_2),
## 用 role_id 反查会拿到错位的 actor。因此并行维护 _actor_ids: Array[String] 与
## _actors 同 idx 对齐, 保存每条数据模型项当前对应的 world actor_id。
## 插入/删除走数组同步操作,_role_id_to_actor_id 在每次结构变化后整体重建。
var _role_id_to_actor_id: Dictionary[String, String] = {}
var _actor_ids: Array[String] = []

## 最近一次战斗的总帧数, 从 timeline.meta.totalFrames 缓存。
## 不能从 _world.get_active_battle() 读 —— battle_finished emit 之前
## _active_battle 已经被 null 掉了 (见 world_gameplay_instance.gd:103-113)。
var _last_battle_frames: int = 0

## Map spinbox value_changed debounce —— 拖动时合并多次 rebuild。
var _map_change_timer: Timer = null


# ========== 生命周期 ==========

func _ready() -> void:
	_apply_clay_theme()
	_update_workspace_layout()
	get_viewport().size_changed.connect(_update_workspace_layout)
	GameWorld.init()
	_init_world_stack()
	_init_player_controller()
	_init_ui_static_options()
	_init_signals()
	_init_default_actors()
	_refresh_preset_list()
	_reset_world_to_model()
	_apply_setup_inspector_layout()
	_set_console_expanded(false)
	_set_status("Ready — 右键点格子编辑摆位")
	_log_welcome()


func _exit_tree() -> void:
	GameWorld.destroy()


func _process(delta: float) -> void:
	_process_stage_camera_input(delta)


func _init_world_stack() -> void:
	_world = SkillPreviewWorldGI.new()
	GameWorld.create_instance(func() -> GameplayInstance: return _world)
	_world.start()
	_world.battle_finished.connect(_on_battle_finished)

	_setup_camera_and_env()

	_world_view = FrontendWorldView.new()
	_world_view.name = "WorldView"
	add_child(_world_view)
	_world_view.bind_world(_world)

	_animator = FrontendBattleAnimator.new()
	_animator.name = "BattleAnimator"
	add_child(_animator)
	_animator.playback_ended.connect(_on_playback_ended)

	_add_pick_ground()


## LomoPlayerController 的 raycast 需要 Y≈0 平面有 collider 才能命中 "ground"。
## frontend 的 hex 渲染没自带 collision, 没这个 pad ground_clicked 永远不 fire。
func _add_pick_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "PickGround"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 0.1, 1000.0)
	col.shape = shape
	col.position = Vector3(0.0, -0.05, 0.0)
	body.add_child(col)
	add_child(body)


## 相机 / 光 / 环境 —— 原先委托 FrontendBattleReplayScene 做, 切到 WorldView 后
## 自己承担。参数沿袭 replay_scene._setup_camera/_setup_lighting 保证视觉一致。
func _setup_camera_and_env() -> void:
	var camera_scene := preload("res://addons/lomolib/camera/lomo_camera_rig.tscn")
	_camera_rig = camera_scene.instantiate() as LomoCameraRig
	_camera_rig.name = "CameraRig"
	_camera_rig.default_arm_length = 24.0
	_camera_rig.min_zoom = 8.0
	_camera_rig.max_zoom = 48.0
	_camera_rig.default_pitch = -50.0
	_camera_rig.move_speed = 15.0
	add_child(_camera_rig)
	_camera_rig.make_current()
	_frame_stage_camera()

	var dir_light := DirectionalLight3D.new()
	dir_light.name = "DirectionalLight"
	dir_light.position = Vector3(5, 10, 5)
	dir_light.rotation_degrees = Vector3(-45, 45, 0)
	dir_light.light_energy = 1.0
	dir_light.shadow_enabled = true
	add_child(dir_light)

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


func _init_player_controller() -> void:
	_player_controller = LomoPlayerController.new()
	_player_controller.name = "PlayerController"
	_player_controller.auto_handle_camera_input = false
	add_child(_player_controller)
	if _camera_rig != null:
		_player_controller.use_camera_rig(_camera_rig)
	# 右键交互走自己的 _input, 不依赖 LomoPlayerController 的 click emission。


func _init_ui_static_options() -> void:
	_preset_load_option.fit_to_longest_item = false
	_map_orientation_option.fit_to_longest_item = false
	_skill_active_option.fit_to_longest_item = false
	_target_mode_option.fit_to_longest_item = false

	# Map
	_map_orientation_option.clear()
	_map_orientation_option.add_item("pointy")
	_map_orientation_option.add_item("flat")
	_map_orientation_option.selected = 1  # flat 与 main.tscn 默认一致

	# Skill active
	_skill_active_option.clear()
	for cfg in HexBattleSkillIndex.actives():
		_skill_active_option.add_item("%s (%s)" % [cfg.display_name, cfg.config_id])

	# Passives
	for child in _passives_container.get_children():
		child.queue_free()
	_passive_checks.clear()
	for cfg in HexBattleSkillIndex.passives():
		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [cfg.display_name, cfg.config_id]
		_passives_container.add_child(cb)
		_passive_checks.append(cb)
		cb.toggled.connect(_on_passive_toggled.bind(cb))
		_apply_passive_style(cb, false)

	# Target mode
	_target_mode_option.clear()
	for m in TARGET_MODE_NAMES:
		_target_mode_option.add_item(m)
	_target_mode_option.selected = 0
	_update_target_visibility()

	# Defaults
	_map_radius_input.value = 5
	_map_hex_size_input.value = 1.0
	_max_ticks_input.value = 500
	_speed_input.value = 1.0


func _init_signals() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_console_toggle_button.pressed.connect(_on_console_toggle_pressed)
	_actor_add_enemy_button.pressed.connect(func() -> void: _add_actor_at_next_free("B"))
	_actor_add_ally_button.pressed.connect(func() -> void: _add_actor_at_next_free("A"))
	_target_mode_option.item_selected.connect(_on_target_mode_changed)
	_preset_save_button.pressed.connect(_on_preset_save_pressed)
	_preset_load_option.item_selected.connect(_on_preset_load_selected)
	_speed_input.value_changed.connect(_on_speed_changed)
	# Map spinbox 走增量 grid mutation: configure_grid emit grid_configured -> view
	# 重渲网格 + 遍历 actor emit actor_position_changed 让 unit view 按新 hex_size
	# 平滑滑到新位置。拖动时每 0.1 step 触发一次会抖, 150ms debounce 合并成松手一次。
	_map_change_timer = Timer.new()
	_map_change_timer.one_shot = true
	_map_change_timer.wait_time = 0.15
	_map_change_timer.timeout.connect(_apply_grid_change)
	add_child(_map_change_timer)
	_map_radius_input.value_changed.connect(func(_v: float) -> void: _map_change_timer.start())
	_map_orientation_option.item_selected.connect(func(_i: int) -> void: _map_change_timer.start())
	_map_hex_size_input.value_changed.connect(func(_v: float) -> void: _map_change_timer.start())
	_hex_popup.id_pressed.connect(_on_popup_id_pressed)
	_hex_popup.window_input.connect(_on_hex_popup_window_input)


func _apply_setup_inspector_layout() -> void:
	_playback_mode = false
	if _inspector_tabs != null:
		_inspector_tabs.current_tab = 0
	_update_workspace_layout()


func _apply_playback_inspector_layout() -> void:
	_playback_mode = true
	if _inspector_tabs != null:
		_inspector_tabs.current_tab = 0
	_update_workspace_layout()


func _update_workspace_layout() -> void:
	if _left_panel == null or _console_panel == null:
		return
	var inspector_width := _current_inspector_width()
	_left_panel.custom_minimum_size = Vector2(0.0, 0.0)
	_left_panel.size = Vector2(inspector_width, get_viewport().get_visible_rect().size.y - INSPECTOR_MARGIN * 2.0)
	if _inspector_tabs != null:
		_inspector_tabs.custom_minimum_size = Vector2(0.0, 0.0)
	_left_panel.offset_left = INSPECTOR_MARGIN
	_left_panel.offset_top = INSPECTOR_MARGIN
	_left_panel.offset_right = INSPECTOR_MARGIN + inspector_width
	_left_panel.offset_bottom = -INSPECTOR_MARGIN

	_console_panel.offset_left = INSPECTOR_MARGIN + inspector_width + WORKSPACE_GAP
	_console_panel.offset_right = -INSPECTOR_MARGIN
	_console_panel.offset_bottom = -INSPECTOR_MARGIN
	_console_panel.offset_top = -(_drawer_height() + INSPECTOR_MARGIN)
	_frame_stage_camera()


func _current_inspector_width() -> float:
	return INSPECTOR_PLAYBACK_WIDTH if _playback_mode else INSPECTOR_WIDTH


func _drawer_height() -> float:
	return DRAWER_EXPANDED_HEIGHT if _console_expanded else DRAWER_COLLAPSED_HEIGHT


func _frame_stage_camera() -> void:
	if _camera_rig == null:
		return
	_camera_rig.teleport_to(_stage_camera_focus())
	_camera_rig.set_zoom(_camera_rig.default_arm_length)


func _stage_camera_focus() -> Vector3:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector3.ZERO
	var stage_left := INSPECTOR_MARGIN + _current_inspector_width() + WORKSPACE_GAP
	var stage_right := maxf(stage_left + 1.0, viewport_size.x - INSPECTOR_MARGIN)
	var stage_bottom := maxf(INSPECTOR_MARGIN + 1.0, viewport_size.y - _drawer_height() - INSPECTOR_MARGIN)
	var stage_center := Vector2((stage_left + stage_right) * 0.5, (INSPECTOR_MARGIN + stage_bottom) * 0.5)
	var cam := _camera_rig.get_camera()
	if cam == null:
		return Vector3.ZERO
	var stage_ground := _ground_point_at_screen(cam, stage_center)
	return _camera_rig.global_position - stage_ground


func _ground_point_at_screen(cam: Camera3D, screen_pos: Vector2) -> Vector3:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector3.ZERO
	var distance := -from.y / dir.y
	return from + dir * distance


func _process_stage_camera_input(_delta: float) -> void:
	if _camera_rig == null:
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	var move_input := Vector2.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_input.y += 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_input.y -= 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_input.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_input.x += 1.0
	if move_input != Vector2.ZERO:
		_camera_rig.move(move_input.normalized())
	if Input.is_key_pressed(KEY_Q):
		_camera_rig.rotate_camera(-1.0)
	if Input.is_key_pressed(KEY_E):
		_camera_rig.rotate_camera(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _camera_rig == null:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _is_mouse_in_stage_area():
				_camera_rig.zoom(1.0)
				get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _is_mouse_in_stage_area():
				_camera_rig.zoom(-1.0)
				get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_SPACE and get_viewport().gui_get_focus_owner() == null:
			_frame_stage_camera()
			get_viewport().set_input_as_handled()


func _is_mouse_in_stage_area() -> bool:
	if _is_mouse_over_blocking_ui():
		return false
	var mouse_pos := get_viewport().get_mouse_position()
	var stage_left := INSPECTOR_MARGIN + _current_inspector_width() + WORKSPACE_GAP
	return mouse_pos.x >= stage_left and mouse_pos.x <= get_viewport().get_visible_rect().size.x


func _is_mouse_over_blocking_ui() -> bool:
	return _is_mouse_inside_control(_left_panel) or _is_mouse_inside_control(_console_panel)


func _is_mouse_inside_control(control: Control) -> bool:
	if control == null or not control.visible:
		return false
	return control.get_global_rect().has_point(get_viewport().get_mouse_position())


func _init_default_actors() -> void:
	_actors = [
		{"role": "caster", "team": "A", "class": "WARRIOR", "pos": [0, 0], "hp": 0.0, "atk": 0.0},
		{"role": "dummy",  "team": "B", "class": "WARRIOR", "pos": [2, 0], "hp": 100.0, "atk": 0.0},
	]
	_rebuild_actors_ui()


# ========== 数据模型操作 ==========

func _add_actor(role: String, team: String, cls: String, q: int, r: int) -> void:
	var coord := _nearest_free_coord_for(q, r, team, -1)
	if not coord.is_valid():
		_set_status("No free hex available")
		return
	_actors.append({
		"role": role, "team": team, "class": cls,
		"pos": [coord.q, coord.r], "hp": 100.0, "atk": 0.0,
	})
	_selected_actor_idx = _actors.size() - 1
	_rebuild_actors_ui()
	if _is_playing:
		return
	# 增量 spawn: 不动其它 actor view,新 view 直接落在 _actors 末尾。
	_spawn_one_actor(_actors.size() - 1)


func _add_actor_at_next_free(team: String) -> void:
	var start_q := 2 if team == "B" else -1
	_add_actor("dummy", team, "WARRIOR", start_q, 0)


func _nearest_free_coord_for(start_q: int, start_r: int, team: String, actor_idx: int) -> HexCoord:
	var preferred_direction := 1 if team == "B" else -1
	var start_coord := HexCoord.new(start_q, start_r)
	if _can_place_actor_at_for(start_coord, actor_idx):
		return start_coord
	for distance in range(1, 12):
		var candidates: Array[HexCoord] = [
			HexCoord.new(start_q + distance * preferred_direction, start_r),
			HexCoord.new(start_q, start_r + distance),
			HexCoord.new(start_q, start_r - distance),
			HexCoord.new(start_q + distance * preferred_direction, start_r - distance),
			HexCoord.new(start_q - distance * preferred_direction, start_r + distance),
			HexCoord.new(start_q - distance * preferred_direction, start_r),
		]
		for coord in candidates:
			if _can_place_actor_at_for(coord, actor_idx):
				return coord
	return HexCoord.invalid()


func _can_place_actor_at_for(coord: HexCoord, actor_idx: int) -> bool:
	if coord == null or not coord.is_valid():
		return false
	if UGridMap.model != null and not UGridMap.model.has_tile(coord):
		return false
	var occupant_idx := _find_actor_idx_at(coord.q, coord.r)
	return occupant_idx == -1 or occupant_idx == actor_idx


func _remove_actor_at(idx: int) -> void:
	if idx <= 0 or idx >= _actors.size():
		return  # caster (idx 0) 不可删

	if not _is_playing and idx < _actor_ids.size():
		# 增量 remove: HexWorldGameplayInstance.remove_actor 内部会处理 grid occupant
		# 清理并 emit actor_removed → WorldView 销毁对应 unit view。其它 view 不动。
		var actor_id := _actor_ids[idx]
		if actor_id != "":
			_world.remove_actor(actor_id)
		_actor_ids.remove_at(idx)
	_actors.remove_at(idx)
	if _selected_actor_idx > idx:
		_selected_actor_idx -= 1
	elif _selected_actor_idx == idx:
		_selected_actor_idx = min(idx, _actors.size() - 1)
	_selected_actor_idx = clampi(_selected_actor_idx, 0, max(0, _actors.size() - 1))
	_rebuild_role_id_mapping()
	_rebuild_actors_ui()


func _find_actor_idx_at(q: int, r: int) -> int:
	for i in _actors.size():
		var pos: Array = _actors[i]["pos"]
		if int(pos[0]) == q and int(pos[1]) == r:
			return i
	return -1


func _move_caster_to(q: int, r: int) -> void:
	var coord := _nearest_free_coord_for(q, r, _actors[0]["team"] as String, 0)
	if not coord.is_valid():
		_set_status("No free hex available")
		return
	_actors[0]["pos"] = [coord.q, coord.r]
	_selected_actor_idx = 0
	_rebuild_actors_ui()
	if _is_playing:
		return
	_apply_actor_position_change(0, coord.q, coord.r)


# ========== UI: Actors 表 ==========

func _rebuild_actors_ui() -> void:
	_actors_ui_rebuild_queued = false
	for child in _actors_container.get_children():
		child.queue_free()
	if _actors.is_empty():
		_selected_actor_idx = 0
		_sync_target_index_bounds()
		return
	_selected_actor_idx = clampi(_selected_actor_idx, 0, _actors.size() - 1)
	for i in _actors.size():
		_actors_container.add_child(_build_actor_card(i))
	_actors_container.add_child(HSeparator.new())
	_actors_container.add_child(_build_actor_detail_panel(_selected_actor_idx))
	_sync_target_index_bounds()


func _build_actor_card(idx: int) -> Button:
	var data: Dictionary = _actors[idx]
	var card := Button.new()
	card.text = _actor_summary(idx)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.tooltip_text = "Edit %s" % _actor_role_label(data)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(func() -> void: _select_actor(idx))
	card.add_theme_stylebox_override("normal", _outlined_sb(Color("FFFFFF"), Color("C8D1DF"), 6, 10, 7))
	card.add_theme_stylebox_override("hover", _outlined_sb(Color("EAF2FF"), Color("7AA7F7"), 6, 10, 7))
	card.add_theme_stylebox_override("pressed", _outlined_sb(Color("CFE1FF"), Color("2563EB"), 6, 10, 7))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.add_theme_color_override("font_color", CLAY_TEXT)
	card.add_theme_color_override("font_hover_color", CLAY_TEXT)
	if idx == _selected_actor_idx:
		card.add_theme_stylebox_override("normal", _outlined_sb(Color("CFE1FF"), Color("2563EB"), 6, 10, 7))
		card.add_theme_stylebox_override("hover", _outlined_sb(Color("BDD5FF"), Color("1D4ED8"), 6, 10, 7))
		card.add_theme_color_override("font_color", START_PRESSED)
	return card


func _select_actor(idx: int) -> void:
	_selected_actor_idx = clampi(idx, 0, _actors.size() - 1)
	_rebuild_actors_ui()


func _queue_actors_ui_rebuild() -> void:
	if _actors_ui_rebuild_queued:
		return
	_actors_ui_rebuild_queued = true
	call_deferred("_rebuild_actors_ui")


func _refresh_actor_card_summary(actor_idx: int) -> void:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return
	if actor_idx >= _actors_container.get_child_count():
		return
	var card := _actors_container.get_child(actor_idx) as Button
	if card != null:
		card.text = _actor_summary(actor_idx)


func _actor_summary(idx: int) -> String:
	var data: Dictionary = _actors[idx]
	var pos: Array = data["pos"]
	return "%s  %s  (%d,%d)  HP %.0f" % [
		_actor_role_label(data),
		data["class"],
		int(pos[0]),
		int(pos[1]),
		float(data["hp"]),
	]


func _actor_role_label(data: Dictionary) -> String:
	if data["role"] == "caster":
		return "Caster"
	return "Ally" if data["team"] == "A" else "Enemy"


func _build_actor_detail_panel(idx: int) -> PanelContainer:
	var data: Dictionary = _actors[idx]
	var panel := PanelContainer.new()
	var panel_sb := _clay_sb(Color("F8FAFC"), 8, 10, 10, 0, 0)
	panel_sb.border_color = Color("D8DEE8")
	panel_sb.border_width_left = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", panel_sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Edit %s" % _actor_role_label(data)
	title.add_theme_color_override(
		"font_color",
		Color("1F7A4D") if data["role"] == "caster" else Color("2F6FED") if data["team"] == "A" else Color("B23B3B")
	)
	title.add_theme_font_override("font", _clay_font_bold())
	box.add_child(title)

	var class_opt := OptionButton.new()
	class_opt.fit_to_longest_item = false
	for cls in CLASS_NAMES:
		class_opt.add_item(cls)
	class_opt.selected = max(0, CLASS_NAMES.find(data["class"]))
	class_opt.tooltip_text = "Actor class"
	class_opt.item_selected.connect(func(i: int) -> void:
		_actors[idx]["class"] = CLASS_NAMES[i]
		if not _is_playing:
			_apply_actor_class_change(idx)
		_refresh_actor_card_summary(idx)
	)
	box.add_child(_build_actor_detail_field("Class", class_opt))

	var pos: Array = data["pos"]
	box.add_child(_build_actor_detail_field("Q", _make_actor_spin(idx, "q", pos[0], -20, 20, false, 0)))
	box.add_child(_build_actor_detail_field("R", _make_actor_spin(idx, "r", pos[1], -20, 20, false, 0)))
	box.add_child(_build_actor_detail_field("HP", _make_actor_spin(idx, "hp", data["hp"], 0, 9999, true, 0)))

	if data["role"] != "caster":
		var rm := Button.new()
		rm.text = "Remove Actor"
		rm.tooltip_text = "Remove actor"
		rm.pressed.connect(func() -> void: _remove_actor_at(idx))
		box.add_child(rm)
	return panel


func _build_actor_detail_field(label_text: String, editor: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(72, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)
	return row


func _make_actor_spin(
	actor_idx: int, field: String, value: float,
	min_v: int, max_v: int, allow_float: bool = false, width: int = 60
) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 0.1 if allow_float else 1
	s.value = value
	s.custom_minimum_size = Vector2(width, 0)
	s.tooltip_text = field.to_upper()
	s.value_changed.connect(func(v: float) -> void:
		match field:
			"q", "r":
				var pos: Array = _actors[actor_idx]["pos"]
				var next_q := int(v) if field == "q" else int(pos[0])
				var next_r := int(v) if field == "r" else int(pos[1])
				var actor_data: Dictionary = _actors[actor_idx]
				var coord := _nearest_free_coord_for(next_q, next_r, actor_data["team"] as String, actor_idx)
				if not coord.is_valid():
					_set_status("No free hex available")
					_queue_actors_ui_rebuild()
					return
				_actors[actor_idx]["pos"] = [coord.q, coord.r]
				if not _is_playing:
					_apply_actor_position_change(actor_idx, coord.q, coord.r)
				if coord.q != next_q or coord.r != next_r:
					_set_status("Position occupied — moved to nearest free hex")
					_queue_actors_ui_rebuild()
				else:
					_refresh_actor_card_summary(actor_idx)
			"hp":
				_actors[actor_idx]["hp"] = v
				if not _is_playing:
					_apply_actor_hp_change(actor_idx, v)
				_refresh_actor_card_summary(actor_idx)
	)
	return s


# ========== World Reset (按数据模型重置到默认状态) ==========

## 把 world 重置成 _actors 数据模型对应的初始状态: reset → configure_grid →
## add_actor × N + place_occupant。每一步都走 WorldGI 的显式 mutation API,
## 触发 signal -> FrontendWorldView 自动维护 unit view 生命周期
## (无 destructive load_replay 或 _spawn_units 调用)。
##
## ⚠ 这是 destructive 操作, 仅用于"明确意图的场景重置", 合法调用点只有 3 处:
##   1. _ready 初始化 (首次建立 world)
##   2. _on_reset_pressed (用户主动按 RESET 按钮)
##   3. _on_preset_load_selected (切换 preset = 切场景)
##
## 战斗回放结束 (_on_playback_ended) 不再自动 reset —— 用户可能想观察战斗结果或
## 重播, 状态恢复改由 RESET 按钮主动触发。START 按钮在回放结束后保持 disabled
## 强制走 RESET → START 流程, 避免基于残破状态再次战斗。
##
## 编辑期面板 / 右键 / spinbox 全部走 event→update 的增量 mutation
## (_add_actor / _remove_actor_at / _apply_actor_position_change /
## _apply_actor_hp_change / _apply_actor_class_change / _apply_grid_change),
## 不走 reset。增量路径不重建已有 view, 避免"加一个 actor 所有棋子从 (0,0) 滑回"
## 的视觉抖动。
##
## 战斗播放期间 (_is_playing=true) 不 reset, 避免打断正在播的 animator。
func _reset_world_to_model() -> void:
	if _is_playing:
		return
	_reset_world_to_model_unguarded()


func _reset_world_to_model_unguarded() -> void:
	_world.reset()
	_role_id_to_actor_id.clear()
	_actor_ids.clear()

	_world.configure_grid(_build_grid_config())
	if _sanitize_actor_positions():
		_queue_actors_ui_rebuild()
	var collision_detector := MobaCollisionDetector.new()
	_world.add_system(ProjectileSystem.new(collision_detector, GameWorld.event_collector, false))
	HexBattleAllSkills.register_all_timelines()

	for i in _actors.size():
		_spawn_one_actor(i)


func _sanitize_actor_positions() -> bool:
	var changed := false
	for i in _actors.size():
		var data: Dictionary = _actors[i]
		var pos: Array = data["pos"]
		var coord := HexCoord.new(int(pos[0]), int(pos[1]))
		if _can_place_actor_at_for(coord, i):
			continue
		var adjusted := _nearest_free_coord_for(coord.q, coord.r, data["team"] as String, i)
		if not adjusted.is_valid():
			continue
		_actors[i]["pos"] = [adjusted.q, adjusted.r]
		changed = true
	return changed


## 把 _actors[idx] 这一条数据模型 commit 到 world: 创建 CharacterActor + hydrate 字段
## + add_actor + place_occupant + 同步 _actor_ids/_role_id_to_actor_id 索引。
##
## 调用前 _world.grid 必须已 configure(_reset_world_to_model_unguarded 在循环前已 configure;
## 增量 _add_actor 路径依赖 _ready 时跑过的初始 rebuild)。idx 必须等于 _actors.size()-1
## 或 _actor_ids.size()(即 append 到末尾) —— 中间插入未支持(会破坏 _actor_ids 顺序)。
func _spawn_one_actor(idx: int) -> void:
	var a: Dictionary = _actors[idx]
	var role_id := _role_id_for(idx)
	var team_int: int = 0 if a["team"] == "A" else 1
	var max_hp: float = 100.0 if a["hp"] <= 0.0 else a["hp"]

	var cchar := CharacterActor.new(HexBattleClassConfig.string_to_class(a["class"] as String))
	cchar._display_name = role_id
	cchar.set_team_id(team_int)
	cchar.attribute_set.set_max_hp_base(max_hp)
	cchar.attribute_set.set_hp_base(max_hp)
	if a.get("atk", 0.0) > 0.0:
		cchar.attribute_set.set_atk_base(float(a["atk"]))

	var pos: Array = a["pos"]
	var coord := HexCoord.new(int(pos[0]), int(pos[1]))
	# WorldView._hydrate_from_actor 在 actor_added 信号里一次性读 team / hp / hex_position,
	# core 层尚未 emit actor_position_changed (见 CHANGELOG 待处理 / D5)。
	# 因此所有可视字段必须在 add_actor 之前写入,否则 view 会停在默认 (team=0, pos=0,0)。
	cchar.hex_position = coord.duplicate()

	_world.add_actor(cchar)

	if _world.grid != null and _world.grid.has_tile(coord):
		_world.grid.place_occupant(coord, cchar)

	_role_id_to_actor_id[role_id] = cchar.get_id()
	if idx >= _actor_ids.size():
		_actor_ids.resize(idx + 1)
	_actor_ids[idx] = cchar.get_id()


## 删 idx 后 enemy_3 → enemy_2 这种重编号会让 _role_id_to_actor_id 出现 stale entry,
## 同时 class 切换走 remove + add 会复用同一 idx 但 actor_id 变。这里用 _actor_ids
## 作真理来源整体重建 dict, 调方负责调用前先把 _actor_ids 维护好。
func _rebuild_role_id_mapping() -> void:
	_role_id_to_actor_id.clear()
	for i in _actor_ids.size():
		var role_id := _role_id_for(i)
		_role_id_to_actor_id[role_id] = _actor_ids[i]


## 增量改 actor 坐标: 写 actor.hex_position + grid.move_occupant + 手动 emit
## actor_position_changed 触发 WorldView._on_actor_position_changed → view.set_world_position。
##
## 手动 emit 是兜底 —— core 层 actor_position_changed 还没有 emit 调用点
## (CHANGELOG 待处理 / D5 阶段 4 配移动动画一起补)。SkillPreview 编辑态绕过去,
## 等 core emit 就位后这里删掉手动 emit 即可。
func _apply_actor_position_change(idx: int, q: int, r: int) -> void:
	if idx >= _actor_ids.size():
		return
	var actor_id := _actor_ids[idx]
	var actor := _world.get_actor(actor_id) as CharacterActor
	if actor == null:
		return
	var old_coord: HexCoord = actor.hex_position
	var new_coord := HexCoord.new(q, r)
	if old_coord != null and old_coord.is_valid() and old_coord.equals(new_coord):
		return
	actor.hex_position = new_coord.duplicate()
	if _world.grid != null and _world.grid.has_tile(new_coord):
		if old_coord != null and old_coord.is_valid() and _world.grid.has_tile(old_coord):
			_world.grid.move_occupant(old_coord, new_coord)
		else:
			_world.grid.place_occupant(new_coord, actor)
	_world.actor_position_changed.emit(actor_id, old_coord, new_coord)


## 增量改 actor max_hp / current_hp: 写 attribute_set + 重新 hydrate unit view。
## view 没有专门的 update_max_hp API, 编辑态调 view.initialize 整体 reset 字段
## (actor_id / display_name / team 不变, 等价于只刷 hp)。
func _apply_actor_hp_change(idx: int, hp: float) -> void:
	if idx >= _actor_ids.size():
		return
	var actor_id := _actor_ids[idx]
	var actor := _world.get_actor(actor_id) as CharacterActor
	if actor == null or actor.attribute_set == null:
		return
	actor.attribute_set.set_max_hp_base(hp)
	actor.attribute_set.set_hp_base(hp)
	var view := _world_view.get_unit_view(actor_id)
	if view != null:
		view.initialize(actor_id, actor.get_display_name(), actor.get_team_id(), hp, hp)


## 增量改 actor class: CharacterActor class 是构造参数(影响 ability_set 默认 grant +
## attribute 默认值), 不可动态切。删旧 actor + 重 spawn 同 idx, 让 _spawn_one_actor
## 重新读 _actors[idx]["class"]。idx 不变 → role_id 不变, _spawn_one_actor 内部
## 自会覆盖 _role_id_to_actor_id[role_id] 为新 actor_id, 无需额外重建映射。
func _apply_actor_class_change(idx: int) -> void:
	if idx >= _actor_ids.size():
		return
	var actor_id := _actor_ids[idx]
	if actor_id != "":
		_world.remove_actor(actor_id)
	_actor_ids[idx] = ""
	_spawn_one_actor(idx)


## 增量改 grid 配置 (radius / orientation / hex_size): configure_grid 重建 model
## (UGridMap.configure 创建新 GridMapModel, 旧 occupant 数据全丢) -> emit
## grid_configured -> WorldView 重渲网格。然后遍历 _actor_ids 重新 place_occupant
## + 用同坐标 emit actor_position_changed 让 view 按新 hex_size 重算 world_position
## 平滑滑过去 —— actor 自身的 hex_position 不变, 只是世界投影改了。
##
## 边界: radius 改小后 actor coord 不在新网格内, 跳过 place_occupant 但仍 emit
## position_changed (coord_to_world 是纯数学, 不依赖 has_tile, view 仍能算位置)。
func _apply_grid_change() -> void:
	if _is_playing:
		return
	_world.configure_grid(_build_grid_config())
	for i in _actor_ids.size():
		var actor_id := _actor_ids[i]
		if actor_id == "":
			continue
		var actor := _world.get_actor(actor_id) as CharacterActor
		if actor == null:
			continue
		var coord: HexCoord = actor.hex_position
		if coord == null or not coord.is_valid():
			continue
		if _world.grid != null and _world.grid.has_tile(coord):
			_world.grid.place_occupant(coord, actor)
		_world.actor_position_changed.emit(actor_id, coord, coord)


## 数据模型 idx → 逻辑 role id (caster / ally_N / enemy_N)。
## role id 用于 target 解析和 queue_preview 的 caster_id / target_id。
func _role_id_for(idx: int) -> String:
	var a: Dictionary = _actors[idx]
	if a["role"] == "caster":
		return "caster"
	var n := 0
	for j in idx:
		var aj: Dictionary = _actors[j]
		if aj["role"] == "dummy" and aj["team"] == a["team"]:
			n += 1
	return ("ally_%d" if a["team"] == "A" else "enemy_%d") % n


func _build_grid_config() -> GridMapConfig:
	var cfg := GridMapConfig.new()
	cfg.grid_type = GridMapConfig.GridType.HEX
	cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	cfg.radius = int(_map_radius_input.value)
	cfg.orientation = (GridMapConfig.Orientation.FLAT
		if _map_orientation_option.selected == 1
		else GridMapConfig.Orientation.POINTY)
	cfg.size = _map_hex_size_input.value
	return cfg


# ========== 3D 右键交互 ==========

## 自己处理右键: mouse_pos → raycast → hex coord → popup。
## 用 _input 而非 _unhandled_input —— PopupMenu 是 subwindow,外点自动关闭时
## 会把那次 click consume 掉,_unhandled_input 收不到;_input 在输入链更靠前,
## popup 已开时也能先拿到 event 并手动 hide + 重弹。
func _input(event: InputEvent) -> void:
	if _is_playing:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	if _is_mouse_over_blocking_ui():
		return
	if _hex_popup.visible:
		_hex_popup.hide()
	if _camera_rig == null:
		_log("[color=red]no camera — cannot raycast[/color]")
		return
	var cam := _camera_rig.get_camera()
	if cam == null:
		_log("[color=red]no camera — cannot raycast[/color]")
		return
	var mouse_pos := cam.get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var to := from + dir * 1000.0
	var space := cam.get_world_3d().direct_space_state
	var ground_result := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1)
	)
	if ground_result.is_empty():
		return
	var world_pos: Vector3 = ground_result["position"]
	if UGridMap.model == null:
		_log("[color=red]UGridMap.model null — map not configured[/color]")
		return
	var coord := UGridMap.world_to_coord(Vector2(world_pos.x, world_pos.z))
	if not UGridMap.model.has_tile(coord):
		return
	_popup_hex = coord
	_popup_actor_idx = _find_actor_idx_at(coord.q, coord.r)
	_show_hex_popup()
	get_viewport().set_input_as_handled()


func _show_hex_popup() -> void:
	_hex_popup.clear()
	var q := _popup_hex.q
	var r := _popup_hex.r
	_hex_popup.add_separator("(%d, %d)" % [q, r])
	if _popup_actor_idx == 0:
		_hex_popup.add_item("Caster 位置", 100)
	elif _popup_actor_idx > 0:
		_hex_popup.add_item("🎯 设为 target (enemy_index/ally_index)", 10)
		_hex_popup.add_item("🗑  删除此 actor", 11)
	else:
		_hex_popup.add_item("⚔  加敌方 actor (team B)", 1)
		_hex_popup.add_item("💚 加友方 actor (team A)", 2)
		_hex_popup.add_item("🎯 移动 caster 到此", 3)
	_hex_popup.add_separator()
	_hex_popup.add_item("📍 设为 target (fixed_pos)", 20)
	var local_mouse := Vector2i(get_viewport().get_mouse_position())
	_hex_popup.popup_on_parent(Rect2i(local_mouse, Vector2i(1, 1)))


## PopupMenu 是 modal —— popup 已显示时用户右键另一个 hex, 该 InputEventMouseButton
## 会被 popup 自身截获(主场景 _input 收不到), 表现为"右键另一个 hex 没反应, 要再
## 点一次"。绕过办法: Window.window_input signal 把 popup 截获到的事件转发给我们,
## 这里检测右键 → 关旧 popup → 在新 hex 重弹。
##
## 左键 / ESC / 点菜单项的关闭路径不走这里 (popup 自身原生关闭流程处理),
## 因此不会引发"点菜单后误重弹"等副作用。
func _on_hex_popup_window_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	if _is_playing:
		return
	if _camera_rig == null:
		return
	var cam := _camera_rig.get_camera()
	if cam == null:
		return
	if UGridMap.model == null:
		return
	# Window.window_input 转发的 mouse position 是 popup 内部坐标。直接查全局
	# 鼠标位置 → 转主 viewport 坐标 → raycast 算 hex coord。
	var main_vp := get_viewport()
	var mouse_pos: Vector2 = main_vp.get_mouse_position()
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var to := from + dir * 1000.0
	var space := cam.get_world_3d().direct_space_state
	var ground_result := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1)
	)
	if ground_result.is_empty():
		return
	var world_pos: Vector3 = ground_result["position"]
	var coord := UGridMap.world_to_coord(Vector2(world_pos.x, world_pos.z))
	if not UGridMap.model.has_tile(coord):
		return
	# 同 hex 不重弹(用户右键当前 popup 所在 hex, 没意图)。
	if _popup_hex != null and _popup_hex.is_valid() and _popup_hex.equals(coord):
		_hex_popup.hide()
		return
	# 不同 hex: 关旧 popup, 在新 hex 重弹。
	_hex_popup.hide()
	_popup_hex = coord
	_popup_actor_idx = _find_actor_idx_at(coord.q, coord.r)
	# 等一帧让 hide 真正完成再 show, 避免 hide+show 同帧的潜在 race。
	call_deferred("_show_hex_popup")


func _on_popup_id_pressed(id: int) -> void:
	var q := _popup_hex.q
	var r := _popup_hex.r
	match id:
		1: _add_actor("dummy", "B", "WARRIOR", q, r)
		2: _add_actor("dummy", "A", "WARRIOR", q, r)
		3: _move_caster_to(q, r)
		10:
			var a: Dictionary = _actors[_popup_actor_idx]
			var team: String = a["team"]
			var idx_among_team := -1
			var count := 0
			for i in _actors.size():
				var ai: Dictionary = _actors[i]
				if ai["role"] == "dummy" and ai["team"] == team:
					if i == _popup_actor_idx:
						idx_among_team = count
						break
					count += 1
			_target_mode_option.selected = (2 if team == "A" else 1)  # ally_index=2, enemy_index=1
			_target_index_input.value = idx_among_team
			_update_target_visibility()
		11: _remove_actor_at(_popup_actor_idx)
		20:
			_target_mode_option.selected = 3  # fixed_pos
			_target_q_input.value = q
			_target_r_input.value = r
			_update_target_visibility()


# ========== Target UI ==========

func _on_target_mode_changed(_idx: int) -> void:
	_update_target_visibility()


func _update_target_visibility() -> void:
	var mode: String = TARGET_MODE_NAMES[_target_mode_option.selected]
	_target_index_row.visible = mode == "enemy_index" or mode == "ally_index"
	_target_pos_row.visible = mode == "fixed_pos"
	_sync_target_index_bounds()


func _sync_target_index_bounds() -> void:
	var mode: String = TARGET_MODE_NAMES[_target_mode_option.selected]
	if mode != "enemy_index" and mode != "ally_index":
		return
	var team := "B" if mode == "enemy_index" else "A"
	var count := 0
	for actor_data in _actors:
		var data := actor_data as Dictionary
		if data.get("role", "") == "dummy" and data.get("team", "") == team:
			count += 1
	var max_index := max(0, count - 1)
	_target_index_input.max_value = max_index
	if int(_target_index_input.value) > max_index:
		_target_index_input.value = max_index


func _on_speed_changed(v: float) -> void:
	if _animator != null:
		_animator.set_speed(v)


# ========== START / Simulate ==========

func _on_start_pressed() -> void:
	_start_button.disabled = true
	_is_playing = true
	_set_inspector_editable(false)
	_reset_button.disabled = true
	_apply_playback_inspector_layout()
	_set_console_expanded(true)
	_set_status("Running...")
	_console_log.clear()

	var ability_cfg := _get_selected_active_ability()
	if ability_cfg == null:
		_finish_with_status("No active skill selected")
		return

	# 编辑期所有面板/右键操作走 event→update 增量 mutation,
	# world state 与 _actors 数据模型实时一致, 战斗前不需要再 commit。

	var caster_id: String = _role_id_to_actor_id.get("caster", "")
	if caster_id == "":
		_finish_with_status("No caster in world")
		return

	var target_id := _resolve_target_actor_id()
	var passives := _collect_selected_passives()

	_log_battle_start(ability_cfg, int(_max_ticks_input.value))
	_log_battle_header_params(caster_id, target_id)

	_world.queue_preview(caster_id, ability_cfg, target_id, passives)

	var participants: Array[Actor] = []
	for actor in _world.get_actors():
		participants.append(actor)

	_world.start_battle(participants)

	# BATTLE_TICKS_PER_WORLD_FRAME=INT_MAX 默认下, 单次 tick 会把战斗一口气跑完,
	# 同步 emit battle_finished -> _on_battle_finished 里喂给 animator。
	_world.tick(float(TICK_INTERVAL_MS))


func _finish_with_status(s: String) -> void:
	_is_playing = false
	_apply_setup_inspector_layout()
	_start_button.disabled = false
	_reset_button.disabled = false
	_set_inspector_editable(true)
	_set_status(s)


func _get_selected_active_ability() -> AbilityConfig:
	var idx := _skill_active_option.selected
	if idx < 0:
		return null
	var actives := HexBattleSkillIndex.actives()
	return actives[idx] if idx < actives.size() else null


func _collect_selected_passives() -> Array[AbilityConfig]:
	var passives: Array[AbilityConfig] = []
	var passive_pool := HexBattleSkillIndex.passives()
	for i in _passive_checks.size():
		if _passive_checks[i].button_pressed and i < passive_pool.size():
			passives.append(passive_pool[i])
	return passives


## 按 target UI 模式解析到 world 里实际的 actor id。
func _resolve_target_actor_id() -> String:
	var mode: String = TARGET_MODE_NAMES[_target_mode_option.selected]
	match mode:
		"enemy_index":
			return _role_id_to_actor_id.get("enemy_%d" % int(_target_index_input.value), "")
		"ally_index":
			return _role_id_to_actor_id.get("ally_%d" % int(_target_index_input.value), "")
		"fixed_pos":
			var coord := HexCoord.new(int(_target_q_input.value), int(_target_r_input.value))
			var nearest := _find_nearest_character(coord, func(_c: CharacterActor) -> bool: return true)
			return nearest.get_id() if nearest != null else ""
		_:
			var caster: CharacterActor = _world.get_actor(_role_id_to_actor_id.get("caster", "")) as CharacterActor
			if caster == null:
				return ""
			var nearest := _find_nearest_character(
				caster.hex_position,
				func(c: CharacterActor) -> bool: return c.get_team_id() != caster.get_team_id(),
			)
			return nearest.get_id() if nearest != null else ""


## 遍历 world.get_actors() 找离 origin 最近的 CharacterActor, filter 决定候选集合。
func _find_nearest_character(origin: HexCoord, filter: Callable) -> CharacterActor:
	var best: CharacterActor = null
	var best_dist := 0x7FFFFFFF
	for actor in _world.get_actors():
		if not (actor is CharacterActor):
			continue
		var cchar := actor as CharacterActor
		if not filter.call(cchar):
			continue
		var d := cchar.hex_position.distance_to(origin)
		if d < best_dist:
			best_dist = d
			best = cchar
	return best


# ========== Battle 结果 / 动画 ==========

func _on_battle_finished(timeline: Dictionary) -> void:
	if timeline.is_empty():
		_last_battle_frames = 0
		_log_battle_end(0)
		_finish_with_status("Empty timeline")
		return

	_dump_timeline_events(timeline)
	_last_battle_frames = _read_total_frames(timeline)
	_set_status("Playing — %d frames" % _last_battle_frames)

	_animator.set_speed(float(_speed_input.value))
	_animator.load(timeline, _world_view.get_unit_views())
	_animator.play()


## 战斗回放结束后保留 world 当前状态(死者已 remove / 受伤者血条 < max), 让用户
## 能观察结果或重播。状态恢复到"战前"由用户按 RESET 按钮触发, 不自动 reset。
##
## START 按钮在回放结束后保持 disabled —— 当前 world 是残破状态(死者已 remove,
## hp 已损耗), 直接再 START 会基于残破状态战斗, 语义混乱。强制走 RESET → START
## 流程, 让"再次战斗"始终从干净初始态开始。
func _on_playback_ended() -> void:
	_log_battle_end(_last_battle_frames)
	_set_status("Playback ended — 按 RESET 恢复战前状态")
	_is_playing = false
	_reset_button.disabled = false


## 用户主动重置: world 状态归零到 _actors 数据模型对应的"战前"。清 console log
## (战斗记录已无对应 world 状态可对照, 留着易误读) + 重置 status + 启用 START。
func _on_reset_pressed() -> void:
	if _is_playing:
		return
	_reset_world_to_model_unguarded()
	_console_log.clear()
	_set_console_expanded(false)
	_set_inspector_editable(true)
	_apply_setup_inspector_layout()
	_set_status("Ready — 已重置")
	_start_button.disabled = false
	_frame_stage_camera()


func _read_total_frames(timeline: Dictionary) -> int:
	if timeline.has("meta") and timeline["meta"] is Dictionary:
		return int((timeline["meta"] as Dictionary).get("totalFrames", 0))
	return 0


# ========== Timeline → console (一次性 dump) ==========
#
# 切到 Animator 后不再有 per-frame signal 转发到 skill_preview, console log 变成
# "战斗结束时一次性 dump 所有事件"。视觉动画仍按 speed 播, 文字日志不追帧对齐。
# 视觉层面 UX 略退化, 阶段 4 录像 v3 + ReplayPlayer 再评估是否需要 frame signal。

func _dump_timeline_events(timeline: Dictionary) -> void:
	for entry_variant in timeline.get("timeline", []):
		var entry := entry_variant as Dictionary
		var frame := int(entry.get("frame", 0))
		for ev_variant in entry.get("events", []):
			_log_event(frame, ev_variant as Dictionary)


# ========== Console UX formatters ==========
#
# 设计目标: 战报风格的事件流,而非 raw debug 日志。
# - 仅打印 5 类"玩家关心的"事件:damage/heal/activate/death/move_start
# - 其他框架事件(attribute_changed, tag_changed, ability_granted 等)在 Godot
#   控制台查,不在 UI console 里喧宾夺主
# - 每行: [时间戳] 图标 主体  —— 图标提供扫视线索, 颜色区分语义

const EVENT_DIVIDER := "[color=#6B4F3E]━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]"


func _log_welcome() -> void:
	_log(EVENT_DIVIDER)
	_log("  [color=#FF6B6B][b]Skill Preview[/b][/color]  [color=#6B4F3E]· 右键格子摆位 · START 模拟[/color]")
	_log(EVENT_DIVIDER)


func _log_battle_start(ability_cfg: AbilityConfig, max_ticks: int) -> void:
	_console_log.clear()
	_log(EVENT_DIVIDER)
	_log("  [color=#FF6B6B][b]▶ %s[/b][/color]  [color=#6B4F3E](%s)[/color]  [color=#A89580]max_ticks=%d[/color]" % [
		ability_cfg.display_name, ability_cfg.config_id, max_ticks,
	])
	_log(EVENT_DIVIDER)


func _log_battle_header_params(caster_id: String, target_id: String) -> void:
	_log("  [color=#A89580]caster=[/color][b]%s[/b]  [color=#A89580]target=[/color]%s" % [
		caster_id, target_id if target_id != "" else "(none)",
	])


func _log_battle_end(last_frame: int) -> void:
	_log(EVENT_DIVIDER)
	_log("  [color=#7FB56B][b]■ ENDED[/b][/color]  [color=#6B4F3E](%d frames · %d ms)[/color]" % [
		last_frame, last_frame * TICK_INTERVAL_MS,
	])
	_log(EVENT_DIVIDER)


func _log_event(frame: int, ev: Dictionary) -> void:
	var kind: String = ev.get("kind", "?")
	var ms := frame * TICK_INTERVAL_MS
	var ts := "[color=#6B4F3E]%5dms[/color]" % ms
	var line := ""
	match kind:
		"damage":
			var crit := " [color=#FFC857][b]CRIT[/b][/color]" if ev.get("is_critical", false) else ""
			line = "%s  [color=#FF6B6B]⚔[/color] [b]%s[/b]  [color=#FF6B6B]−%.1f[/color] [color=#A89580](%s)[/color]%s" % [
				ts,
				ev.get("target_actor_id", "?"),
				float(ev.get("damage", 0.0)),
				ev.get("damage_type", "?"),
				crit,
			]
		"heal":
			line = "%s  [color=#7FB56B]✚[/color] [b]%s[/b]  [color=#7FB56B]+%.1f[/color]" % [
				ts,
				ev.get("target_actor_id", "?"),
				float(ev.get("heal_amount", 0.0)),
			]
		"ability_activate":
			line = "%s  [color=#5FB3D9]◈[/color] [b]%s[/b]  [color=#A89580]by[/color] %s" % [
				ts,
				ev.get("abilityInstanceId", ev.get("ability_id", "?")),
				ev.get("sourceId", "?"),
			]
		"death":
			line = "%s  [color=#A072C8]☠[/color] [b]%s[/b]  [color=#A89580]fell[/color]" % [
				ts, ev.get("actor_id", "?"),
			]
		"move_start":
			line = "%s  [color=#A89580]→[/color] %s  [color=#A89580]moving[/color]" % [
				ts, ev.get("actor_id", "?"),
			]
		_:
			return  # 框架内部事件不进 UI console (Godot 控制台仍可查)
	_log(line)


# ========== Preset 保存/加载 ==========

func _refresh_preset_list() -> void:
	_preset_load_option.clear()
	_preset_load_option.add_item("-- load preset --")
	_append_presets_from(BUILTIN_PRESET_DIR, "[builtin] ")
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	_append_presets_from(PRESET_DIR, "")


func _append_presets_from(dir_path: String, label_prefix: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var entries: Array[String] = []
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".json"):
			entries.append(file)
		file = dir.get_next()
	dir.list_dir_end()
	entries.sort()
	for f in entries:
		_preset_load_option.add_item(label_prefix + f.trim_suffix(".json"))
		_preset_load_option.set_item_metadata(
			_preset_load_option.item_count - 1, "%s/%s" % [dir_path, f]
		)


func _on_preset_save_pressed() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Save Preset"
	var vb := VBoxContainer.new()
	var label := Label.new()
	label.text = "Preset name:"
	vb.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = "my_preset"
	vb.add_child(edit)
	dialog.add_child(vb)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var preset_name: String = edit.text.strip_edges()
		if preset_name != "":
			_save_preset(preset_name)
	)
	dialog.popup_centered(Vector2(320, 120))
	edit.grab_focus()


func _save_preset(preset_name: String) -> void:
	var data := _serialize_ui_state()
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var path := "%s/%s.json" % [PRESET_DIR, preset_name]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_log("[color=red]Preset save failed: %s[/color]" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_refresh_preset_list()
	_log("Preset saved: %s" % path)


func _on_preset_load_selected(idx: int) -> void:
	if idx <= 0:
		return
	var path_variant: Variant = _preset_load_option.get_item_metadata(idx)
	if not (path_variant is String) or (path_variant as String).is_empty():
		return
	var path: String = path_variant
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_log("[color=red]Preset load failed: %s[/color]" % path)
		return
	var text := f.get_as_text()
	f.close()
	var data_variant: Variant = JSON.parse_string(text)
	if not (data_variant is Dictionary):
		_log("[color=red]Preset not a dict: %s[/color]" % path)
		return
	_deserialize_ui_state(data_variant as Dictionary)
	_log("Preset loaded: %s" % _preset_load_option.get_item_text(idx))


## Preset JSON 格式 (v2, 统一 actors):
##   {
##     "map": {"radius", "orientation", "hex_size"},
##     "skill": {"active_id", "passive_ids"},
##     "actors": [{"role", "team", "class", "pos":[q,r], "hp", "atk"}, ...],
##     "target": {"mode", "index", "q", "r"},
##     "controls": {"max_ticks", "speed"}
##   }
func _serialize_ui_state() -> Dictionary:
	var passive_ids: Array[String] = []
	var passive_pool := HexBattleSkillIndex.passives()
	for i in _passive_checks.size():
		if _passive_checks[i].button_pressed and i < passive_pool.size():
			passive_ids.append(passive_pool[i].config_id)
	var actives := HexBattleSkillIndex.actives()
	var active_id: String = ""
	if _skill_active_option.selected >= 0 and _skill_active_option.selected < actives.size():
		active_id = actives[_skill_active_option.selected].config_id
	return {
		"map": {
			"radius": int(_map_radius_input.value),
			"orientation": "flat" if _map_orientation_option.selected == 1 else "pointy",
			"hex_size": float(_map_hex_size_input.value),
		},
		"skill": {"active_id": active_id, "passive_ids": passive_ids},
		"actors": _actors.duplicate(true),
		"target": {
			"mode": TARGET_MODE_NAMES[_target_mode_option.selected],
			"index": int(_target_index_input.value),
			"q": int(_target_q_input.value),
			"r": int(_target_r_input.value),
		},
		"controls": {
			"max_ticks": int(_max_ticks_input.value),
			"speed": _speed_input.value,
		},
	}


func _deserialize_ui_state(d: Dictionary) -> void:
	# Map
	var map_cfg: Dictionary = d.get("map", {})
	_map_radius_input.value = map_cfg.get("radius", 5)
	_map_orientation_option.selected = 1 if map_cfg.get("orientation", "flat") == "flat" else 0
	_map_hex_size_input.value = map_cfg.get("hex_size", 1.0)

	# Skill
	var skill_cfg: Dictionary = d.get("skill", {})
	var actives := HexBattleSkillIndex.actives()
	var active_id: String = skill_cfg.get("active_id", "")
	for i in actives.size():
		if actives[i].config_id == active_id:
			_skill_active_option.selected = i
			break
	var passives := HexBattleSkillIndex.passives()
	var passive_ids: Array = skill_cfg.get("passive_ids", [])
	for i in _passive_checks.size():
		var is_on: bool = i < passives.size() and passives[i].config_id in passive_ids
		_passive_checks[i].button_pressed = is_on
		_apply_passive_style(_passive_checks[i], is_on)

	# Actors
	var loaded_actors: Array = d.get("actors", [])
	_actors = []
	for a_variant in loaded_actors:
		var a := a_variant as Dictionary
		var pos: Array = a.get("pos", [0, 0])
		_actors.append({
			"role": a.get("role", "dummy"),
			"team": a.get("team", "B"),
			"class": a.get("class", "WARRIOR"),
			"pos": [int(pos[0]), int(pos[1])],
			"hp": float(a.get("hp", 100.0)),
			"atk": float(a.get("atk", 0.0)),
		})
	if _actors.is_empty() or _actors[0]["role"] != "caster":
		_actors.insert(0, {"role": "caster", "team": "A",
			"class": "WARRIOR", "pos": [0, 0], "hp": 0.0, "atk": 0.0})
	_rebuild_actors_ui()

	# Target
	var target: Dictionary = d.get("target", {})
	var tmode_idx := TARGET_MODE_NAMES.find(target.get("mode", "auto"))
	_target_mode_option.selected = max(0, tmode_idx)
	_target_index_input.value = target.get("index", 0)
	_target_q_input.value = target.get("q", 0)
	_target_r_input.value = target.get("r", 0)
	_update_target_visibility()

	# Controls
	var ctrl: Dictionary = d.get("controls", {})
	_max_ticks_input.value = ctrl.get("max_ticks", 500)
	_speed_input.value = ctrl.get("speed", 1.0)

	_reset_world_to_model()


# ========== 工具 ==========

func _set_status(s: String) -> void:
	_status_label.text = "Status: " + s
	if _console_summary_label != null:
		_console_summary_label.text = s


func _on_console_toggle_pressed() -> void:
	_set_console_expanded(not _console_expanded)


func _set_console_expanded(expanded: bool) -> void:
	_console_expanded = expanded
	_console_log.visible = expanded
	_console_toggle_button.text = "Hide Log" if expanded else "Show Log"
	_update_workspace_layout()


func _set_inspector_editable(editable: bool) -> void:
	_left_panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if editable else 0.72)
	_set_controls_editable(_left_panel, editable)
	_speed_input.editable = true
	_speed_input.get_line_edit().editable = true


func _set_controls_editable(node: Node, editable: bool) -> void:
	for child in node.get_children():
		if child == _reset_button:
			continue
		if child is Button:
			(child as Button).disabled = not editable
		elif child is SpinBox:
			var spin := child as SpinBox
			spin.editable = editable
			spin.get_line_edit().editable = editable
		elif child is OptionButton:
			(child as OptionButton).disabled = not editable
		elif child is CheckBox:
			(child as CheckBox).disabled = not editable
		_set_controls_editable(child, editable)


func _log(line: String) -> void:
	_console_log.append_text(line + "\n")


# ============================================================================
# Control Panel Theme
# ============================================================================

const CLAY_BG := Color("F1F5F9")
const CLAY_SURFACE := Color("FFFFFF")
const CLAY_TEXT := Color("111827")
const CLAY_TEXT_SOFT := Color("64748B")
const CLAY_SHADOW := Color(15, 23, 42, 0.08)

## 每个 section 保留轻量色标，避免整面板变成同一种颜色。
const SECTION_COLORS := {
	"TitlePreset": Color("F8FAFC"),
	"TitleMap": Color("F8FAFC"),
	"TitleSkill": Color("F8FAFC"),
	"TitleActors": Color("F8FAFC"),
	"TitleTarget": Color("F8FAFC"),
	"TitleCtrl": Color("F8FAFC"),
}

const START_COLOR := Color("2563EB")
const START_HOVER := Color("1D4ED8")
const START_PRESSED := Color("1E40AF")
const CONSOLE_BG := Color("111827")
const CONSOLE_FG := Color("E5E7EB")


func _apply_clay_theme() -> void:
	var root: Control = get_node("ConfigUI/Root")
	root.theme = _build_clay_theme()
	_style_section_titles()
	_style_inspector_tabs()
	_style_actor_add_buttons()
	_style_start_button()
	_style_reset_button()
	_style_status_label()
	_style_console()


func _clay_font() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Inter", "Segoe UI", "Roboto", "Noto Sans", "sans-serif",
	])
	sf.font_weight = 500
	return sf


func _clay_font_bold() -> Font:
	var fv := FontVariation.new()
	fv.base_font = _clay_font()
	fv.variation_embolden = 1.0
	return fv


## 构造一个 panel/control stylebox: 低阴影 + 小圆角 + 稳定内边距。
func _clay_sb(
	bg: Color, radius: int = 8,
	pad_x: int = 10, pad_y: int = 7,
	shadow_y: int = 2, shadow_size: int = 4
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	sb.shadow_color = CLAY_SHADOW
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2(0, shadow_y)
	return sb


## 全局 Theme 资源: panel / button / input 等默认外观
func _build_clay_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _clay_font()
	t.default_font_size = 14

	# PanelContainer (LeftPanel, BottomPanel)
	var panel_sb := _clay_sb(CLAY_SURFACE, 8, 12, 12, 2, 8)
	panel_sb.border_color = Color("D8DEE8")
	panel_sb.border_width_left = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_bottom = 1
	t.set_stylebox("panel", "PanelContainer", panel_sb)

	# Button
	var btn_bg := Color("F8FAFC")
	var btn_hover := Color("EEF2F7")
	var btn_pressed := Color("E2E8F0")
	var btn_normal := _clay_sb(btn_bg, 6, 10, 6, 0, 0)
	btn_normal.border_color = Color("CBD5E1")
	btn_normal.border_width_left = 1
	btn_normal.border_width_right = 1
	btn_normal.border_width_top = 1
	btn_normal.border_width_bottom = 1
	var btn_hover_sb := _clay_sb(btn_hover, 6, 10, 6, 0, 0)
	btn_hover_sb.border_color = Color("B6C2D2")
	btn_hover_sb.border_width_left = 1
	btn_hover_sb.border_width_right = 1
	btn_hover_sb.border_width_top = 1
	btn_hover_sb.border_width_bottom = 1
	t.set_stylebox("normal",   "Button", btn_normal)
	t.set_stylebox("hover",    "Button", btn_hover_sb)
	t.set_stylebox("pressed",  "Button",
		_clay_sb(btn_pressed, 6, 10, 6, 0, 0))
	t.set_stylebox("disabled", "Button", _clay_sb(Color("E5E7EB"), 6, 10, 6, 0, 0))
	t.set_stylebox("focus",    "Button", StyleBoxEmpty.new())
	t.set_color("font_color",          "Button", CLAY_TEXT)
	t.set_color("font_hover_color",    "Button", Color("0F172A"))
	t.set_color("font_pressed_color",  "Button", CLAY_TEXT)
	t.set_color("font_disabled_color", "Button", CLAY_TEXT_SOFT)

	# CheckBox
	t.set_stylebox("normal",  "CheckBox", _outlined_sb(Color("FFFFFF"), Color("C8D1DF"), 6, 6, 3))
	t.set_stylebox("hover",   "CheckBox", _outlined_sb(Color("EAF2FF"), Color("7AA7F7"), 6, 6, 3))
	t.set_stylebox("pressed", "CheckBox", _outlined_sb(Color("CFE1FF"), Color("2563EB"), 6, 6, 3))
	t.set_stylebox("focus",   "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", CLAY_TEXT)
	t.set_color("font_hover_color", "CheckBox", CLAY_TEXT)
	t.set_color("font_pressed_color", "CheckBox", START_PRESSED)

	# OptionButton
	t.set_stylebox("normal",  "OptionButton", _outlined_sb(Color("FFFFFF"), Color("9CAFC7"), 6, 9, 5))
	t.set_stylebox("hover",   "OptionButton", _outlined_sb(Color("EAF2FF"), Color("5C91F2"), 6, 9, 5))
	t.set_stylebox("pressed", "OptionButton", _outlined_sb(Color("CFE1FF"), Color("2563EB"), 6, 9, 5))
	t.set_stylebox("disabled", "OptionButton", _outlined_sb(Color("EEF2F7"), Color("CBD5E1"), 6, 9, 5))
	t.set_stylebox("focus",   "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", CLAY_TEXT)
	t.set_color("font_hover_color", "OptionButton", START_PRESSED)
	t.set_color("font_pressed_color", "OptionButton", START_PRESSED)
	t.set_color("font_disabled_color", "OptionButton", CLAY_TEXT_SOFT)

	# SpinBox 内部 LineEdit
	t.set_stylebox("normal",   "LineEdit", _outlined_sb(Color("FFFFFF"), Color("9CAFC7"), 6, 8, 5))
	t.set_stylebox("focus",    "LineEdit", _outlined_sb(Color("EAF2FF"), Color("2563EB"), 6, 8, 5))
	t.set_stylebox("read_only","LineEdit", _outlined_sb(Color("EEF2F7"), Color("CBD5E1"), 6, 8, 5))
	t.set_color("font_color",  "LineEdit", CLAY_TEXT)
	t.set_color("caret_color", "LineEdit", CLAY_TEXT)

	# Label 默认
	t.set_color("font_color", "Label", CLAY_TEXT)

	# ItemList / ScrollContainer
	t.set_stylebox("panel",      "ItemList",         _clay_sb(Color("FFFFFF"), 6, 8, 6, 0, 0))
	t.set_stylebox("focus",      "ItemList",         StyleBoxEmpty.new())
	t.set_stylebox("selected",   "ItemList",         _clay_sb(Color("DBEAFE"), 6, 6, 3, 0, 0))
	t.set_color("font_color",              "ItemList", CLAY_TEXT)
	t.set_color("font_selected_color",     "ItemList", CLAY_TEXT)

	# PopupMenu (右键菜单)
	t.set_stylebox("panel",         "PopupMenu", _clay_sb(CLAY_SURFACE, 8, 8, 6, 2, 8))
	t.set_stylebox("hover",         "PopupMenu", _clay_sb(Color("EFF6FF"), 6, 10, 4, 0, 0))
	t.set_color("font_color",       "PopupMenu", CLAY_TEXT)
	t.set_color("font_hover_color", "PopupMenu", CLAY_TEXT)
	t.set_color("font_separator_color", "PopupMenu", CLAY_TEXT_SOFT)

	# HSeparator (细分隔 — 我们主要不用,保留 fallback)
	var sep_sb := StyleBoxLine.new()
	sep_sb.color = Color("E2E8F0")
	sep_sb.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep_sb)

	return t


## 给每个 Section Title label 套上轻量标题块。
func _style_section_titles() -> void:
	_style_section_titles_under(_left_panel)


func _style_section_titles_under(node: Node) -> void:
	for child in node.get_children():
		if child is Label and SECTION_COLORS.has(child.name):
			_style_section_title(child as Label)
		_style_section_titles_under(child)


func _style_section_title(lbl: Label) -> void:
	var color: Color = SECTION_COLORS[lbl.name]
	var sb := _clay_sb(color, 4, 0, 3, 0, 0)
	lbl.add_theme_stylebox_override("normal", sb)
	lbl.add_theme_font_override("font", _clay_font_bold())
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.text = lbl.text.replace("—", "").strip_edges()


func _style_inspector_tabs() -> void:
	if _inspector_tabs == null:
		return
	_inspector_tabs.add_theme_stylebox_override("panel", _clay_sb(Color("FFFFFF"), 6, 8, 8, 0, 0))
	_inspector_tabs.add_theme_stylebox_override("tab_selected",
		_outlined_sb(Color("D7E6FF"), Color("2563EB"), 6, 8, 6))
	_inspector_tabs.add_theme_stylebox_override("tab_hovered",
		_outlined_sb(Color("EAF2FF"), Color("7AA7F7"), 6, 8, 6))
	_inspector_tabs.add_theme_stylebox_override("tab_unselected",
		_outlined_sb(Color("FFFFFF"), Color("D5DDE8"), 6, 8, 6))
	_inspector_tabs.add_theme_color_override("font_selected_color", START_PRESSED)
	_inspector_tabs.add_theme_color_override("font_unselected_color", Color("334155"))
	_inspector_tabs.add_theme_color_override("font_hovered_color", Color("0F172A"))


func _style_actor_add_buttons() -> void:
	_style_subtle_button(_actor_add_enemy_button)
	_style_subtle_button(_actor_add_ally_button)


func _style_subtle_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _outlined_sb(Color("FFFFFF"), Color("9CAFC7"), 6, 10, 6))
	btn.add_theme_stylebox_override("hover", _outlined_sb(Color("EAF2FF"), Color("5C91F2"), 6, 10, 6))
	btn.add_theme_stylebox_override("pressed", _outlined_sb(Color("CFE1FF"), Color("2563EB"), 6, 10, 6))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", CLAY_TEXT)
	btn.add_theme_color_override("font_hover_color", CLAY_TEXT)


func _outlined_sb(bg: Color, border: Color, radius: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var sb := _clay_sb(bg, radius, pad_x, pad_y, 0, 0)
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	return sb


## StartButton 是主操作，使用唯一高对比色。
func _style_start_button() -> void:
	var btn := _start_button
	btn.add_theme_stylebox_override("normal",
		_clay_sb(START_COLOR, 6, 18, 9, 1, 3))
	btn.add_theme_stylebox_override("hover",
		_clay_sb(START_HOVER, 6, 18, 9, 1, 4))
	btn.add_theme_stylebox_override("pressed",
		_clay_sb(START_PRESSED, 6, 18, 9, 0, 0))
	btn.add_theme_stylebox_override("disabled",
		_clay_sb(Color("93C5FD"), 6, 18, 9, 0, 0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", _clay_font_bold())
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


## ResetButton 视觉次于 START，用中性按钮避免误抢焦点。
func _style_reset_button() -> void:
	var btn := _reset_button
	btn.add_theme_stylebox_override("normal",
		_outlined_sb(Color("FFFFFF"), Color("CBD5E1"), 6, 14, 9))
	btn.add_theme_stylebox_override("hover",
		_outlined_sb(Color("F8FAFC"), Color("94A3B8"), 6, 14, 9))
	btn.add_theme_stylebox_override("pressed",
		_outlined_sb(Color("E2E8F0"), Color("94A3B8"), 6, 14, 9))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", _clay_font_bold())
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", CLAY_TEXT)
	btn.add_theme_color_override("font_hover_color", CLAY_TEXT)
	btn.add_theme_color_override("font_pressed_color", CLAY_TEXT)


func _style_status_label() -> void:
	var sb := _clay_sb(Color("F8FAFC"), 6, 9, 6, 0, 0)
	sb.border_color = Color("E2E8F0")
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	_status_label.add_theme_stylebox_override("normal", sb)
	_status_label.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	_status_label.add_theme_font_size_override("font_size", 12)


## Passive CheckBox 选中/未选中视觉: 选中 = 鲜珊瑚 + 白字(高对比),
## 未选中 = 淡米(低突出)。直接 override 每个状态 stylebox 让渲染顺序无歧义。
##
## passive 选择只影响 _on_start_pressed 时 _collect_selected_passives() 传给
## queue_preview, 编辑期 world 不感知 passive (passive 是战斗期 grant 给 caster),
## 因此勾选/取消勾选不需要触发 world mutation。
func _on_passive_toggled(_pressed: bool, cb: CheckBox) -> void:
	_apply_passive_style(cb, _pressed)


func _apply_passive_style(cb: CheckBox, selected: bool) -> void:
	if selected:
		var sb := _clay_sb(Color("CFE1FF"), 6, 6, 3, 0, 0)
		sb.border_color = START_COLOR
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		cb.add_theme_stylebox_override("normal", sb)
		cb.add_theme_stylebox_override("hover", _outlined_sb(Color("BDD5FF"), Color("1D4ED8"), 6, 6, 3))
		cb.add_theme_stylebox_override("pressed", _outlined_sb(Color("AFCBFF"), Color("1E40AF"), 6, 6, 3))
		cb.add_theme_color_override("font_color", START_PRESSED)
		cb.add_theme_color_override("font_hover_color", START_PRESSED)
		cb.add_theme_color_override("font_pressed_color", START_PRESSED)
	else:
		cb.remove_theme_stylebox_override("normal")
		cb.remove_theme_stylebox_override("hover")
		cb.remove_theme_stylebox_override("pressed")
		cb.remove_theme_color_override("font_color")
		cb.remove_theme_color_override("font_hover_color")
		cb.remove_theme_color_override("font_pressed_color")


## Console: 深紫底 + 亮字, 对比 vibrant 主面板
func _style_console() -> void:
	_console_panel.add_theme_stylebox_override("panel",
		_clay_sb(CONSOLE_BG, 8, 12, 10, 2, 8))
	_console_log.add_theme_color_override("default_color", CONSOLE_FG)
	_console_log.add_theme_font_size_override("normal_font_size", 12)
	_console_summary_label.add_theme_color_override("font_color", Color("CBD5E1"))
	_console_summary_label.add_theme_font_size_override("font_size", 12)
	_console_toggle_button.add_theme_stylebox_override("normal",
		_clay_sb(Color("1F2937"), 6, 12, 6, 0, 0))
	_console_toggle_button.add_theme_stylebox_override("hover",
		_clay_sb(Color("374151"), 6, 12, 6, 0, 0))
	_console_toggle_button.add_theme_stylebox_override("pressed",
		_clay_sb(Color("111827"), 6, 12, 6, 0, 0))
	_console_toggle_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_console_toggle_button.add_theme_color_override("font_color", CONSOLE_FG)
	_console_toggle_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_console_toggle_button.add_theme_color_override("font_pressed_color", Color.WHITE)
