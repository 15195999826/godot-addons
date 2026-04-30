## HexAtbBattle Frontend Demo 入口脚本（响应式 wire）
##
## addon 自带的 frontend demo 场景: 3D camera + 6v6 默认战斗 + animator 播放。
## 用户按 Start Battle 看战斗动起来什么样。真正的项目入口在主仓
## scenes/Simulation.tscn (web 桥接)。本场景只是 addon frontend 演示。
##
## 用户按 Start Battle:
##   1. 创建 HexDemoWorldGameplayInstance (WorldGameplayInstance 子类)
##   2. WorldView.bind_world(battle) -> battle.start 时 add_actor signal 触发 view spawn
##   3. tick 同步跑完战斗 -> battle_finished signal
##   4. _on_battle_finished -> animator.load(timeline, view.get_unit_views()) 加载录像(不自动播放)
##   5. 用户按 Play 按钮 / 1-4 速度键 / Space -> animator.play()
extends Node


# ========== UI 节点引用 ==========

@onready var _draw_mode_option: OptionButton = $ConfigUI/VBoxContainer/DrawModeOption
@onready var _rows_container: HBoxContainer = $ConfigUI/VBoxContainer/RowsContainer
@onready var _columns_container: HBoxContainer = $ConfigUI/VBoxContainer/ColumnsContainer
@onready var _radius_container: HBoxContainer = $ConfigUI/VBoxContainer/RadiusContainer
@onready var _rows_input: SpinBox = $ConfigUI/VBoxContainer/RowsContainer/RowsInput
@onready var _columns_input: SpinBox = $ConfigUI/VBoxContainer/ColumnsContainer/ColumnsInput
@onready var _radius_input: SpinBox = $ConfigUI/VBoxContainer/RadiusContainer/RadiusInput
@onready var _hex_size_input: SpinBox = $ConfigUI/VBoxContainer/HexSizeContainer/HexSizeInput
@onready var _orientation_option: OptionButton = $ConfigUI/VBoxContainer/OrientationOption
@onready var _start_battle_button: Button = $ConfigUI/VBoxContainer/StartBattleButton
@onready var _status_label: Label = $ConfigUI/VBoxContainer/StatusLabel


# ========== 响应式栈 ==========

var _battle: HexDemoWorldGameplayInstance = null
var _world_view: FrontendWorldView
var _animator: FrontendBattleAnimator
var _camera_rig: LomoCameraRig
var _player_controller: LomoPlayerController
var _controls: FrontendPlaybackControls


# ========== 生命周期 ==========

func _ready() -> void:
	print("\n========== Hex ATB Battle Frontend Demo ==========\n")
	print("Camera Controls:")
	print("  WASD / Arrow Keys - Move camera")
	print("  Q / E - Rotate camera")
	print("  Mouse Wheel - Zoom in/out")
	print("  Space - Reset camera / Toggle playback")
	print("  R - Reset playback")
	print("  1/2/3/4 - Set playback speed (0.5x/1x/2x/4x)")
	print("")

	GameWorld.init()

	_setup_config_ui()
	_setup_camera_and_env()
	_setup_world_view_and_animator()
	_setup_player_controller()
	_setup_ui()

	_update_status("Ready - Configure map and click 'Start Battle'")


func _exit_tree() -> void:
	if _world_view != null:
		_world_view.unbind_world()
	GameWorld.destroy()


# ========== Config UI ==========

func _setup_config_ui() -> void:
	_draw_mode_option.add_item("Row/Column", 0)
	_draw_mode_option.add_item("Radius", 1)
	_draw_mode_option.selected = 0

	_orientation_option.add_item("Flat", 0)
	_orientation_option.add_item("Pointy", 1)
	_orientation_option.selected = 0

	_rows_input.value = 9
	_columns_input.value = 9
	_radius_input.value = 4
	_hex_size_input.value = 1

	_update_input_visibility()


func _update_input_visibility() -> void:
	var is_row_column := _draw_mode_option.selected == 0
	_rows_container.visible = is_row_column
	_columns_container.visible = is_row_column
	_radius_container.visible = not is_row_column


func _get_map_config() -> GridMapConfig:
	var config := GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.size = _hex_size_input.value
	config.orientation = (
		GridMapConfig.Orientation.FLAT if _orientation_option.selected == 0
		else GridMapConfig.Orientation.POINTY
	)

	if _draw_mode_option.selected == 0:
		config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		config.rows = int(_rows_input.value)
		config.columns = int(_columns_input.value)
	else:
		config.draw_mode = GridMapConfig.DrawMode.RADIUS
		config.radius = int(_radius_input.value)

	return config


# ========== 响应式栈初始化 ==========

func _setup_camera_and_env() -> void:
	var camera_scene := preload("res://addons/lomolib/camera/lomo_camera_rig.tscn")
	_camera_rig = camera_scene.instantiate() as LomoCameraRig
	_camera_rig.name = "CameraRig"
	_camera_rig.default_arm_length = 20.0
	_camera_rig.min_zoom = 8.0
	_camera_rig.max_zoom = 40.0
	_camera_rig.default_pitch = -50.0
	_camera_rig.move_speed = 15.0
	add_child(_camera_rig)
	_camera_rig.make_current()

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


func _setup_world_view_and_animator() -> void:
	_world_view = FrontendWorldView.new()
	_world_view.name = "WorldView"
	add_child(_world_view)

	_animator = FrontendBattleAnimator.new()
	_animator.name = "BattleAnimator"
	add_child(_animator)
	_animator.playback_state_changed.connect(_on_playback_state_changed)
	_animator.frame_changed.connect(_on_frame_changed)
	_animator.playback_ended.connect(_on_playback_ended)


func _setup_player_controller() -> void:
	_player_controller = LomoPlayerController.new()
	_player_controller.name = "PlayerController"
	add_child(_player_controller)
	if _camera_rig != null:
		_player_controller.use_camera_rig(_camera_rig)
	_player_controller.ground_clicked.connect(_on_ground_clicked)
	_player_controller.actor_clicked.connect(_on_actor_clicked)


func _setup_ui() -> void:
	_controls = FrontendPlaybackControls.new()
	_controls.name = "PlaybackControls"
	# 右上角放置
	_controls.anchor_left = 0.7
	_controls.anchor_top = 0.0
	_controls.anchor_right = 1.0
	_controls.anchor_bottom = 0.3
	add_child(_controls)

	_controls.play_pressed.connect(_on_play_pressed)
	_controls.pause_pressed.connect(_on_pause_pressed)
	_controls.reset_pressed.connect(_on_reset_pressed)
	_controls.speed_changed.connect(_on_speed_changed)


func _update_status(text: String) -> void:
	if _status_label:
		_status_label.text = "Status: " + text


# ========== 配置 UI 回调 ==========

func _on_draw_mode_option_item_selected(_index: int) -> void:
	_update_input_visibility()


func _on_ground_clicked(pos: Vector3, button: MouseButton) -> void:
	print("[Main] Ground clicked at: %s (button: %d)" % [pos, button])


func _on_actor_clicked(actor: Node3D, button: MouseButton) -> void:
	print("[Main] Actor clicked: %s (button: %d)" % [actor.name, button])


# ========== Start Battle ==========

func _on_start_battle_button_pressed() -> void:
	_update_status("Running battle simulation...")
	_start_battle_button.disabled = true

	# HexDemoWorldGameplayInstance 一次性实例,跑完留在 GameWorld._instances 不会自清,显式 destroy
	# 防止多次 Start Battle 累积。
	_world_view.unbind_world()
	if _battle != null:
		GameWorld.destroy_instance(_battle.id)
	_battle = null

	var map_config := _get_map_config()
	print("[Main] Starting battle with map config: %s" % map_config)

	_battle = HexDemoWorldGameplayInstance.new()
	GameWorld.create_instance(func() -> GameplayInstance: return _battle)
	_battle.battle_finished.connect(_on_battle_finished)

	# 先 bind_world(空 world,无 actor) 再 start —— start 内部会 add_actor 触发
	# WorldView spawn unit views,顺序反过来会让 view 漏听。
	_world_view.bind_world(_battle)

	_battle.start({
		"logging": false,
		"recording": true,
		"console_log": false,
		"file_log": false,
		"map_config": map_config,
	})

	# 循环兜底:防极端配置(BATTLE_TICKS_PER_WORLD_FRAME 设有限值)不在单 tick 内收敛。
	var dt := 100.0
	for _i in range(HexBattleProcedure.MAX_TICKS):
		GameWorld.tick_all(dt)
		if not GameWorld.has_running_instances():
			break

	print("[Main] Logic battle completed in %d ticks" % _battle.tick_count)


# ========== Battle / Animator 信号 ==========

func _on_battle_finished(timeline: Dictionary) -> void:
	if timeline.is_empty():
		_update_status("Battle ended but produced no timeline")
		_start_battle_button.disabled = false
		return

	var meta: Dictionary = timeline.get("meta", {})
	var total_frames: int = meta.get("totalFrames", 0)
	_update_status("Loaded - %d frames (press Play)" % total_frames)

	_animator.load(timeline, _world_view.get_unit_views())


func _on_playback_state_changed(is_playing: bool) -> void:
	_controls.update_playback_state(is_playing)


func _on_frame_changed(current_frame: int, total_frames: int) -> void:
	_controls.update_frame_info(current_frame, total_frames)


func _on_playback_ended() -> void:
	_controls.set_ended_state()
	_start_battle_button.disabled = false
	print("[Main] Playback ended")


# ========== UI 控件回调 → animator forward ==========

func _on_play_pressed() -> void:
	_animator.resume()


func _on_pause_pressed() -> void:
	_animator.pause()


func _on_reset_pressed() -> void:
	_animator.reset()
	_controls.update_playback_state(false)
	_controls.update_frame_info(0, _animator.get_total_frames())


func _on_speed_changed(speed: float) -> void:
	_animator.set_speed(speed)


# ========== 输入处理 ==========

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_SPACE:
				if key_event.ctrl_pressed:
					if _camera_rig != null:
						_camera_rig.reset_camera()
				else:
					if _animator.is_playing():
						_animator.pause()
					else:
						_animator.resume()
			KEY_R:
				_on_reset_pressed()
			KEY_1:
				_animator.set_speed(0.5)
			KEY_2:
				_animator.set_speed(1.0)
			KEY_3:
				_animator.set_speed(2.0)
			KEY_4:
				_animator.set_speed(4.0)
