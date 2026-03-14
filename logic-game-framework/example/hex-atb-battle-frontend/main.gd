## Main - 战斗回放前端示例入口
##
## 演示如何使用表演框架播放战斗录像
## 通过 UI 配置地图参数，点击按钮启动战斗模拟
extends Node


# ========== 节点引用 ==========

var _replay_scene: FrontendBattleReplayScene
var _controls: FrontendReplayControls
var _player_controller: LomoPlayerController

## 逻辑层战斗实例（用于获取录像数据）
var _battle: HexBattle

## 地图配置 UI 引用
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
	
	# 1. 初始化地图配置 UI
	_setup_config_ui()
	
	# 2. 创建回放场景（但不加载数据）
	_replay_scene = FrontendBattleReplayScene.new()
	_replay_scene.name = "BattleReplayScene"
	add_child(_replay_scene)
	
	# 3. 创建玩家控制器并绑定相机
	_setup_player_controller()
	
	# 4. 创建播放控制 UI
	_setup_ui()
	
	# 5. 连接信号
	var director := _replay_scene.get_director()
	director.playback_state_changed.connect(_on_playback_state_changed)
	director.frame_changed.connect(_on_frame_changed)
	director.playback_ended.connect(_on_playback_ended)
	
	# 6. 更新状态
	_update_status("Ready - Configure map and click 'Start Battle'")


## 设置地图配置 UI
func _setup_config_ui() -> void:
	# 初始化下拉框选项
	_draw_mode_option.add_item("Row/Column", 0)
	_draw_mode_option.add_item("Radius", 1)
	_draw_mode_option.selected = 0
	
	# 初始化 Orientation 下拉框
	_orientation_option.add_item("Flat", 0)
	_orientation_option.add_item("Pointy", 1)
	_orientation_option.selected = 0
	
	# 初始化输入框默认值
	_rows_input.value = 9
	_columns_input.value = 9
	_radius_input.value = 4
	_hex_size_input.value = 1
	
	# 初始显示/隐藏对应的输入框
	_update_input_visibility()


## 根据当前选择的模式更新输入框可见性
func _update_input_visibility() -> void:
	var is_row_column := _draw_mode_option.selected == 0
	_rows_container.visible = is_row_column
	_columns_container.visible = is_row_column
	_radius_container.visible = not is_row_column


## 获取当前地图配置
func _get_map_config() -> GridMapConfig:
	var config := GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.size = _hex_size_input.value
	config.orientation = GridMapConfig.Orientation.FLAT if _orientation_option.selected == 0 else GridMapConfig.Orientation.POINTY
	
	if _draw_mode_option.selected == 0:
		# Row/Column 模式
		config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		config.rows = int(_rows_input.value)
		config.columns = int(_columns_input.value)
	else:
		# Radius 模式
		config.draw_mode = GridMapConfig.DrawMode.RADIUS
		config.radius = int(_radius_input.value)
	
	return config


## 设置玩家控制器
func _setup_player_controller() -> void:
	_player_controller = LomoPlayerController.new()
	_player_controller.name = "PlayerController"
	add_child(_player_controller)
	
	# 绑定相机
	var camera_rig: LomoCameraRig = _replay_scene.get_camera_rig()
	if camera_rig:
		_player_controller.use_camera_rig(camera_rig)
	
	# 连接点击信号（可用于未来的交互功能）
	_player_controller.ground_clicked.connect(_on_ground_clicked)
	_player_controller.actor_clicked.connect(_on_actor_clicked)


## 地面点击回调
func _on_ground_clicked(position: Vector3, button: MouseButton) -> void:
	print("[Main] Ground clicked at: %s (button: %d)" % [position, button])


## Actor 点击回调
func _on_actor_clicked(actor: Node3D, button: MouseButton) -> void:
	print("[Main] Actor clicked: %s (button: %d)" % [actor.name, button])


func _setup_ui() -> void:
	_controls = FrontendReplayControls.new()
	_controls.name = "ReplayControls"
	_controls.anchor_left = 0.0
	_controls.anchor_top = 0.0
	_controls.anchor_right = 0.3
	_controls.anchor_bottom = 0.3
	# 将播放控制 UI 放在右上角，避免与配置 UI 重叠
	_controls.anchor_left = 0.7
	_controls.anchor_right = 1.0
	add_child(_controls)
	
	# 连接 UI 信号
	_controls.play_pressed.connect(_on_play_pressed)
	_controls.pause_pressed.connect(_on_pause_pressed)
	_controls.reset_pressed.connect(_on_reset_pressed)
	_controls.speed_changed.connect(_on_speed_changed)


## 更新状态标签
func _update_status(text: String) -> void:
	if _status_label:
		_status_label.text = "Status: " + text


# ========== 地图配置 UI 回调 ==========

func _on_draw_mode_option_item_selected(_index: int) -> void:
	_update_input_visibility()


## 开始战斗按钮回调
func _on_start_battle_button_pressed() -> void:
	_update_status("Running battle simulation...")
	_start_battle_button.disabled = true
	
	# 获取当前地图配置
	var map_config := _get_map_config()
	print("[Main] Starting battle with map config: %s" % map_config)
	
	# 运行逻辑层战斗
	var replay_data := _run_logic_battle(map_config)
	
	# 加载并播放录像
	if not replay_data.is_empty():
		var record := ReplayData.BattleRecord.from_dict(replay_data)
		print("[Main] Loading replay from logic battle")
		print("  - Total frames: %d" % record.meta.total_frames)
		print("  - Actors: %d" % record.initial_actors.size())
		_replay_scene.load_replay(record)
		_update_status("Battle loaded - %d frames" % record.meta.total_frames)
	else:
		print("[Main] Logic battle produced no replay data, using demo data")
		_load_demo_replay()
		_update_status("Demo replay loaded")
	
	_start_battle_button.disabled = false


# ========== 逻辑层战斗 ==========

## 同步运行一场逻辑层战斗，返回录像数据
func _run_logic_battle(map_config: GridMapConfig) -> Dictionary:
	print("[Main] Running logic battle...")
	
	# 确保 GameWorld 已初始化
	GameWorld.init()
	
	# 创建战斗实例
	_battle = GameWorld.create_instance(func() -> GameplayInstance:
		var b := HexBattle.new()
		b.start({
			"logging": false,      # 禁用日志文件输出
			"recording": true,     # 启用录像
			"console_log": false,  # 禁用控制台日志
			"file_log": false,     # 禁用文件日志
			"map_config": map_config,  # 传递地图配置
		})
		return b
	) as HexBattle
	
	# 同步运行战斗（每帧 100ms，上限与逻辑层一致）
	var dt := 100.0
	for i in range(HexBattle.MAX_TICKS):
		GameWorld.tick_all(dt)
		if not GameWorld.has_running_instances():
			break
	
	print("[Main] Logic battle completed in %d ticks" % _battle.tick_count)
	
	# 获取录像数据
	return _battle.get_replay_data()


func _load_demo_replay() -> void:
	# 创建演示用的回放数据
	var demo_record := _create_demo_replay()
	print("[Main] Using demo replay data")
	_replay_scene.load_replay(demo_record)


func _create_demo_replay() -> ReplayData.BattleRecord:
	# 创建一个简单的演示回放
	return ReplayData.BattleRecord.from_dict({
		"version": "2.0",
		"meta": {
			"battleId": "demo_battle",
			"recordedAt": Time.get_unix_time_from_system(),
			"tickInterval": 100,
			"totalFrames": 50,
			"result": "demo",
		},
		"configs": {
			"positionFormats": {
				"Character": "hex",
			},
		},
		"initialActors": [
			{
				"id": "actor_1",
				"type": "Character",
				"configId": "warrior",
				"displayName": "Warrior",
				"team": 0,
				"position": [-2, 0, 0],
				"attributes": { "hp": 100.0, "maxHp": 100.0 },
				"abilities": [],
				"tags": {},
			},
			{
				"id": "actor_2",
				"type": "Character",
				"configId": "mage",
				"displayName": "Mage",
				"team": 1,
				"position": [2, 0, 0],
				"attributes": { "hp": 80.0, "maxHp": 80.0 },
				"abilities": [],
				"tags": {},
			},
		],
		"timeline": [
			{
				"frame": 5,
				"events": [
					{
						"kind": "move_start",
						"actor_id": "actor_1",
						"from_hex": { "q": -2, "r": 0 },
						"to_hex": { "q": -1, "r": 0 },
					},
				],
			},
			{
				"frame": 10,
				"events": [
					{
						"kind": "damage",
						"target_actor_id": "actor_2",
						"damage": 25.0,
						"damage_type": "physical",
						"source_actor_id": "actor_1",
						"is_critical": false,
						"is_reflected": false,
					},
				],
			},
			{
				"frame": 20,
				"events": [
					{
						"kind": "heal",
						"target_actor_id": "actor_2",
						"heal_amount": 15.0,
						"source_actor_id": "actor_2",
					},
				],
			},
			{
				"frame": 30,
				"events": [
					{
						"kind": "damage",
						"target_actor_id": "actor_2",
						"damage": 50.0,
						"damage_type": "physical",
						"source_actor_id": "actor_1",
						"is_critical": true,
						"is_reflected": false,
					},
				],
			},
			{
				"frame": 40,
				"events": [
					{
						"kind": "damage",
						"target_actor_id": "actor_2",
						"damage": 30.0,
						"damage_type": "physical",
						"source_actor_id": "actor_1",
						"is_critical": false,
						"is_reflected": false,
					},
					{
						"kind": "death",
						"actor_id": "actor_2",
						"killer_actor_id": "actor_1",
					},
				],
			},
		],
	})


# ========== 信号处理 ==========

func _on_playback_state_changed(is_playing: bool) -> void:
	_controls.update_playback_state(is_playing)


func _on_frame_changed(current_frame: int, total_frames: int) -> void:
	_controls.update_frame_info(current_frame, total_frames)


func _on_playback_ended() -> void:
	_controls.set_ended_state()
	print("[Main] Playback ended")


func _on_play_pressed() -> void:
	_replay_scene.play()


func _on_pause_pressed() -> void:
	_replay_scene.pause()


func _on_reset_pressed() -> void:
	_replay_scene.reset()
	_controls.update_playback_state(false)
	_controls.update_frame_info(0, _replay_scene.get_director().get_total_frames())


func _on_speed_changed(speed: float) -> void:
	_replay_scene.set_speed(speed)


# ========== 输入处理 ==========

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_SPACE:
				# 如果按住 Ctrl，重置相机；否则切换播放
				if key_event.ctrl_pressed:
					var camera_rig: LomoCameraRig = _replay_scene.get_camera_rig()
					if camera_rig:
						camera_rig.reset_camera()
				else:
					_replay_scene.toggle()
			KEY_R:
				_on_reset_pressed()
			KEY_1:
				_replay_scene.set_speed(0.5)
			KEY_2:
				_replay_scene.set_speed(1.0)
			KEY_3:
				_replay_scene.set_speed(2.0)
			KEY_4:
				_replay_scene.set_speed(4.0)
