## SkillPreview - 技能预览开发者工具
##
## 打开 skill_preview.tscn F6:
## - 右侧 Controls dock: Start / Reset / Replay / Status, 可收起
## - 下方 Workspace drawer: Timeline / Scene / Run / Log / Warnings
## - Details 是右侧浮层: 点击 hex / actor / wall / keyframe 后显示, 可关闭
## - 3D viewport: 编辑模式下 WorldView 响应式渲染 actors 摆位, 右键点格子 /
##   actor 弹 PopupMenu
## - 点 START: world.queue_preview(actor_setups) + start_battle -> SkillPreviewProcedure
##   -> battle_finished -> FrontendBattleAnimator.play 在已有 unit view 上叠加
##   VFX / 飘字 / 死亡动画
##
## 多 actor 时间轴模型:
##   每个 actor 一条 track, track 上多个 keyframe = {time_ms, skill, target}。
##   passive 也每 actor 自己挂。procedure 在 start() drain time_ms<=0,
##   tick_once 按 logic_time 调度后续 keyframe。
##
## 响应式架构 (阶段 3):
##   - 一个 skill_preview session 一个常驻 SkillPreviewWorldGI
##   - 一个常驻 FrontendWorldView bind 到 world, 订阅 mutation signal 管 view 生命周期
##   - 一个常驻 FrontendBattleAnimator 播放 battle_finished 产出的 timeline
##   - 编辑态增删 actor 走 world.add_actor / remove_actor, WorldView 自动刷新
##   - 战斗中死者 view 不被销毁 (damage_utils 不再 remove_actor 死者), Replay 走
##     animator.reset()+play() 复用同一组 unit_views, 跟 demo_frontend 一致
##
## 数据模型 (v2):
##   actors: Array[Dictionary] —— 每条 {
##     role: "caster"|"dummy", team: "A"|"B", class, pos: [q,r], hp, atk,
##     passives: Array[String],   # config_id 列表
##     track:    Array[Dictionary],
##     # keyframe = {time_ms: int, skill: String,
##     #             target: {mode: "auto"|"enemy_index"|"ally_index"|"fixed_pos",
##     #                      index: int, q: int, r: int}}
##   }。role=="caster" 唯一且必是 team A。
##   environments: Array[Dictionary] —— 每条 {type: "stone_wall", pos: [q,r]}
##   map:      {radius: int, orientation: "pointy"|"flat", hex_size: float}
##   controls: {max_ticks, speed}
extends Node


const PRESET_DIR := "user://skill_preview_presets"
const BUILTIN_PRESET_DIR := "res://addons/logic-game-framework/example/skill-preview/presets"
const ENV_STONE_WALL := "stone_wall"

const CLASS_NAMES: Array[String] = [
	"WARRIOR", "PRIEST", "ARCHER", "MAGE", "BERSERKER", "ASSASSIN",
]

const TARGET_MODE_NAMES: Array[String] = [
	"auto", "enemy_index", "ally_index", "fixed_pos",
]

const TICK_INTERVAL_MS := 100
const INSPECTOR_MARGIN := 12.0
const SKILL_PREVIEW_WINDOW_SIZE := Vector2i(1920, 1080)
const SKILL_PREVIEW_MIN_WINDOW_SIZE := Vector2i(1600, 900)
const SKILL_PREVIEW_WINDOW_MARGIN := Vector2i(80, 120)
const CONTROL_DOCK_WIDTH := 340.0
const CONTROL_DOCK_HEIGHT := 156.0
const CHARACTER_PANEL_WIDTH := 420.0
const DETAILS_POPUP_WIDTH := 380.0
const WORKSPACE_GAP := 12.0
const DRAWER_COLLAPSED_HEIGHT := 44.0
const DRAWER_EXPANDED_HEIGHT := 420.0
const CONTROL_DOCK_COLLAPSED_WIDTH := 0.0
const WORKSPACE_MODE_SETUP := "setup"
const WORKSPACE_MODE_TIMELINE := "timeline"
const WORKSPACE_MODE_PLAYBACK := "playback"

const SELECT_NONE := "none"
const SELECT_HEX := "hex"
const SELECT_ACTOR := "actor"
const SELECT_ENVIRONMENT := "environment"
const SELECT_KEYFRAME := "keyframe"

# Keyframe 时间语义常量(SpinBox 取值范围 / 步进)
const KF_TIME_MAX_MS := 60000
const KF_TIME_STEP_MS := 100

# SkillPreviewTimeline (SPT) tab 视觉常量
# 命名前缀 SPT 与 LGF core TimelineRegistry / Ability timeline 概念区分。
const SPT_ACTOR_LABEL_W := 220
const SPT_ROW_H := 78
const SPT_RULER_H := 34
const SPT_RULER_LABEL_W := 58.0
const SPT_RULER_LABEL_H := 16.0
const SPT_KF_BTN_W := 92
const SPT_KF_BTN_H := 30
const SPT_RELEASE_SPAN_H := 18
const SPT_COOLDOWN_BAR_H := 4
const SPT_MIN_AUTO_MS := 5000
const SPT_AUTO_BUFFER_MS := 1000
const SPT_MIN_TRACK_W := 1500.0
const SPT_MS_TO_PX := 0.32
const SPT_SELECTED_BORDER := Color("0F172A")
const SPT_WARNING_COOLDOWN := Color("DC2626")
const SPT_WARNING_OVERLAP := Color("D97706")
const SPT_GHOST_COLOR := Color(0.07, 0.09, 0.15, 0.58)
const SPT_EDITOR_BG := Color("111827")
const SPT_EDITOR_PANEL := Color("1F2937")
const SPT_EDITOR_ROW := Color("17202C")
const SPT_EDITOR_GRID := Color(1.0, 1.0, 1.0, 0.08)
const SPT_EDITOR_GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.18)
const SPT_EDITOR_TEXT := Color("E5E7EB")
const SPT_EDITOR_TEXT_SOFT := Color("94A3B8")
const SPT_CURSOR_COLOR := Color("FACC15")


# ========== Scene 节点 (unique names) ==========

@onready var _left_panel: PanelContainer = get_node("ConfigUI/Root/LeftPanel") as PanelContainer
@onready var _inspector_tabs: TabContainer = %InspectorTabs

@onready var _preset_load_option: OptionButton = %PresetLoadOption
@onready var _preset_save_button: Button = %PresetSaveButton

@onready var _map_radius_input: SpinBox = %MapRadiusInput
@onready var _map_orientation_option: OptionButton = %MapOrientationOption
@onready var _map_hex_size_input: SpinBox = %MapHexSizeInput

@onready var _actors_container: VBoxContainer = %ActorsContainer
@onready var _actor_add_enemy_button: Button = %ActorAddEnemyButton
@onready var _actor_add_ally_button: Button = %ActorAddAllyButton

@onready var _spt_max_override_input: SpinBox = %SptMaxOverride
@onready var _spt_max_auto_label: Label = %SptMaxAutoLabel
@onready var _spt_ruler: Control = %SptRuler
@onready var _spt_tracks_container: VBoxContainer = %SptTracksContainer

@onready var _max_ticks_input: SpinBox = %MaxTicksInput
@onready var _speed_input: SpinBox = %SpeedInput

@onready var _start_button: Button = %StartButton
@onready var _reset_button: Button = %ResetButton
@onready var _replay_button: Button = %ReplayButton
@onready var _status_label: Label = %StatusLabel

@onready var _console_panel: PanelContainer = %BottomPanel
@onready var _console_toggle_button: Button = %ConsoleToggleButton
@onready var _console_summary_label: Label = %ConsoleSummaryLabel
@onready var _console_log: RichTextLabel = %ConsoleLog

@onready var _character_panel: PanelContainer = %CharacterPanel
@onready var _character_panel_mode_label: Label = %CharacterPanelModeLabel
@onready var _character_panel_body: VBoxContainer = %CharacterPanelBody

@onready var _hex_popup: PopupMenu = %HexPopupMenu


# ========== 状态 ==========

## 数据模型: caster 永远在 [0] 位置,其后跟随 dummies
var _actors: Array[Dictionary] = []
var _environments: Array[Dictionary] = []

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
var _controls_collapsed: bool = false
var _selected_kind: String = SELECT_NONE
var _selected_hex: HexCoord = null
var _selected_actor_idx: int = 0
var _selected_environment_idx: int = -1
var _inspector_rebuild_queued: bool = false
var _workspace_mode: String = WORKSPACE_MODE_SETUP

# SkillPreviewTimeline tab 状态
var _spt_max_override: int = 0           # 0 = auto-fit; >0 = override
var _selected_spt_actor_idx: int = -1
var _selected_spt_kf_idx: int = -1
var _spt_dragging: bool = false
var _spt_drag_actor_idx: int = -1
var _spt_drag_kf_idx: int = -1
var _spt_drag_requested_ms: int = 0
var _spt_drag_track_area: Control = null
var _spt_cursor_actor_idx: int = -1
var _spt_cursor_time_ms: int = 0

var _timeline_tracks_container: VBoxContainer = null
var _timeline_warning_list: VBoxContainer = null
var _timeline_add_button: Button = null
var _timeline_delete_button: Button = null
var _timeline_status_label: Label = null
var _drawer_tabs: TabContainer = null
var _drawer_timeline_tab: VBoxContainer = null
var _drawer_log_tab: VBoxContainer = null
var _drawer_header: Control = null
var _control_toggle_button: Button = null
var _details_popup: PanelContainer = null
var _details_popup_body: VBoxContainer = null
var _details_popup_user_closed: bool = false

## PopupMenu 上下文(右键点的格子 / actor idx)
var _popup_hex: HexCoord = null
var _popup_actor_idx: int = -1
var _popup_environment_idx: int = -1

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
var _environment_ids: Array[String] = []

## 最近一次战斗的总帧数, 从 timeline.meta.totalFrames 缓存。
## 不能从 _world.get_active_battle() 读 —— battle_finished emit 之前
## _active_battle 已经被 null 掉了 (见 world_gameplay_instance.gd:103-113)。
var _last_battle_frames: int = 0

## 最近一次战斗的录像 timeline。Replay 按钮按下时调 _animator.reset()+play()
## 即可,不需要重新 load (timeline 已在 _on_battle_finished 时 load 过, animator
## 内部 _replay_data 还在;且 actor_id / unit_views 跟战时一致)。
## 缓存 timeline 的目的只是判断 Replay 按钮是否该 enabled (空 timeline 不可重播)。
var _last_timeline: Dictionary = {}

## Map spinbox value_changed debounce —— 拖动时合并多次 rebuild。
var _map_change_timer: Timer = null


# ========== 生命周期 ==========

func _ready() -> void:
	_apply_skill_preview_window_size()
	call_deferred("_apply_skill_preview_window_size")
	_apply_clay_theme()
	_update_workspace_layout()
	get_viewport().size_changed.connect(_update_workspace_layout)
	GameWorld.init()
	_init_world_stack()
	_init_player_controller()
	_init_ui_static_options()
	_init_timeline_workspace_shell()
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


func _apply_skill_preview_window_size() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window == null:
		return
	var screen_idx := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_idx)
	var screen_pos := DisplayServer.screen_get_position(screen_idx)
	var target_size := Vector2i(
		mini(SKILL_PREVIEW_WINDOW_SIZE.x, maxi(900, screen_size.x - SKILL_PREVIEW_WINDOW_MARGIN.x)),
		mini(SKILL_PREVIEW_WINDOW_SIZE.y, maxi(640, screen_size.y - SKILL_PREVIEW_WINDOW_MARGIN.y))
	)
	window.mode = Window.MODE_WINDOWED
	window.min_size = Vector2i(
		mini(SKILL_PREVIEW_MIN_WINDOW_SIZE.x, target_size.x),
		mini(SKILL_PREVIEW_MIN_WINDOW_SIZE.y, target_size.y)
	)
	window.size = target_size
	window.position = screen_pos + Vector2i(
		int((screen_size.x - target_size.x) * 0.5),
		int((screen_size.y - target_size.y) * 0.5)
	)


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
	if _inspector_tabs != null and _inspector_tabs.get_tab_count() >= 3:
		_inspector_tabs.set_tab_title(0, "Details (popup)")
		_inspector_tabs.set_tab_title(1, "Timeline")
		_inspector_tabs.set_tab_title(2, "Scene")
		_inspector_tabs.set_tab_hidden(1, true)
		_inspector_tabs.visible = false
	var actors_vbox := _actors_container.get_parent() as VBoxContainer
	if actors_vbox != null:
		for child in actors_vbox.get_children():
			if child.name == "TitleActors" and child is Label:
				(child as Label).text = "Details"
			elif child.name == "ActorAddRow":
				(child as Control).visible = false

	# Map
	_map_orientation_option.clear()
	_map_orientation_option.add_item("pointy")
	_map_orientation_option.add_item("flat")
	_map_orientation_option.selected = 1  # flat 与 main.tscn 默认一致

	# Defaults
	_map_radius_input.value = 5
	_map_hex_size_input.value = 1.0
	_max_ticks_input.value = 2000
	_speed_input.value = 1.0
	var title_ctrl := get_node_or_null("ConfigUI/Root/LeftPanel/InspectorVBox/RunFooter/TitleCtrl") as Label
	if title_ctrl != null:
		title_ctrl.text = "Controls"


func _init_timeline_workspace_shell() -> void:
	_timeline_tracks_container = null
	_timeline_warning_list = null

	var drawer_vbox := _console_panel.get_child(0) as VBoxContainer
	if drawer_vbox == null:
		return
	_drawer_header = _console_toggle_button.get_parent() as Control
	if _drawer_header != null:
		_drawer_header.remove_child(_console_toggle_button)
		_drawer_header.visible = false
	var root := get_node("ConfigUI/Root") as Control
	root.add_child(_console_toggle_button)
	_console_toggle_button.custom_minimum_size = Vector2(36, 28)
	_console_toggle_button.focus_mode = Control.FOCUS_NONE
	_init_control_toggle_button(root)
	_init_details_popup(root)

	_drawer_tabs = TabContainer.new()
	_drawer_tabs.name = "WorkspaceTabs"
	_drawer_tabs.clip_tabs = true
	_drawer_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer_vbox.add_child(_drawer_tabs)

	_drawer_timeline_tab = VBoxContainer.new()
	_drawer_timeline_tab.name = "Timeline"
	_drawer_timeline_tab.add_theme_constant_override("separation", 6)
	_drawer_timeline_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_timeline_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer_tabs.add_child(_drawer_timeline_tab)

	_build_drawer_timeline_tab()
	_build_drawer_scene_tab()
	_build_drawer_run_tab()

	_drawer_log_tab = VBoxContainer.new()
	_drawer_log_tab.name = "Log"
	_drawer_log_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_log_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer_tabs.add_child(_drawer_log_tab)
	if _console_log.get_parent() != null:
		_console_log.get_parent().remove_child(_console_log)
	_console_log.visible = true
	_console_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer_log_tab.add_child(_console_log)

	var warnings_tab := VBoxContainer.new()
	warnings_tab.name = "Warnings"
	warnings_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warnings_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	warnings_tab.add_theme_constant_override("separation", 6)
	_drawer_tabs.add_child(warnings_tab)
	_timeline_warning_list = warnings_tab

	_drawer_tabs.current_tab = 0
	_set_console_expanded(_console_expanded)


func _build_drawer_timeline_tab() -> void:
	_drawer_timeline_tab.add_theme_stylebox_override(
		"panel",
		_clay_sb(SPT_EDITOR_BG, 8, 8, 8, 0, 0)
	)
	var toolbar := HBoxContainer.new()
	toolbar.name = "TimelineToolbar"
	toolbar.add_theme_constant_override("separation", 8)
	toolbar.add_theme_stylebox_override("panel", _clay_sb(SPT_EDITOR_PANEL, 6, 9, 7, 0, 0))
	_drawer_timeline_tab.add_child(toolbar)

	var title := Label.new()
	title.text = "Timeline"
	title.add_theme_font_override("font", _clay_font_bold())
	title.add_theme_color_override("font_color", SPT_EDITOR_TEXT)
	toolbar.add_child(title)

	toolbar.add_child(_make_timeline_legend_chip(
		"Release",
		Color("14532D"),
		Color("22C55E"),
		"Skill execution window"
	))
	toolbar.add_child(_make_timeline_legend_chip(
		"Cooldown",
		Color("334155"),
		Color("94A3B8"),
		"Same skill cannot be reused before this ends"
	))

	var add_btn := _make_timeline_tool_button("Add", "Create a keyframe at the current timeline cursor")
	add_btn.pressed.connect(_on_timeline_add_keyframe_pressed)
	toolbar.add_child(add_btn)
	_timeline_add_button = add_btn

	var delete_btn := _make_timeline_tool_button("Del", "Delete selected keyframe")
	delete_btn.pressed.connect(func() -> void:
		if _selected_spt_actor_idx >= 0 and _selected_spt_kf_idx >= 0:
			_remove_keyframe(_selected_spt_actor_idx, _selected_spt_kf_idx)
	)
	toolbar.add_child(delete_btn)
	_timeline_delete_button = delete_btn

	var divider := VSeparator.new()
	toolbar.add_child(divider)

	var step_label := Label.new()
	step_label.text = "Step %dms" % KF_TIME_STEP_MS
	step_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
	toolbar.add_child(step_label)

	var span_label := Label.new()
	span_label.text = "Span"
	span_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
	toolbar.add_child(span_label)

	var span_input := SpinBox.new()
	span_input.name = "TimelineSpanOverride"
	span_input.min_value = 0.0
	span_input.max_value = 60000.0
	span_input.step = 100.0
	span_input.suffix = "ms"
	span_input.custom_minimum_size = Vector2(120, 0)
	toolbar.add_child(span_input)
	_spt_max_override_input = span_input

	var auto_label := Label.new()
	auto_label.name = "TimelineAutoSpan"
	auto_label.text = "auto = 1000 ms"
	auto_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
	toolbar.add_child(auto_label)
	_spt_max_auto_label = auto_label

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var status_label := Label.new()
	status_label.text = "Status: Editing"
	status_label.add_theme_color_override("font_color", Color("60A5FA"))
	status_label.add_theme_font_override("font", _clay_font_bold())
	toolbar.add_child(status_label)
	_timeline_status_label = status_label

	var timeline_scroll := ScrollContainer.new()
	timeline_scroll.name = "TimelineScroll"
	timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline_scroll.add_theme_stylebox_override("panel", _clay_sb(SPT_EDITOR_BG, 6, 0, 0, 0, 0))
	_drawer_timeline_tab.add_child(timeline_scroll)

	var timeline_content := VBoxContainer.new()
	timeline_content.name = "TimelineContent"
	timeline_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_content.add_theme_constant_override("separation", 4)
	timeline_scroll.add_child(timeline_content)

	var ruler_row := HBoxContainer.new()
	ruler_row.name = "TimelineRulerRow"
	ruler_row.add_theme_constant_override("separation", 0)
	timeline_content.add_child(ruler_row)

	var ruler_spacer := Control.new()
	ruler_spacer.custom_minimum_size = Vector2(SPT_ACTOR_LABEL_W, SPT_RULER_H)
	ruler_row.add_child(ruler_spacer)

	var ruler := Control.new()
	ruler.name = "TimelineRuler"
	ruler.custom_minimum_size = Vector2(_spt_track_width(), SPT_RULER_H)
	ruler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ruler.draw.connect(func() -> void: _draw_spt_ruler_on(ruler))
	ruler.resized.connect(func() -> void: _rebuild_spt_ruler_labels(ruler))
	ruler_row.add_child(ruler)
	_spt_ruler = ruler
	call_deferred("_rebuild_spt_ruler_labels", ruler)

	var tracks := VBoxContainer.new()
	tracks.name = "TimelineTracksContainer"
	tracks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracks.add_theme_constant_override("separation", 4)
	timeline_content.add_child(tracks)
	_spt_tracks_container = tracks


func _make_timeline_tool_button(text: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(42, 30)
	btn.add_theme_stylebox_override("normal", _outlined_sb(Color("243142"), Color("334155"), 5, 7, 4))
	btn.add_theme_stylebox_override("hover", _outlined_sb(Color("2F4056"), Color("60A5FA"), 5, 7, 4))
	btn.add_theme_stylebox_override("pressed", _outlined_sb(Color("1D4ED8"), Color("93C5FD"), 5, 7, 4))
	btn.add_theme_stylebox_override("disabled", _outlined_sb(Color("1F2937"), Color("334155"), 5, 7, 4))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", SPT_EDITOR_TEXT)
	btn.add_theme_color_override("font_hover_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_disabled_color", Color("64748B"))
	return btn


func _make_timeline_legend_chip(
	text: String, fill: Color, border: Color, tooltip: String
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.tooltip_text = tooltip
	panel.add_theme_stylebox_override("panel", _outlined_sb(fill, border, 5, 7, 3))
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _clay_font_bold())
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("E5E7EB"))
	panel.add_child(label)
	return panel


func _build_drawer_scene_tab() -> void:
	var scene_scroll := ScrollContainer.new()
	scene_scroll.name = "Scene"
	scene_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scene_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scene_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer_tabs.add_child(scene_scroll)

	var scene_vbox := get_node_or_null("ConfigUI/Root/LeftPanel/InspectorVBox/InspectorTabs/Scene/SceneVBox") as VBoxContainer
	if scene_vbox == null:
		return
	_reparent_control(scene_vbox, scene_scroll)


func _build_drawer_run_tab() -> void:
	var run_tab := VBoxContainer.new()
	run_tab.name = "Run"
	run_tab.add_theme_constant_override("separation", 8)
	run_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer_tabs.add_child(run_tab)

	var title := Label.new()
	title.text = "Run Config"
	title.add_theme_font_override("font", _clay_font_bold())
	run_tab.add_child(title)
	_reparent_control(_max_ticks_input.get_parent() as Control, run_tab)
	_reparent_control(_speed_input.get_parent() as Control, run_tab)


func _reparent_control(control: Control, new_parent: Control) -> void:
	if control == null or new_parent == null:
		return
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	new_parent.add_child(control)
	control.visible = true
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _init_control_toggle_button(root: Control) -> void:
	_control_toggle_button = Button.new()
	_control_toggle_button.name = "ControlDockToggleButton"
	_control_toggle_button.custom_minimum_size = Vector2(28, 44)
	_control_toggle_button.focus_mode = Control.FOCUS_NONE
	_control_toggle_button.pressed.connect(_on_control_toggle_pressed)
	root.add_child(_control_toggle_button)
	_style_floating_toggle_button(_control_toggle_button)
	_set_controls_collapsed(_controls_collapsed)


func _init_details_popup(root: Control) -> void:
	_details_popup = PanelContainer.new()
	_details_popup.name = "DetailsPopup"
	_details_popup.visible = false
	_details_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_details_popup)

	var popup_vbox := VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 8)
	_details_popup.add_child(popup_vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	popup_vbox.add_child(header)

	var title := Label.new()
	title.text = "Details"
	title.add_theme_font_override("font", _clay_font_bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.name = "DetailsCloseButton"
	close_btn.text = "x"
	close_btn.tooltip_text = "Close details"
	close_btn.custom_minimum_size = Vector2(30, 28)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.set_meta("always_enabled", true)
	close_btn.pressed.connect(_close_details_popup)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup_vbox.add_child(scroll)

	_details_popup_body = VBoxContainer.new()
	_details_popup_body.add_theme_constant_override("separation", 8)
	_details_popup_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_details_popup_body)


func _init_signals() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_replay_button.pressed.connect(_on_replay_pressed)
	if _inspector_tabs != null:
		_inspector_tabs.tab_changed.connect(_on_inspector_tab_changed)
	_console_toggle_button.pressed.connect(_on_console_toggle_pressed)
	_actor_add_enemy_button.pressed.connect(func() -> void: _add_actor_at_next_free("B"))
	_actor_add_ally_button.pressed.connect(func() -> void: _add_actor_at_next_free("A"))
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
	# SkillPreviewTimeline span override + ruler 自绘。
	# Override 警告在 mutation 点 emit, 不放 _spt_max_ms() getter — 否则每次 redraw
	# 都会盖掉用户正在看的 status。
	_spt_max_override_input.value_changed.connect(func(v: float) -> void:
		_spt_max_override = int(v)
		_warn_if_override_below_keyframes()
		_rebuild_spt_ui()
	)


func _apply_setup_inspector_layout() -> void:
	_set_workspace_mode(WORKSPACE_MODE_SETUP)


func _apply_timeline_workspace_layout() -> void:
	_set_workspace_mode(WORKSPACE_MODE_TIMELINE)
	_set_drawer_tab("Timeline")
	_set_console_expanded(true)


func _apply_playback_inspector_layout() -> void:
	_set_workspace_mode(WORKSPACE_MODE_PLAYBACK)


func _set_workspace_mode(mode: String) -> void:
	_workspace_mode = mode
	_playback_mode = mode == WORKSPACE_MODE_PLAYBACK
	if _inspector_tabs != null:
		_inspector_tabs.current_tab = 0
	_update_timeline_mode_buttons()
	_refresh_character_panel()
	_update_workspace_layout()
	if mode == WORKSPACE_MODE_TIMELINE:
		_rebuild_spt_ui()


func _on_inspector_tab_changed(tab_idx: int) -> void:
	if tab_idx == 1:
		_apply_timeline_workspace_layout()


func _update_timeline_mode_buttons() -> void:
	_clear_spt_cursor_if_invalid()
	var editable := not _playback_mode and not _is_playing
	var target_actor_idx := _timeline_add_target_actor_idx()
	var target_time_ms := _timeline_add_target_time_ms(target_actor_idx)
	if _timeline_add_button != null:
		var can_add := editable and target_actor_idx >= 0 and target_actor_idx < _actors.size()
		_timeline_add_button.disabled = not can_add
		if can_add:
			_timeline_add_button.text = "Add @ %dms" % target_time_ms
			_timeline_add_button.tooltip_text = "Create keyframe on %s at %dms" % [
				_role_id_for(target_actor_idx), target_time_ms,
			]
		else:
			_timeline_add_button.text = "Add"
			_timeline_add_button.tooltip_text = "Select an actor track before adding"
	if _timeline_delete_button != null:
		_timeline_delete_button.disabled = not editable \
				or _selected_spt_actor_idx < 0 \
				or _selected_spt_kf_idx < 0
	if _timeline_status_label != null:
		_timeline_status_label.text = _timeline_status_text()


func _timeline_add_target_actor_idx() -> int:
	if _spt_cursor_actor_idx >= 0 and _spt_cursor_actor_idx < _actors.size():
		return _spt_cursor_actor_idx
	if _selected_kind == SELECT_KEYFRAME \
			and _selected_spt_actor_idx >= 0 \
			and _selected_spt_actor_idx < _actors.size():
		return _selected_spt_actor_idx
	if _selected_kind == SELECT_ACTOR \
			and _selected_actor_idx >= 0 \
			and _selected_actor_idx < _actors.size():
		return _selected_actor_idx
	return -1


func _timeline_add_target_time_ms(actor_idx: int) -> int:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return 0
	if _spt_cursor_actor_idx == actor_idx:
		return _spt_cursor_time_ms
	return _next_keyframe_time_for(actor_idx)


func _timeline_status_text() -> String:
	if _is_playing or _playback_mode:
		return "Playback"
	if _selected_spt_actor_idx >= 0 \
			and _selected_spt_actor_idx < _actors.size() \
			and _selected_spt_kf_idx >= 0:
		var track: Array = (_actors[_selected_spt_actor_idx] as Dictionary).get("track", []) as Array
		if _selected_spt_kf_idx < track.size():
			var kf: Dictionary = track[_selected_spt_kf_idx] as Dictionary
			var skill_id := str(kf.get("skill", ""))
			var skill_cfg := HexBattleSkillIndex.get_by_id(skill_id)
			var skill_name := skill_cfg.display_name if skill_cfg != null else skill_id
			return "Selected %s @ %dms" % [skill_name, int(kf.get("time_ms", 0))]
	if _spt_cursor_actor_idx >= 0 and _spt_cursor_actor_idx < _actors.size():
		return "Cursor %s @ %dms" % [_role_id_for(_spt_cursor_actor_idx), _spt_cursor_time_ms]
	if _selected_spt_actor_idx >= 0 and _selected_spt_actor_idx < _actors.size():
		return "Selected %s" % _role_id_for(_selected_spt_actor_idx)
	return "Ready"


func _refresh_runtime_layout() -> void:
	_refresh_character_panel()
	_update_workspace_layout()


func _update_workspace_layout() -> void:
	if _left_panel == null or _console_panel == null:
		return
	var control_width := _current_control_width()
	_left_panel.visible = not _controls_collapsed
	_left_panel.anchor_left = 1.0
	_left_panel.anchor_right = 1.0
	_left_panel.anchor_top = 0.0
	_left_panel.anchor_bottom = 0.0
	_left_panel.custom_minimum_size = Vector2(CONTROL_DOCK_WIDTH, CONTROL_DOCK_HEIGHT)
	if _inspector_tabs != null:
		_inspector_tabs.custom_minimum_size = Vector2(0.0, 0.0)
	_left_panel.offset_left = -INSPECTOR_MARGIN - control_width
	_left_panel.offset_top = INSPECTOR_MARGIN
	_left_panel.offset_right = -INSPECTOR_MARGIN
	_left_panel.offset_bottom = INSPECTOR_MARGIN + CONTROL_DOCK_HEIGHT

	_console_panel.offset_left = INSPECTOR_MARGIN
	_console_panel.offset_right = -(_right_reserved_width() + WORKSPACE_GAP + INSPECTOR_MARGIN)
	_console_panel.offset_bottom = -INSPECTOR_MARGIN
	_console_panel.offset_top = -(_drawer_height() + INSPECTOR_MARGIN)
	_layout_drawer_toggle_button()
	_layout_control_toggle_button()
	_layout_character_panel()
	_layout_details_popup()
	# 不在 layout 切换时 reframe camera —— Start/Replay/Reset 都会过这条路径,
	# 用户不希望相机被动归位。初始 frame 在 _setup_camera_and_env 做一次,
	# 之后想归位按 Space。


func _layout_drawer_toggle_button() -> void:
	if _console_toggle_button == null:
		return
	_console_toggle_button.anchor_left = 0.0
	_console_toggle_button.anchor_right = 0.0
	_console_toggle_button.anchor_top = 1.0
	_console_toggle_button.anchor_bottom = 1.0
	_console_toggle_button.offset_left = INSPECTOR_MARGIN + 6.0
	_console_toggle_button.offset_right = INSPECTOR_MARGIN + 42.0
	_console_toggle_button.offset_top = -(_drawer_height() + INSPECTOR_MARGIN + 14.0)
	_console_toggle_button.offset_bottom = -(_drawer_height() + INSPECTOR_MARGIN - 16.0)


func _layout_control_toggle_button() -> void:
	if _control_toggle_button == null:
		return
	_control_toggle_button.anchor_left = 1.0
	_control_toggle_button.anchor_right = 1.0
	_control_toggle_button.anchor_top = 0.0
	_control_toggle_button.anchor_bottom = 0.0
	var control_width := _current_control_width()
	var left_edge := -INSPECTOR_MARGIN - control_width
	_control_toggle_button.offset_left = left_edge - 28.0
	_control_toggle_button.offset_right = left_edge
	_control_toggle_button.offset_top = INSPECTOR_MARGIN + 42.0
	_control_toggle_button.offset_bottom = INSPECTOR_MARGIN + 86.0


func _layout_character_panel() -> void:
	if _character_panel == null:
		return
	_character_panel.anchor_left = 1.0
	_character_panel.anchor_right = 1.0
	_character_panel.anchor_top = 0.0
	_character_panel.anchor_bottom = 1.0
	var top_gap := INSPECTOR_MARGIN
	if not _controls_collapsed:
		top_gap += CONTROL_DOCK_HEIGHT + WORKSPACE_GAP
	_character_panel.offset_right = -INSPECTOR_MARGIN
	_character_panel.offset_left = -INSPECTOR_MARGIN - CHARACTER_PANEL_WIDTH
	_character_panel.offset_top = top_gap
	_character_panel.offset_bottom = -INSPECTOR_MARGIN
	_character_panel.custom_minimum_size = Vector2(CHARACTER_PANEL_WIDTH, 0.0)


func _layout_details_popup() -> void:
	if _details_popup == null:
		return
	_details_popup.anchor_left = 1.0
	_details_popup.anchor_right = 1.0
	_details_popup.anchor_top = 0.0
	_details_popup.anchor_bottom = 1.0
	var right_gap := INSPECTOR_MARGIN
	var top_gap := INSPECTOR_MARGIN
	if _controls_collapsed:
		right_gap += 28.0 + WORKSPACE_GAP
		top_gap += 54.0
	else:
		top_gap += CONTROL_DOCK_HEIGHT + WORKSPACE_GAP
	_details_popup.offset_right = -right_gap
	_details_popup.offset_left = -right_gap - DETAILS_POPUP_WIDTH
	_details_popup.offset_top = top_gap
	_details_popup.offset_bottom = -(_drawer_height() + INSPECTOR_MARGIN + WORKSPACE_GAP)
	_details_popup.custom_minimum_size = Vector2(DETAILS_POPUP_WIDTH, 0.0)


func _current_control_width() -> float:
	if _controls_collapsed:
		return CONTROL_DOCK_COLLAPSED_WIDTH
	return CONTROL_DOCK_WIDTH


func _right_reserved_width() -> float:
	var reserved_width := _current_control_width()
	if _character_panel != null and _character_panel.visible:
		reserved_width = maxf(reserved_width, CHARACTER_PANEL_WIDTH)
	if _details_popup != null and _details_popup.visible:
		reserved_width = maxf(reserved_width, DETAILS_POPUP_WIDTH)
	return reserved_width


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
	var stage_left := INSPECTOR_MARGIN
	var stage_right := maxf(stage_left + 1.0, viewport_size.x - _right_reserved_width() - WORKSPACE_GAP - INSPECTOR_MARGIN)
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


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return false
	if focus_owner is LineEdit:
		return (focus_owner as LineEdit).editable
	if focus_owner is TextEdit:
		return (focus_owner as TextEdit).editable
	return false


func _process_stage_camera_input(_delta: float) -> void:
	if _camera_rig == null:
		return
	# 只在文字编辑控件拿焦点时 block (SpinBox/LineEdit/TextEdit 里输入数值/文本),
	# 否则 Button/OptionButton 点过一次就保持焦点, WASD 永远进不来。
	if _is_text_input_focused():
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
	var stage_right := get_viewport().get_visible_rect().size.x - _right_reserved_width() - WORKSPACE_GAP - INSPECTOR_MARGIN
	return mouse_pos.x >= INSPECTOR_MARGIN and mouse_pos.x <= stage_right


func _is_mouse_over_blocking_ui() -> bool:
	return (
		_is_mouse_inside_control(_left_panel)
		or _is_mouse_inside_control(_console_panel)
		or _is_mouse_inside_control(_character_panel)
		or _is_mouse_inside_control(_details_popup)
	)


func _is_mouse_inside_control(control: Control) -> bool:
	if control == null or not control.visible:
		return false
	return control.get_global_rect().has_point(get_viewport().get_mouse_position())


func _init_default_actors() -> void:
	# 默认给 caster 挂一条 t=0 Strike keyframe (target=auto), 跟改造前 baseline 等价。
	# dummy 默认空 track + 空 passives, 用户通过 Actors 详情面板按需添加。
	var default_active_id := _default_active_skill_id()
	_actors = [
		{
			"role": "caster", "team": "A", "class": "WARRIOR",
			"pos": [0, 0], "hp": 0.0, "atk": 0.0,
			"passives": [] as Array[String],
			"track": [_make_default_keyframe(default_active_id)] if default_active_id != "" else [] as Array[Dictionary],
		},
		{
			"role": "dummy", "team": "B", "class": "WARRIOR",
			"pos": [2, 0], "hp": 100.0, "atk": 0.0,
			"passives": [] as Array[String],
			"track": [] as Array[Dictionary],
		},
	]
	_select_actor_at(0, false)
	_rebuild_inspector()


## 默认 active skill: HexBattleStrike 优先, 没有则取第一个。空场则空 (允许场上无技能)。
static func _default_active_skill_id() -> String:
	for cfg in HexBattleSkillIndex.actives():
		if cfg.config_id == "skill_strike":
			return cfg.config_id
	var actives := HexBattleSkillIndex.actives()
	return actives[0].config_id if not actives.is_empty() else ""


static func _make_default_keyframe(skill_id: String) -> Dictionary:
	return {
		"time_ms": 0,
		"skill": skill_id,
		"target": {"mode": "auto", "index": 0, "q": 0, "r": 0},
	}


# ========== 数据模型操作 ==========

func _add_actor(role: String, team: String, cls: String, q: int, r: int) -> void:
	var coord := _nearest_free_coord_for(q, r, team, -1)
	if not coord.is_valid():
		_set_status("No free hex available")
		return
	_actors.append({
		"role": role, "team": team, "class": cls,
		"pos": [coord.q, coord.r], "hp": 100.0, "atk": 0.0,
		"passives": [] as Array[String],
		"track": [] as Array[Dictionary],
	})
	_select_actor_at(_actors.size() - 1, false)
	_rebuild_inspector()
	if _is_playing:
		return
	# 增量 spawn: 不动其它 actor view,新 view 直接落在 _actors 末尾。
	_spawn_one_actor(_actors.size() - 1)


func _add_actor_at_next_free(team: String) -> void:
	var start_q := 2 if team == "B" else -1
	_add_actor("dummy", team, "WARRIOR", start_q, 0)


func _add_stone_wall(q: int, r: int) -> void:
	var coord := HexCoord.new(q, r)
	if not _can_place_environment_at_for(coord, -1):
		_set_status("StoneWall placement blocked at (%d, %d)" % [q, r])
		_log("[color=yellow]StoneWall placement blocked at (%d, %d)[/color]" % [q, r])
		return
	_environments.append({
		"type": ENV_STONE_WALL,
		"pos": [coord.q, coord.r],
	})
	var idx := _environments.size() - 1
	_select_environment_at(idx, false)
	if _is_playing:
		return
	if _spawn_one_environment(idx):
		_set_status("StoneWall placed at (%d, %d)" % [q, r])
		_rebuild_inspector()
	else:
		_environments.remove_at(idx)
		_select_hex_at(coord, false)
		_rebuild_inspector()


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
	if occupant_idx != -1 and occupant_idx != actor_idx:
		return false
	return _find_environment_idx_at(coord.q, coord.r) == -1


func _can_place_environment_at_for(coord: HexCoord, environment_idx: int) -> bool:
	if coord == null or not coord.is_valid():
		return false
	if UGridMap.model != null and not UGridMap.model.has_tile(coord):
		return false
	if _find_actor_idx_at(coord.q, coord.r) != -1:
		return false
	var occupant_idx := _find_environment_idx_at(coord.q, coord.r)
	return occupant_idx == -1 or occupant_idx == environment_idx


func _remove_actor_at(idx: int) -> void:
	if idx <= 0 or idx >= _actors.size():
		return  # caster (idx 0) 不可删
	var removed_coord := _actor_coord(idx)
	var removed_selection := (_selected_kind == SELECT_ACTOR and _selected_actor_idx == idx) \
			or (_selected_kind == SELECT_KEYFRAME and _selected_spt_actor_idx == idx)

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
		_selected_actor_idx = -1
	if _selected_spt_actor_idx > idx:
		_selected_spt_actor_idx -= 1
	elif _selected_spt_actor_idx == idx:
		_selected_spt_actor_idx = -1
		_selected_spt_kf_idx = -1
	if removed_selection:
		_select_hex_at(removed_coord, false)
	_rebuild_role_id_mapping()
	_rebuild_inspector()


func _remove_environment_at(idx: int) -> void:
	if idx < 0 or idx >= _environments.size():
		return
	var env_pos: Array = (_environments[idx] as Dictionary).get("pos", [0, 0])
	var removed_coord := HexCoord.new(int(env_pos[0]), int(env_pos[1]))
	var removed_selection := _selected_kind == SELECT_ENVIRONMENT and _selected_environment_idx == idx
	if not _is_playing and idx < _environment_ids.size():
		var env_id := _environment_ids[idx]
		if env_id != "":
			_world.remove_actor(env_id)
		_environment_ids.remove_at(idx)
	_environments.remove_at(idx)
	if _selected_environment_idx > idx:
		_selected_environment_idx -= 1
	if removed_selection:
		_select_hex_at(removed_coord, false)
	_set_status("StoneWall removed")
	_rebuild_inspector()


func _find_actor_idx_at(q: int, r: int) -> int:
	for i in _actors.size():
		var pos: Array = _actors[i]["pos"]
		if int(pos[0]) == q and int(pos[1]) == r:
			return i
	return -1


func _find_environment_idx_at(q: int, r: int) -> int:
	for i in _environments.size():
		var pos: Array = _environments[i]["pos"]
		if int(pos[0]) == q and int(pos[1]) == r:
			return i
	return -1


func _move_caster_to(q: int, r: int) -> void:
	var coord := _nearest_free_coord_for(q, r, _actors[0]["team"] as String, 0)
	if not coord.is_valid():
		_set_status("No free hex available")
		return
	_actors[0]["pos"] = [coord.q, coord.r]
	_select_actor_at(0, false)
	_rebuild_inspector()
	if _is_playing:
		return
	_apply_actor_position_change(0, coord.q, coord.r)


# ========== UI: Details ==========

func _rebuild_actors_ui() -> void:
	_inspector_rebuild_queued = false
	for child in _actors_container.get_children():
		child.queue_free()
	_clear_selection_if_invalid()
	_refresh_details_popup()
	_refresh_character_panel()


func _refresh_details_popup() -> void:
	if _details_popup == null or _details_popup_body == null:
		return
	if _character_panel != null:
		_clear_selection_if_invalid()
		_details_popup.visible = false
		return
	for child in _details_popup_body.get_children():
		child.queue_free()
	_clear_selection_if_invalid()
	if _selected_kind == SELECT_NONE or _details_popup_user_closed:
		_details_popup.visible = false
		return
	var details := _build_details_panel()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_popup_body.add_child(details)
	_details_popup.visible = true
	_layout_details_popup()


func _refresh_character_panel() -> void:
	if _character_panel == null or _character_panel_body == null:
		return
	for child in _character_panel_body.get_children():
		child.queue_free()
	_clear_selection_if_invalid()
	if _character_panel_mode_label != null:
		_character_panel_mode_label.text = _character_panel_mode_text()

	if _selected_kind == SELECT_KEYFRAME:
		_character_panel_body.add_child(_build_character_selected_keyframe_panel())
	elif _selected_kind == SELECT_HEX:
		_character_panel_body.add_child(_build_character_hex_context_panel())
	elif _selected_kind == SELECT_ENVIRONMENT:
		_character_panel_body.add_child(_build_character_environment_context_panel())

	var list_title := Label.new()
	list_title.text = "Roster"
	list_title.add_theme_font_override("font", _clay_font_bold())
	list_title.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	_character_panel_body.add_child(list_title)

	if _actors.is_empty():
		_character_panel_body.add_child(_make_character_hint_label("No actors"))
	else:
		for i in _actors.size():
			_character_panel_body.add_child(_build_character_actor_card(i))

	var editable := not _playback_mode and not _is_playing
	_character_panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if editable else 0.78)
	_set_controls_editable(_character_panel, editable)


func _character_panel_mode_text() -> String:
	if _playback_mode:
		return "Playback"
	if _workspace_mode == WORKSPACE_MODE_TIMELINE:
		return "Timeline"
	return "Setup"


func _build_character_selected_keyframe_panel() -> PanelContainer:
	var panel := _make_character_panel_card(Color("F8FAFC"), Color("F59E0B"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Selected Keyframe"
	title.add_theme_font_override("font", _clay_font_bold())
	title.add_theme_color_override("font_color", Color("92400E"))
	box.add_child(title)
	var details := _build_keyframe_detail_panel()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(details)
	return panel


func _build_character_hex_context_panel() -> PanelContainer:
	var panel := _make_character_panel_card(Color("FFFFFF"), Color("CBD5E1"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Empty Hex"
	title.add_theme_font_override("font", _clay_font_bold())
	box.add_child(title)
	if _selected_hex != null:
		box.add_child(_make_detail_label("Coord", "(%d, %d)" % [_selected_hex.q, _selected_hex.r]))
		box.add_child(_make_character_hint_label("Right-click the hex to add an actor or wall."))
	return panel


func _build_character_environment_context_panel() -> PanelContainer:
	var panel := _make_character_panel_card(Color("FFFFFF"), Color("CBD5E1"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	if _selected_environment_idx < 0 or _selected_environment_idx >= _environments.size():
		box.add_child(_make_character_hint_label("No environment selected"))
		return panel
	var data: Dictionary = _environments[_selected_environment_idx]
	var title := Label.new()
	title.text = "Wall"
	title.add_theme_font_override("font", _clay_font_bold())
	box.add_child(title)
	var pos: Array = data.get("pos", [0, 0])
	box.add_child(_make_detail_label("Coord", "(%d, %d)" % [int(pos[0]), int(pos[1])]))
	var remove_btn := Button.new()
	remove_btn.text = "Remove Wall"
	remove_btn.pressed.connect(func() -> void:
		if _selected_environment_idx >= 0 and _selected_environment_idx < _environments.size():
			_remove_environment_at(_selected_environment_idx)
	)
	box.add_child(remove_btn)
	return panel


func _build_character_actor_card(idx: int) -> PanelContainer:
	var highlighted := _is_character_actor_selected(idx)
	var expanded := _should_expand_character_actor_card(idx)
	var border := _actor_track_color(idx, 1.0) if highlighted else Color("D8DEE8")
	var bg := Color("F8FAFC") if highlighted else Color("FFFFFF")
	var panel := _make_character_panel_card(bg, border)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 7)
	box.add_child(header)

	var select_btn := Button.new()
	select_btn.text = _actor_timeline_label(idx)
	select_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_btn.tooltip_text = "Select actor"
	select_btn.set_meta("always_enabled", true)
	select_btn.pressed.connect(func() -> void:
		if idx >= 0 and idx < _actors.size():
			_select_actor_at(idx)
	)
	header.add_child(select_btn)

	var data: Dictionary = _actors[idx]
	header.add_child(_make_character_chip(_actor_role_label(data), _actor_track_color(idx, 0.14), _actor_track_color(idx, 0.8)))
	header.add_child(_make_character_chip(str(data.get("team", "?")), _team_chip_bg(str(data.get("team", "A"))), _team_chip_border(str(data.get("team", "A")))))

	box.add_child(_build_character_hp_row(idx))

	var pos: Array = data.get("pos", [0, 0])
	var meta := Label.new()
	meta.text = "pos (%d, %d)  ·  %d keyframes" % [
		int(pos[0]), int(pos[1]), (data.get("track", []) as Array).size(),
	]
	meta.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	meta.add_theme_font_size_override("font_size", 12)
	box.add_child(meta)

	if expanded:
		if _playback_mode:
			box.add_child(_build_character_runtime_section(idx))
		else:
			box.add_child(_build_character_actor_editor(idx))
	return panel


func _should_expand_character_actor_card(idx: int) -> bool:
	if idx < 0 or idx >= _actors.size():
		return false
	if _selected_kind == SELECT_ACTOR:
		return _selected_actor_idx == idx
	return false


func _build_character_hp_row(idx: int) -> HBoxContainer:
	var stats := _actor_stats_for_panel(idx)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.custom_minimum_size = Vector2(28, 0)
	hp_label.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	row.add_child(hp_label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(1.0, float(stats.get("max_hp", 1.0)))
	bar.value = clampf(float(stats.get("hp", 0.0)), 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var value := Label.new()
	value.text = "%d / %d" % [int(stats.get("hp", 0.0)), int(stats.get("max_hp", 0.0))]
	value.custom_minimum_size = Vector2(64, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _build_character_actor_editor(idx: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var data: Dictionary = _actors[idx]
	var class_opt := OptionButton.new()
	class_opt.fit_to_longest_item = false
	for cls in CLASS_NAMES:
		class_opt.add_item(cls)
	class_opt.selected = max(0, CLASS_NAMES.find(str(data.get("class", "WARRIOR"))))
	class_opt.item_selected.connect(func(i: int) -> void:
		if idx < 0 or idx >= _actors.size():
			return
		_actors[idx]["class"] = CLASS_NAMES[i]
		if not _is_playing:
			_apply_actor_class_change(idx)
		_queue_inspector_rebuild()
	)
	box.add_child(_build_actor_detail_field("Class", class_opt))

	var pos: Array = data.get("pos", [0, 0])
	box.add_child(_build_actor_detail_field("Q", _make_actor_spin(idx, "q", float(pos[0]), -20, 20, false, 0)))
	box.add_child(_build_actor_detail_field("R", _make_actor_spin(idx, "r", float(pos[1]), -20, 20, false, 0)))
	box.add_child(_build_actor_detail_field("HP", _make_actor_spin(idx, "hp", float(data.get("hp", 0.0)), 0, 9999, true, 0)))
	box.add_child(_build_actor_detail_field("ATK", _make_actor_spin(idx, "atk", float(data.get("atk", 0.0)), 0, 9999, true, 0)))
	box.add_child(_build_actor_passive_section(idx))
	box.add_child(_build_character_track_controls(idx))

	if str(data.get("role", "")) != "caster":
		var remove_btn := Button.new()
		remove_btn.text = "Remove Actor"
		remove_btn.pressed.connect(func() -> void:
			if idx > 0 and idx < _actors.size():
				_remove_actor_at(idx)
		)
		box.add_child(remove_btn)
	return box


func _build_character_track_controls(idx: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "Skill Track"
	title.add_theme_font_override("font", _clay_font_bold())
	title.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	box.add_child(title)

	var track: Array = (_actors[idx] as Dictionary).get("track", []) as Array
	if track.is_empty():
		box.add_child(_make_character_hint_label("No actions"))
	else:
		for kf_idx in track.size():
			box.add_child(_build_keyframe_summary_row(idx, kf_idx))

	var add_btn := Button.new()
	add_btn.text = "+ Add Action"
	add_btn.pressed.connect(func() -> void:
		if idx < 0 or idx >= _actors.size():
			return
		var new_idx := _add_keyframe_at(idx, _next_keyframe_time_for(idx))
		if new_idx >= 0:
			_select_spt_keyframe(idx, new_idx)
			_apply_timeline_workspace_layout()
	)
	box.add_child(add_btn)
	return box


func _build_character_runtime_section(idx: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 5)
	var statuses := _actor_status_labels(idx)
	if statuses.is_empty():
		chips.add_child(_make_character_chip("No status", Color("F8FAFC"), Color("CBD5E1")))
	else:
		for status_text in statuses:
			chips.add_child(_make_character_chip(status_text, _status_chip_bg(status_text), _status_chip_border(status_text)))
	box.add_child(chips)

	var history_title := Label.new()
	history_title.text = "Damage History"
	history_title.add_theme_font_override("font", _clay_font_bold())
	history_title.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	box.add_child(history_title)
	var history := _actor_history_lines(idx, 5)
	if history.is_empty():
		box.add_child(_make_character_hint_label("No damage or heal events"))
	else:
		for line in history:
			var label := Label.new()
			label.text = line
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", CLAY_TEXT)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(label)
	return box


func _make_character_panel_card(bg: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := _outlined_sb(bg, border, 8, 10, 9)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return panel


func _make_character_chip(text: String, bg: Color, border: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _clay_font_bold())
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", border.darkened(0.35))
	label.add_theme_stylebox_override("normal", _outlined_sb(bg, border, 5, 7, 3))
	return label


func _make_character_hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	label.add_theme_font_size_override("font_size", 12)
	return label


func _is_character_actor_selected(idx: int) -> bool:
	if _selected_kind == SELECT_ACTOR:
		return _selected_actor_idx == idx
	if _selected_kind == SELECT_KEYFRAME:
		return _selected_spt_actor_idx == idx
	return false


func _actor_id_for_idx(idx: int) -> String:
	if idx < 0 or idx >= _actor_ids.size():
		return ""
	return _actor_ids[idx]


func _character_actor_for_idx(idx: int) -> CharacterActor:
	var actor_id := _actor_id_for_idx(idx)
	if actor_id == "" or _world == null:
		return null
	return _world.get_actor(actor_id) as CharacterActor


func _actor_stats_for_panel(idx: int) -> Dictionary:
	var actor := _character_actor_for_idx(idx)
	if actor != null and actor.attribute_set != null:
		return {
			"hp": actor.attribute_set.hp,
			"max_hp": actor.attribute_set.max_hp,
			"atk": actor.attribute_set.atk,
		}
	if idx < 0 or idx >= _actors.size():
		return {"hp": 0.0, "max_hp": 0.0, "atk": 0.0}
	var data: Dictionary = _actors[idx]
	var max_hp := float(data.get("hp", 0.0))
	if max_hp <= 0.0:
		max_hp = 100.0
	return {
		"hp": max_hp,
		"max_hp": max_hp,
		"atk": float(data.get("atk", 0.0)),
	}


func _actor_status_labels(idx: int) -> Array[String]:
	var labels: Array[String] = []
	var stats := _actor_stats_for_panel(idx)
	if float(stats.get("hp", 0.0)) <= 0.0:
		labels.append("Defeated")
	var actor := _character_actor_for_idx(idx)
	if actor == null:
		return labels
	var tags := actor.get_tag_snapshot()
	for tag_variant in tags.keys():
		var tag := str(tag_variant)
		var lower_tag := tag.to_lower()
		if lower_tag.contains("cooldown") and not labels.has("Cooldown"):
			labels.append("Cooldown")
		elif lower_tag.contains("poison") and not labels.has("Poison"):
			labels.append("Poison")
		elif (lower_tag.contains("shield") or lower_tag.contains("ward")) and not labels.has("Shield"):
			labels.append("Shield")
		elif lower_tag.contains("inspire") and not labels.has("Inspire"):
			labels.append("Inspire")
	return labels


func _actor_history_lines(idx: int, limit: int) -> Array[String]:
	var actor_id := _actor_id_for_idx(idx)
	var lines: Array[String] = []
	if actor_id == "" or _last_timeline.is_empty():
		return lines
	for entry_variant in _last_timeline.get("timeline", []):
		var entry := entry_variant as Dictionary
		var ms := int(entry.get("frame", 0)) * TICK_INTERVAL_MS
		for ev_variant in entry.get("events", []):
			var ev := ev_variant as Dictionary
			var kind := str(ev.get("kind", ""))
			match kind:
				"damage":
					if str(ev.get("target_actor_id", "")) == actor_id:
						lines.append("%05dms  -%.1f damage from %s" % [
							ms,
							float(ev.get("damage", 0.0)),
							_role_label_for_actor_id(str(ev.get("source_actor_id", ""))),
						])
				"heal":
					if str(ev.get("target_actor_id", "")) == actor_id:
						lines.append("%05dms  +%.1f heal" % [
							ms,
							float(ev.get("heal_amount", 0.0)),
						])
				"death":
					if str(ev.get("actor_id", "")) == actor_id:
						lines.append("%05dms  defeated" % ms)
	var result: Array[String] = []
	for i in range(maxi(0, lines.size() - limit), lines.size()):
		result.append(lines[i])
	return result


func _team_chip_bg(team: String) -> Color:
	return Color("DBEAFE") if team == "A" else Color("FEE2E2")


func _team_chip_border(team: String) -> Color:
	return Color("2563EB") if team == "A" else Color("B23B3B")


func _status_chip_bg(status_text: String) -> Color:
	match status_text:
		"Defeated":
			return Color("FEE2E2")
		"Poison":
			return Color("DCFCE7")
		"Shield":
			return Color("DBEAFE")
		"Cooldown":
			return Color("FEF3C7")
		_:
			return Color("F8FAFC")


func _status_chip_border(status_text: String) -> Color:
	match status_text:
		"Defeated":
			return Color("DC2626")
		"Poison":
			return Color("16A34A")
		"Shield":
			return Color("2563EB")
		"Cooldown":
			return Color("D97706")
		_:
			return Color("CBD5E1")


func _close_details_popup() -> void:
	_details_popup_user_closed = true
	if _details_popup != null:
		_details_popup.visible = false


func _open_details_popup() -> void:
	_details_popup_user_closed = false
	_refresh_details_popup()


func _select_actor(idx: int) -> void:
	_select_actor_at(idx)


func _select_actor_at(idx: int, rebuild: bool = true) -> void:
	if idx < 0 or idx >= _actors.size():
		_clear_selection(rebuild)
		return
	_selected_kind = SELECT_ACTOR
	_selected_actor_idx = idx
	_selected_environment_idx = -1
	_selected_hex = _actor_coord(_selected_actor_idx)
	_selected_spt_actor_idx = idx
	_selected_spt_kf_idx = -1
	if _spt_cursor_actor_idx != idx:
		_set_spt_cursor(idx, _next_keyframe_time_for(idx), false)
	_details_popup_user_closed = false
	if rebuild:
		_rebuild_inspector()


func _select_environment_at(idx: int, rebuild: bool = true) -> void:
	if idx < 0 or idx >= _environments.size():
		_clear_selection(rebuild)
		return
	_selected_kind = SELECT_ENVIRONMENT
	_selected_actor_idx = -1
	_selected_environment_idx = idx
	_selected_spt_actor_idx = -1
	_selected_spt_kf_idx = -1
	_set_spt_cursor(-1, 0, false)
	if idx >= 0 and idx < _environments.size():
		var pos: Array = (_environments[idx] as Dictionary).get("pos", [0, 0])
		_selected_hex = HexCoord.new(int(pos[0]), int(pos[1]))
	else:
		_selected_hex = null
	_details_popup_user_closed = false
	if rebuild:
		_rebuild_inspector()


func _clear_selection(rebuild: bool = true) -> void:
	_selected_kind = SELECT_NONE
	_selected_hex = null
	_selected_actor_idx = -1
	_selected_environment_idx = -1
	_selected_spt_actor_idx = -1
	_selected_spt_kf_idx = -1
	_set_spt_cursor(-1, 0, false)
	_details_popup_user_closed = false
	if rebuild:
		_rebuild_inspector()


func _select_hex_at(coord: HexCoord, rebuild: bool = true) -> void:
	if coord == null or not coord.is_valid():
		_clear_selection(rebuild)
		return
	elif _find_actor_idx_at(coord.q, coord.r) >= 0:
		_select_actor_at(_find_actor_idx_at(coord.q, coord.r), rebuild)
		return
	elif _find_environment_idx_at(coord.q, coord.r) >= 0:
		_select_environment_at(_find_environment_idx_at(coord.q, coord.r), rebuild)
		return
	else:
		_selected_kind = SELECT_HEX
		_selected_hex = coord.duplicate()
		_selected_actor_idx = -1
		_selected_environment_idx = -1
		_selected_spt_actor_idx = -1
		_selected_spt_kf_idx = -1
		_set_spt_cursor(-1, 0, false)
		_details_popup_user_closed = false
	if rebuild:
		_rebuild_inspector()


func _clear_selection_if_invalid() -> void:
	match _selected_kind:
		SELECT_ACTOR:
			if _selected_actor_idx < 0 or _selected_actor_idx >= _actors.size():
				_selected_kind = SELECT_NONE
				_selected_actor_idx = -1
		SELECT_ENVIRONMENT:
			if _selected_environment_idx < 0 or _selected_environment_idx >= _environments.size():
				_selected_kind = SELECT_NONE
				_selected_environment_idx = -1
		SELECT_KEYFRAME:
			_clear_spt_selection_if_invalid()
			if _selected_spt_actor_idx < 0 or _selected_spt_kf_idx < 0:
				_selected_kind = SELECT_NONE
		SELECT_HEX:
			if _selected_hex == null or not _selected_hex.is_valid():
				_selected_kind = SELECT_NONE
	if _selected_spt_actor_idx >= _actors.size():
		_selected_spt_actor_idx = -1
		_selected_spt_kf_idx = -1
	_clear_spt_cursor_if_invalid()


func _build_details_panel() -> Control:
	match _selected_kind:
		SELECT_ACTOR:
			if _selected_actor_idx >= 0 and _selected_actor_idx < _actors.size():
				return _build_actor_detail_panel(_selected_actor_idx)
		SELECT_ENVIRONMENT:
			if _selected_environment_idx >= 0 and _selected_environment_idx < _environments.size():
				return _build_environment_detail_panel(_selected_environment_idx)
		SELECT_KEYFRAME:
			return _build_keyframe_detail_panel()
		SELECT_HEX:
			return _build_hex_detail_panel()
	return _build_empty_detail_panel()


func _build_empty_detail_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Details"
	title.add_theme_font_override("font", _clay_font_bold())
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Select a hex, actor, wall, or timeline keyframe"
	hint.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	return box


func _build_hex_detail_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Empty Hex"
	title.add_theme_font_override("font", _clay_font_bold())
	box.add_child(title)
	if _selected_hex != null:
		box.add_child(_make_detail_label("Coord", "(%d, %d)" % [_selected_hex.q, _selected_hex.r]))
		box.add_child(_make_detail_label("Placement", "right-click to add actor or wall"))
	return box


func _build_environment_detail_panel(idx: int) -> Control:
	var data: Dictionary = _environments[idx]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Wall"
	title.add_theme_font_override("font", _clay_font_bold())
	box.add_child(title)
	var pos: Array = data.get("pos", [0, 0])
	box.add_child(_make_detail_label("Type", str(data.get("type", ENV_STONE_WALL))))
	box.add_child(_make_detail_label("Coord", "(%d, %d)" % [int(pos[0]), int(pos[1])]))
	var remove_btn := Button.new()
	remove_btn.text = "Remove Wall"
	remove_btn.pressed.connect(func() -> void: _remove_environment_at(idx))
	box.add_child(remove_btn)
	return box


func _make_detail_label(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(88, 0)
	label.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	row.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	return row


func _build_keyframe_detail_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	_clear_spt_selection_if_invalid()
	if _selected_spt_actor_idx < 0 or _selected_spt_kf_idx < 0:
		return _build_empty_detail_panel()
	var actor_idx := _selected_spt_actor_idx
	var kf_idx := _selected_spt_kf_idx
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx >= track.size():
		return _build_empty_detail_panel()
	var kf: Dictionary = track[kf_idx]
	var title := Label.new()
	title.text = "Keyframe: %s @ %dms" % [_actor_timeline_label(actor_idx), int(kf.get("time_ms", 0))]
	title.add_theme_font_override("font", _clay_font_bold())
	box.add_child(title)
	var skill_cfg := HexBattleSkillIndex.get_by_id(str(kf.get("skill", "")))
	if skill_cfg != null:
		var time_ms := int(kf.get("time_ms", 0))
		var occupy_ms := SkillPreviewValidation.ability_occupy_ms(skill_cfg)
		var cooldown_ms := SkillPreviewValidation.ability_cooldown_ms(skill_cfg)
		box.add_child(_make_detail_label("Release", "%d-%dms" % [time_ms, time_ms + occupy_ms]))
		if cooldown_ms > 0:
			box.add_child(_make_detail_label("Ready", "%dms" % (time_ms + cooldown_ms)))
	if _is_dragging_keyframe(actor_idx, kf_idx):
		box.add_child(_make_detail_label("Drag target", "%dms" % _spt_drag_requested_ms))
	box.add_child(_build_kf_form_row("Time", _build_kf_time_spin(actor_idx, kf_idx)))
	box.add_child(_build_kf_form_row("Skill", _build_kf_skill_opt(actor_idx, kf_idx)))
	var target_label := Label.new()
	target_label.text = "Target"
	target_label.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	box.add_child(target_label)
	box.add_child(_build_keyframe_target_editor(actor_idx, kf_idx))
	var warning := _keyframe_timing_warning(actor_idx, kf_idx)
	if not warning.is_empty():
		var warning_label := Label.new()
		warning_label.text = str(warning.get("message", ""))
		warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning_label.add_theme_color_override("font_color", _spt_warning_color(str(warning.get("type", ""))))
		box.add_child(warning_label)
		if str(warning.get("type", "")) == "cooldown":
			var ready_btn := Button.new()
			ready_btn.text = "Move to ready time"
			ready_btn.pressed.connect(func() -> void: _move_keyframe_to_ready_time(actor_idx, kf_idx))
			box.add_child(ready_btn)
	var delete_btn := Button.new()
	delete_btn.text = "Delete Keyframe"
	delete_btn.pressed.connect(func() -> void: _remove_keyframe(actor_idx, kf_idx))
	box.add_child(delete_btn)
	return box


func _rebuild_details_panel() -> void:
	_rebuild_inspector()


func _queue_inspector_rebuild() -> void:
	if _inspector_rebuild_queued:
		return
	_inspector_rebuild_queued = true
	call_deferred("_rebuild_inspector")


## 同步重建两个 inspector tab。所有 mutation 都走这里, 保证 Actors / SkillPreviewTimeline
## 共用的 _actors 数据源在两边视图都一致。
func _rebuild_inspector() -> void:
	_inspector_rebuild_queued = false
	_rebuild_actors_ui()
	_rebuild_spt_ui()


# ========== UI: SkillPreviewTimeline tab ==========
#
# 命名 spt 前缀 = SkillPreviewTimeline, 与 LGF core TimelineRegistry / Ability
# timeline 概念严格区分: 这是技能预览 UI 的多 actor 时间轴, 不是 ability animation
# timeline。
#
# 视图全部从 _actors[i] 派生, 不引入新数据 (除 _spt_max_override 一个 int)。
# 重建职责严格分离:
#   _rebuild_spt_ui            只重建节点 (清空 + 每 actor 一行 row)
#   _layout_keyframes_for_row  只调整 KeyframeButton 的 position/size
# resized signal 触发 layout(不重建), 避免 flicker。

func _rebuild_spt_ui() -> void:
	_inspector_rebuild_queued = false
	_clear_spt_cursor_if_invalid()
	if _spt_max_auto_label != null:
		_spt_max_auto_label.text = "auto = %d ms" % _compute_auto_max_ms()
	var track_w := _spt_track_width()
	if _spt_ruler != null:
		_spt_ruler.custom_minimum_size = Vector2(track_w, SPT_RULER_H)
		_spt_ruler.queue_redraw()
		_rebuild_spt_ruler_labels(_spt_ruler)
	if _timeline_tracks_container != null:
		_timeline_tracks_container.custom_minimum_size = Vector2(track_w, 0)
	_rebuild_spt_track_container(_spt_tracks_container, true)
	_rebuild_spt_track_container(_timeline_tracks_container, false)
	_rebuild_spt_warning_list()
	_update_timeline_mode_buttons()


func _rebuild_spt_track_container(container: VBoxContainer, include_actor_label: bool) -> void:
	if container == null:
		return
	for c in container.get_children():
		c.queue_free()
	for i in _actors.size():
		container.add_child(_build_track_row(i, include_actor_label))


## 一行 actor track: [ActorLabel(min_w=110)] [TrackArea(expand)]。
## TrackArea Control 上挂: baseline draw / 每条 keyframe 一个 Button 子节点 /
## 空白点击 gui_input handler。
func _build_track_row(actor_idx: int, include_actor_label: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, SPT_ROW_H)
	row.add_theme_constant_override("separation", 0)
	row.add_theme_stylebox_override("panel", _outlined_sb(SPT_EDITOR_ROW, Color("243142"), 0, 0, 0))

	if include_actor_label:
		row.add_child(_build_timeline_actor_label(actor_idx))

	var track_area := Control.new()
	track_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_area.custom_minimum_size = Vector2(_spt_track_width(), SPT_ROW_H)
	# STOP 而非 PASS: 自己处理空白处单击选轨 / 双击新增; KeyframeButton 子节点默认 STOP
	# 优先吃事件, 命中 button 时不会传到这里。
	track_area.mouse_filter = Control.MOUSE_FILTER_STOP
	track_area.tooltip_text = "Click sets the Add cursor; double-click creates a keyframe at that time"
	track_area.draw.connect(_draw_track_row.bind(actor_idx, track_area))
	# 每条 keyframe 一个 Button 子节点; position 由 _layout_keyframes_for_row 后期填。
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	for k in track.size():
		track_area.add_child(_build_keyframe_button(actor_idx, k))
	# 容器尺寸 settle 后/任意 resize 触发 layout, 不重建节点。
	track_area.resized.connect(func() -> void: _layout_keyframes_for_row(actor_idx, track_area))
	track_area.gui_input.connect(func(event: InputEvent) -> void:
		_on_track_area_clicked(actor_idx, track_area, event)
	)
	# 首次 build: layout 时 size 还没 settle, 推迟一帧。
	call_deferred("_layout_keyframes_for_row", actor_idx, track_area)
	row.add_child(track_area)

	return row


func _build_timeline_actor_label(actor_idx: int) -> Button:
	var actor_label := Button.new()
	actor_label.text = "%d  %s  %s" % [actor_idx, _actor_role_icon(actor_idx), _actor_timeline_label(actor_idx)]
	actor_label.tooltip_text = "Select actor"
	actor_label.custom_minimum_size = Vector2(SPT_ACTOR_LABEL_W, SPT_ROW_H)
	actor_label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	actor_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actor_label.add_theme_stylebox_override("normal", _outlined_sb(SPT_EDITOR_PANEL, _actor_track_color(actor_idx, 0.85), 0, 10, 6))
	actor_label.add_theme_stylebox_override("hover", _outlined_sb(Color("2A3A50"), _actor_track_color(actor_idx, 1.0), 0, 10, 6))
	actor_label.add_theme_stylebox_override("pressed", _outlined_sb(Color("1E3A5F"), Color("93C5FD"), 0, 10, 6))
	actor_label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	actor_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT)
	actor_label.add_theme_color_override("font_hover_color", Color("FFFFFF"))
	actor_label.add_theme_color_override("font_pressed_color", Color("FFFFFF"))
	actor_label.add_theme_font_override("font", _clay_font_bold())
	actor_label.pressed.connect(func() -> void:
		_select_actor(actor_idx)
		if _inspector_tabs != null:
			_inspector_tabs.current_tab = 0
	)
	if _is_character_actor_selected(actor_idx):
		actor_label.add_theme_stylebox_override("normal", _outlined_sb(Color("1E3A5F"), _actor_track_color(actor_idx, 1.0), 0, 10, 6))
	return actor_label


func _actor_role_icon(actor_idx: int) -> String:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return "?"
	var data: Dictionary = _actors[actor_idx]
	if str(data.get("role", "")) == "caster":
		return "Caster"
	return "Ally" if str(data.get("team", "B")) == "A" else "Enemy"


## TrackArea: duration span / cooldown bar / baseline。draw 信号自身不带 sender 上下文。
func _draw_track_row(actor_idx: int, track_area: Control) -> void:
	var w := track_area.size.x
	var h := track_area.size.y
	if w <= 0.0 or h <= 0.0:
		return
	if actor_idx < 0 or actor_idx >= _actors.size():
		return
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	var max_ms := _spt_max_ms()
	track_area.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), SPT_EDITOR_ROW, true)
	if actor_idx == _selected_spt_actor_idx:
		track_area.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), _actor_track_color(actor_idx, 0.08), true)
	var tick_step := _pick_tick_step(max_ms)
	var tick := 0
	while tick <= max_ms:
		var tick_x := _track_x_for_time(tick, max_ms, w)
		track_area.draw_line(
			Vector2(tick_x, 0.0),
			Vector2(tick_x, h),
			SPT_EDITOR_GRID_MAJOR if tick % (tick_step * 2) == 0 else SPT_EDITOR_GRID,
			1.0
		)
		tick += tick_step
	for kf_variant in track:
		var kf: Dictionary = kf_variant as Dictionary
		var time_ms := int(kf.get("time_ms", 0))
		var skill_cfg := HexBattleSkillIndex.get_by_id(str(kf.get("skill", "")))
		if skill_cfg == null:
			continue
		var occupy_ms := SkillPreviewValidation.ability_occupy_ms(skill_cfg)
		var cooldown_ms := SkillPreviewValidation.ability_cooldown_ms(skill_cfg)
		if occupy_ms > 0:
			var span_start := _track_x_for_time(time_ms, max_ms, w)
			var span_end := _track_x_for_time(time_ms + occupy_ms, max_ms, w)
			var span_rect := Rect2(
				Vector2(span_start, (h - SPT_RELEASE_SPAN_H) * 0.5),
				Vector2(maxf(2.0, span_end - span_start), SPT_RELEASE_SPAN_H)
			)
			track_area.draw_rect(span_rect, _actor_track_color(actor_idx, 0.24), true)
			track_area.draw_rect(span_rect, _actor_track_color(actor_idx, 0.7), false, 1.0)
		if cooldown_ms > occupy_ms:
			var cooldown_start := _track_x_for_time(time_ms + occupy_ms, max_ms, w)
			var cooldown_end := _track_x_for_time(time_ms + cooldown_ms, max_ms, w)
			var cooldown_rect := Rect2(
				Vector2(cooldown_start, h - 17.0),
				Vector2(maxf(2.0, cooldown_end - cooldown_start), 14.0)
			)
			track_area.draw_rect(cooldown_rect, Color(0.65, 0.68, 0.75, 0.2), true)
			track_area.draw_rect(cooldown_rect, Color(0.65, 0.68, 0.75, 0.38), false, 1.0)
	var y := h * 0.5
	track_area.draw_line(Vector2(0, y), Vector2(w, y), Color(1.0, 1.0, 1.0, 0.22), 1)
	if _spt_cursor_actor_idx == actor_idx:
		var cursor_x := _track_x_for_time(_spt_cursor_time_ms, max_ms, w)
		track_area.draw_line(Vector2(cursor_x, 3.0), Vector2(cursor_x, h - 3.0), SPT_CURSOR_COLOR, 2.0)
		track_area.draw_circle(Vector2(cursor_x, y), 4.0, SPT_CURSOR_COLOR)
	if _spt_dragging and _spt_drag_actor_idx == actor_idx:
		var ghost_x := _track_x_for_time(_spt_drag_requested_ms, max_ms, w)
		track_area.draw_line(Vector2(ghost_x, 4.0), Vector2(ghost_x, h - 4.0), Color("FFFFFF"), 2.0)
		track_area.draw_circle(Vector2(ghost_x, y), 4.0, Color("FFFFFF"))


## Keyframe 色块按钮: 颜色按 actor team 区分(caster=绿/A=蓝/B=红);
## 按钮正文显示技能名, 详细时间/目标走 tooltip。点击/拖拽会同步右侧 Details。
func _build_keyframe_button(actor_idx: int, kf_idx: int) -> Button:
	var btn := Button.new()
	btn.set_meta("kf_idx", kf_idx)
	btn.size = Vector2(SPT_KF_BTN_W, SPT_KF_BTN_H)
	btn.custom_minimum_size = Vector2(SPT_KF_BTN_W, SPT_KF_BTN_H)
	btn.tooltip_text = _keyframe_tooltip(actor_idx, kf_idx)
	btn.text = _keyframe_button_text(actor_idx, kf_idx)
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.focus_mode = Control.FOCUS_NONE

	var bg: Color
	var border: Color
	var data: Dictionary = _actors[actor_idx]
	if data["role"] == "caster":
		bg = Color("166534"); border = Color("86EFAC")
	elif data["team"] == "A":
		bg = Color("1D4ED8"); border = Color("93C5FD")
	else:
		bg = Color("991B1B"); border = Color("FCA5A5")
	var warning := _keyframe_timing_warning(actor_idx, kf_idx)
	if not warning.is_empty():
		var warning_type := str(warning.get("type", ""))
		border = _spt_warning_color(warning_type)
	if actor_idx == _selected_spt_actor_idx and kf_idx == _selected_spt_kf_idx:
		border = Color("FFFFFF")
	btn.add_theme_stylebox_override("normal", _outlined_sb(bg, border, 4, 0, 0))
	btn.add_theme_stylebox_override("hover", _outlined_sb(bg.lightened(0.1), border, 4, 0, 0))
	btn.add_theme_stylebox_override("pressed", _outlined_sb(bg.darkened(0.1), border, 4, 0, 0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", _clay_font_bold())
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_hover_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("FFFFFF"))
	btn.gui_input.connect(func(event: InputEvent) -> void:
		_on_keyframe_button_gui_input(actor_idx, int(btn.get_meta("kf_idx", -1)), btn, event)
	)
	return btn


func _keyframe_button_text(actor_idx: int, kf_idx: int) -> String:
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return "?"
	var skill_id := str((track[kf_idx] as Dictionary).get("skill", ""))
	var skill_cfg := HexBattleSkillIndex.get_by_id(skill_id)
	if skill_cfg == null:
		return skill_id
	return skill_cfg.display_name


## tooltip 文本: "Strike @ 600ms → enemy_0"。target 模式简写。
func _keyframe_tooltip(actor_idx: int, kf_idx: int) -> String:
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return ""
	var kf: Dictionary = track[kf_idx]
	var skill_name := str(kf.get("skill", "?"))
	var skill_cfg := HexBattleSkillIndex.get_by_id(skill_name)
	var time_ms := int(kf.get("time_ms", 0))
	var target: Dictionary = kf.get("target", {}) as Dictionary
	var mode := str(target.get("mode", "auto"))
	var target_str := _target_mode_label(mode)
	if _skill_uses_self_target(skill_cfg):
		target_str = "Self"
	else:
		match mode:
			"enemy_index", "ally_index":
				target_str = "%s %d" % [_target_mode_label(mode), int(target.get("index", 0))]
			"fixed_pos":
				target_str = "(%d,%d)" % [int(target.get("q", 0)), int(target.get("r", 0))]
		var resolved_idx := _resolve_target_actor_idx_for_ui(actor_idx, target)
		if resolved_idx >= 0:
			target_str += " -> %s" % _role_id_for(resolved_idx)
	var timing_parts: Array[String] = []
	var occupy_ms := SkillPreviewValidation.ability_occupy_ms(skill_cfg)
	var cooldown_ms := SkillPreviewValidation.ability_cooldown_ms(skill_cfg)
	if occupy_ms > 0:
		timing_parts.append("release %d-%dms" % [time_ms, time_ms + occupy_ms])
	if cooldown_ms > 0:
		timing_parts.append("cooldown ready %dms" % (time_ms + cooldown_ms))
	var lines: Array[String] = ["%s @ %dms -> %s" % [skill_name, time_ms, target_str]]
	if not timing_parts.is_empty():
		lines.append(", ".join(timing_parts))
	var warning := _keyframe_timing_warning(actor_idx, kf_idx)
	if not warning.is_empty():
		lines.append("Warning: %s" % str(warning.get("message", "")))
	return "\n".join(lines)


func _keyframe_timing_warning(actor_idx: int, kf_idx: int) -> Dictionary:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return {}
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return {}
	var current: Dictionary = track[kf_idx] as Dictionary
	var current_t := int(current.get("time_ms", 0))
	var current_skill := str(current.get("skill", ""))
	for release_idx in track.size():
		if release_idx == kf_idx:
			continue
		var release_kf: Dictionary = track[release_idx] as Dictionary
		var release_t := int(release_kf.get("time_ms", 0))
		if release_t > current_t:
			continue
		var release_skill := str(release_kf.get("skill", ""))
		var release_cfg := HexBattleSkillIndex.get_by_id(release_skill)
		if release_cfg == null:
			continue
		var occupy_ms := SkillPreviewValidation.ability_occupy_ms(release_cfg)
		if occupy_ms > 0 and current_t < release_t + occupy_ms:
			var warning_type := "release_conflict" if release_skill == current_skill else "overlap"
			return {
				"type": warning_type,
				"message": "%s starts inside %s release window (%d-%dms)" % [
					current_skill, release_skill, release_t, release_t + occupy_ms,
				],
				"source_idx": release_idx,
			}
	for other_idx in track.size():
		if other_idx == kf_idx:
			continue
		var other: Dictionary = track[other_idx] as Dictionary
		var other_t := int(other.get("time_ms", 0))
		if other_t > current_t:
			continue
		var other_skill := str(other.get("skill", ""))
		var other_cfg := HexBattleSkillIndex.get_by_id(other_skill)
		if other_cfg == null:
			continue
		var cooldown_ms := SkillPreviewValidation.ability_cooldown_ms(other_cfg)
		if other_skill == current_skill and cooldown_ms > 0 \
				and current_t > other_t and current_t < other_t + cooldown_ms:
			return {
				"type": "cooldown",
				"message": "%s cooldown ready at %dms" % [current_skill, other_t + cooldown_ms],
				"ready_ms": other_t + cooldown_ms,
				"source_idx": other_idx,
			}
	return {}


static func _spt_warning_color(warning_type: String) -> Color:
	if warning_type == "cooldown" or warning_type == "release_conflict":
		return SPT_WARNING_COOLDOWN
	return SPT_WARNING_OVERLAP


func _actor_track_color(actor_idx: int, alpha: float) -> Color:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return Color(0.45, 0.5, 0.6, alpha)
	var data: Dictionary = _actors[actor_idx]
	if data["role"] == "caster":
		return Color(0.09, 0.64, 0.29, alpha)
	if data["team"] == "A":
		return Color(0.15, 0.39, 0.92, alpha)
	return Color(0.7, 0.23, 0.23, alpha)


func _track_x_for_time(time_ms: int, max_ms: int, width: float) -> float:
	if max_ms <= 0:
		return 0.0
	var ratio := clampf(float(time_ms) / float(max_ms), 0.0, 1.0)
	return ratio * width


## 重排 track_area 内所有 KeyframeButton 的 position/size, 不创建/删除节点。
## resized signal / 首次 build call_deferred / span override 改变后 _rebuild_spt_ui
## 三处都会调到。
func _layout_keyframes_for_row(actor_idx: int, track_area: Control) -> void:
	# Stale callback 防御: 该 row 是 deferred / resized 触发的, 但 actor 可能在
	# 这之间被 _remove_actor_at / _on_preset_load_selected 干掉了, 此时 actor_idx
	# 越界或落到了不同的 actor 上; track_area 也可能正在被 queue_free。
	if track_area == null or not is_instance_valid(track_area):
		return
	if track_area.is_queued_for_deletion():
		return
	if actor_idx < 0 or actor_idx >= _actors.size():
		return
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	var max_ms := _spt_max_ms()
	var w := track_area.size.x
	var h := track_area.size.y
	for k in track.size():
		if k >= track_area.get_child_count():
			break
		var btn := track_area.get_child(k) as Button
		if btn == null:
			continue
		var t := int((track[k] as Dictionary).get("time_ms", 0))
		var ratio := clampf(float(t) / float(max_ms), 0.0, 1.0)
		var x := int(ratio * (w - SPT_KF_BTN_W))
		var lane := _keyframe_lane_for_time(track, k)
		var lane_count := _keyframe_lane_count_at_time(track, t)
		var group_h := float(lane_count) * float(SPT_KF_BTN_H) + float(maxi(0, lane_count - 1)) * 2.0
		var y := int((h - group_h) * 0.5 + float(lane) * (float(SPT_KF_BTN_H) + 2.0))
		btn.position = Vector2(x, y)
		btn.size = Vector2(SPT_KF_BTN_W, SPT_KF_BTN_H)


func _keyframe_lane_for_time(track: Array, kf_idx: int) -> int:
	if kf_idx < 0 or kf_idx >= track.size():
		return 0
	var time_ms := int((track[kf_idx] as Dictionary).get("time_ms", 0))
	var lane := 0
	for i in range(0, kf_idx):
		if int((track[i] as Dictionary).get("time_ms", 0)) == time_ms:
			lane += 1
	return lane


func _keyframe_lane_count_at_time(track: Array, time_ms: int) -> int:
	var count := 0
	for kf_variant in track:
		if int((kf_variant as Dictionary).get("time_ms", 0)) == time_ms:
			count += 1
	return maxi(1, count)


func _on_keyframe_button_gui_input(
	actor_idx: int, kf_idx: int, btn: Button, event: InputEvent
) -> void:
	if _is_playing:
		return
	if actor_idx < 0 or actor_idx >= _actors.size():
		return
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_select_spt_keyframe(actor_idx, kf_idx)
			_spt_dragging = true
			_spt_drag_actor_idx = actor_idx
			_spt_drag_kf_idx = kf_idx
			_spt_drag_requested_ms = int((track[kf_idx] as Dictionary).get("time_ms", 0))
			_spt_drag_track_area = btn.get_parent() as Control
			if _spt_drag_track_area != null:
				_spt_drag_track_area.queue_redraw()
		else:
			if _is_dragging_keyframe(actor_idx, kf_idx):
				var final_ms := _on_keyframe_time_changed(actor_idx, kf_idx, _spt_drag_requested_ms)
				_select_spt_keyframe(actor_idx, kf_idx)
				if final_ms != _spt_drag_requested_ms:
					_set_status("Moved to %dms: same skill release window is occupied" % final_ms)
			_clear_spt_drag_state()
			_rebuild_spt_ui()
	elif event is InputEventMouseMotion:
		if not _is_dragging_keyframe(actor_idx, kf_idx):
			return
		var track_area := btn.get_parent() as Control
		if track_area == null or track_area.size.x <= 0.0:
			return
		var local_x := track_area.get_local_mouse_position().x
		_spt_drag_requested_ms = _time_for_track_x(local_x, track_area.size.x)
		track_area.queue_redraw()
		_rebuild_actors_ui()


func _clear_spt_drag_state() -> void:
	var redraw_area := _spt_drag_track_area
	_spt_dragging = false
	_spt_drag_actor_idx = -1
	_spt_drag_kf_idx = -1
	_spt_drag_requested_ms = 0
	_spt_drag_track_area = null
	if redraw_area != null and is_instance_valid(redraw_area):
		redraw_area.queue_redraw()


func _is_dragging_keyframe(actor_idx: int, kf_idx: int) -> bool:
	return _spt_dragging and _spt_drag_actor_idx == actor_idx and _spt_drag_kf_idx == kf_idx


func _time_for_track_x(x: float, width: float) -> int:
	if width <= 0.0:
		return 0
	var ratio := clampf(x / width, 0.0, 1.0)
	return int(round(ratio * float(_spt_max_ms()) / float(KF_TIME_STEP_MS))) * KF_TIME_STEP_MS


func _set_spt_cursor(actor_idx: int, time_ms: int, redraw: bool = true) -> void:
	if actor_idx < 0 or actor_idx >= _actors.size():
		_spt_cursor_actor_idx = -1
		_spt_cursor_time_ms = 0
	else:
		_spt_cursor_actor_idx = actor_idx
		_spt_cursor_time_ms = clampi(time_ms, 0, _spt_max_ms())
	if redraw:
		_queue_spt_track_redraw()
	_update_timeline_mode_buttons()


func _clear_spt_cursor_if_invalid() -> void:
	if _spt_cursor_actor_idx < 0:
		_spt_cursor_actor_idx = -1
		_spt_cursor_time_ms = 0
		return
	if _spt_cursor_actor_idx >= _actors.size():
		_spt_cursor_actor_idx = -1
		_spt_cursor_time_ms = 0
		return
	_spt_cursor_time_ms = clampi(_spt_cursor_time_ms, 0, _spt_max_ms())


func _queue_spt_track_redraw() -> void:
	var containers: Array[VBoxContainer] = []
	if _spt_tracks_container != null:
		containers.append(_spt_tracks_container)
	if _timeline_tracks_container != null:
		containers.append(_timeline_tracks_container)
	for container in containers:
		for row_variant in container.get_children():
			var row := row_variant as Control
			if row == null:
				continue
			row.queue_redraw()
			for child_variant in row.get_children():
				var child := child_variant as Control
				if child != null:
					child.queue_redraw()


func _set_spt_selection(actor_idx: int, kf_idx: int) -> void:
	_selected_spt_actor_idx = actor_idx
	_selected_spt_kf_idx = kf_idx
	if actor_idx >= 0 and kf_idx >= 0:
		_selected_kind = SELECT_KEYFRAME
		_selected_actor_idx = -1
		_selected_environment_idx = -1
		_details_popup_user_closed = false
		if actor_idx < _actors.size():
			var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
			if kf_idx < track.size():
				_set_spt_cursor(actor_idx, int((track[kf_idx] as Dictionary).get("time_ms", 0)), false)
	elif actor_idx >= 0:
		_select_actor_at(actor_idx, false)


func _select_spt_keyframe(actor_idx: int, kf_idx: int) -> void:
	_set_spt_selection(actor_idx, kf_idx)
	_rebuild_actors_ui()
	_rebuild_spt_warning_list()


func _clear_spt_selection_if_invalid() -> void:
	if _selected_spt_actor_idx < 0 or _selected_spt_actor_idx >= _actors.size():
		_selected_spt_actor_idx = -1
		_selected_spt_kf_idx = -1
		return
	if _selected_spt_kf_idx < 0:
		return
	var track: Array = (_actors[_selected_spt_actor_idx] as Dictionary).get("track", []) as Array
	if _selected_spt_kf_idx >= track.size():
		_selected_spt_kf_idx = track.size() - 1


func _rebuild_spt_warning_list() -> void:
	if _timeline_warning_list == null:
		return
	for c in _timeline_warning_list.get_children():
		c.queue_free()
	var warnings := _collect_spt_warnings()
	if warnings.is_empty():
		var ok := Label.new()
		ok.text = "No timeline warnings"
		ok.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
		_timeline_warning_list.add_child(ok)
		return
	for warning in warnings:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var focus_btn := Button.new()
		var actor_idx := int(warning.get("actor_idx", -1))
		var kf_idx := int(warning.get("kf_idx", -1))
		focus_btn.text = str(warning.get("message", ""))
		focus_btn.tooltip_text = "Focus keyframe"
		focus_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		focus_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var warning_type := str(warning.get("type", ""))
		var border := _spt_warning_color(warning_type)
		focus_btn.add_theme_stylebox_override("normal", _outlined_sb(Color("FFFFFF"), border, 5, 8, 5))
		focus_btn.add_theme_stylebox_override("hover", _outlined_sb(Color("FFF7ED"), border, 5, 8, 5))
		focus_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		focus_btn.pressed.connect(func() -> void:
			_apply_timeline_workspace_layout()
			_select_spt_keyframe(actor_idx, kf_idx)
			_rebuild_spt_ui()
		)
		row.add_child(focus_btn)
		if warning_type == "cooldown":
			var fix_btn := Button.new()
			fix_btn.text = "Ready"
			fix_btn.tooltip_text = "Move to ready time"
			fix_btn.pressed.connect(func() -> void: _move_keyframe_to_ready_time(actor_idx, kf_idx))
			row.add_child(fix_btn)
		_timeline_warning_list.add_child(row)


func _collect_spt_warnings() -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	for actor_idx in _actors.size():
		var actor_data: Dictionary = _actors[actor_idx]
		var track: Array = actor_data.get("track", []) as Array
		for kf_idx in track.size():
			var kf: Dictionary = track[kf_idx] as Dictionary
			var skill_id := str(kf.get("skill", ""))
			var time_ms := int(kf.get("time_ms", 0))
			var skill_cfg := HexBattleSkillIndex.get_by_id(skill_id)
			if skill_cfg == null:
				warnings.append({
					"type": "error",
					"actor_idx": actor_idx,
					"kf_idx": kf_idx,
					"message": "%s @ %dms unknown skill: %s" % [_role_id_for(actor_idx), time_ms, skill_id],
				})
				continue
			var target: Dictionary = kf.get("target", {"mode": "auto"}) as Dictionary
			var target_idx := _resolve_target_actor_idx_for_ui(actor_idx, target)
			if _skill_requires_external_target(skill_cfg) and target_idx < 0:
				warnings.append({
					"type": "error",
					"actor_idx": actor_idx,
					"kf_idx": kf_idx,
					"message": "%s @ %dms invalid target" % [_role_id_for(actor_idx), time_ms],
				})
			var timing_warning := _keyframe_timing_warning(actor_idx, kf_idx)
			if not timing_warning.is_empty():
				timing_warning["actor_idx"] = actor_idx
				timing_warning["kf_idx"] = kf_idx
				timing_warning["message"] = "%s @ %dms: %s" % [
					_role_id_for(actor_idx), time_ms, str(timing_warning.get("message", "")),
				]
				warnings.append(timing_warning)
	return warnings


func _move_keyframe_to_ready_time(actor_idx: int, kf_idx: int) -> void:
	var warning := _keyframe_timing_warning(actor_idx, kf_idx)
	if str(warning.get("type", "")) != "cooldown":
		return
	var ready_ms := int(warning.get("ready_ms", 0))
	var final_ms := _on_keyframe_time_changed(actor_idx, kf_idx, ready_ms)
	_select_spt_keyframe(actor_idx, kf_idx)
	_set_status("Moved keyframe to ready time: %dms" % final_ms)
	_rebuild_spt_ui()


func _on_timeline_add_keyframe_pressed() -> void:
	var actor_idx := _timeline_add_target_actor_idx()
	if actor_idx < 0 or actor_idx >= _actors.size():
		_set_status("Select an actor track before adding")
		return
	var requested_ms := _timeline_add_target_time_ms(actor_idx)
	var new_idx := _add_keyframe_at(actor_idx, requested_ms)
	if new_idx >= 0:
		_select_spt_keyframe(actor_idx, new_idx)
		var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
		var final_ms := requested_ms
		if new_idx < track.size():
			final_ms = int((track[new_idx] as Dictionary).get("time_ms", requested_ms))
		_set_spt_cursor(actor_idx, final_ms, false)
		_set_status("Added keyframe to %s at %dms" % [_role_id_for(actor_idx), final_ms])


func _next_keyframe_time_for(actor_idx: int) -> int:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return 0
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	var t := 0
	for kf_variant in track:
		t = maxi(t, int((kf_variant as Dictionary).get("time_ms", 0)) + KF_TIME_STEP_MS)
	return mini(t, _spt_max_ms())


## label + editor 横排, 用于 Details 的 keyframe 表单行。
func _build_kf_form_row(label_text: String, editor: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(60, 0)
	row.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)
	return row


## TrackArea 空白处单击只移动 Add cursor; 双击才按点击位置新增 keyframe。
func _on_track_area_clicked(actor_idx: int, track_area: Control, event: InputEvent) -> void:
	if _is_playing:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	if track_area == null or not is_instance_valid(track_area) or track_area.size.x <= 0.0:
		return
	if actor_idx < 0 or actor_idx >= _actors.size():
		return  # row 在 free 队列中, actor 已变 — 忽略点击
	var raw_ms := _time_for_track_x(mb.position.x, track_area.size.x)
	_set_spt_cursor(actor_idx, raw_ms)
	if not mb.double_click:
		_select_actor_at(actor_idx)
		_set_status(
			"Cursor set on %s at %dms" % [_role_id_for(actor_idx), raw_ms]
		)
		get_viewport().set_input_as_handled()
		return
	var new_idx := _add_keyframe_at(actor_idx, raw_ms)
	if new_idx >= 0:
		_select_spt_keyframe(actor_idx, new_idx)
		_set_status("Added keyframe at %dms" % raw_ms)
	get_viewport().set_input_as_handled()


## auto-fit: 取所有 keyframe 最大 time_ms + buffer, 并保证不低于 1000ms 防空 track 退化。
func _compute_auto_max_ms() -> int:
	var m := 0
	for actor_data in _actors:
		var track: Array = (actor_data as Dictionary).get("track", []) as Array
		for kf in track:
			m = maxi(m, int((kf as Dictionary).get("time_ms", 0)))
	return maxi(m + SPT_AUTO_BUFFER_MS, SPT_MIN_AUTO_MS)


## 当前生效的时间轴 max。override>0 强制覆盖。纯函数, 不写 status —— 警告由
## _warn_if_override_below_keyframes 在 mutation 点单次触发。
func _spt_max_ms() -> int:
	if _spt_max_override > 0:
		return _spt_max_override
	return _compute_auto_max_ms()


func _spt_track_width() -> float:
	return maxf(SPT_MIN_TRACK_W, float(_spt_max_ms()) * SPT_MS_TO_PX)


## Override 比实际最大 keyframe 还小时, 在改 override 的 SpinBox 上即时提醒一次。
func _warn_if_override_below_keyframes() -> void:
	if _spt_max_override <= 0:
		return
	var max_kf_ms := _compute_auto_max_ms() - SPT_AUTO_BUFFER_MS
	if _spt_max_override < max_kf_ms:
		_set_status("Override below max keyframe (%d ms)" % max_kf_ms)


## 根据 max_ms 选合适的刻度步长 (250/500/1000/2000), 比固定 5 段更直观。
func _pick_tick_step(max_ms: int) -> int:
	if max_ms <= 1500:
		return 250
	if max_ms <= 3000:
		return 500
	if max_ms <= 8000:
		return 1000
	return 2000


func _draw_spt_ruler_on(ruler: Control) -> void:
	if ruler == null:
		return
	var max_ms := _spt_max_ms()
	var step := _pick_tick_step(max_ms)
	var w := ruler.size.x
	var h := ruler.size.y
	if w <= 0.0:
		return
	ruler.draw_rect(Rect2(Vector2.ZERO, ruler.size), SPT_EDITOR_BG, true)
	var t := 0
	while t <= max_ms:
		var x := int(float(t) / float(max_ms) * w)
		var is_major := t % (step * 2) == 0
		ruler.draw_line(
			Vector2(x, SPT_RULER_LABEL_H + 4.0),
			Vector2(x, h - 4.0),
			SPT_EDITOR_GRID_MAJOR if is_major else SPT_EDITOR_GRID,
			1.0
		)
		t += step


func _rebuild_spt_ruler_labels(ruler: Control) -> void:
	if ruler == null or not is_instance_valid(ruler):
		return
	if ruler.is_queued_for_deletion():
		return
	for child_variant in ruler.get_children():
		var child := child_variant as Node
		if child != null:
			ruler.remove_child(child)
			child.queue_free()
	var max_ms := _spt_max_ms()
	var step := _pick_tick_step(max_ms) * 2
	var w := ruler.size.x
	if w <= 0.0 or max_ms <= 0:
		return
	var t := 0
	while t <= max_ms:
		var tick_x := float(t) / float(max_ms) * w
		var label := Label.new()
		label.text = _format_spt_ruler_time(t)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(SPT_RULER_LABEL_W, SPT_RULER_LABEL_H)
		label.size = Vector2(SPT_RULER_LABEL_W, SPT_RULER_LABEL_H)
		label.position = Vector2(
			clampf(tick_x - SPT_RULER_LABEL_W * 0.5, 0.0, maxf(0.0, w - SPT_RULER_LABEL_W)),
			1.0
		)
		label.add_theme_font_override("font", _clay_font_bold())
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
		ruler.add_child(label)
		t += step


func _format_spt_ruler_time(ms: int) -> String:
	if ms >= 1000 and ms % 1000 == 0:
		return "%ds" % int(ms / 1000)
	return "%dms" % ms


func _actor_role_label(data: Dictionary) -> String:
	if data["role"] == "caster":
		return "Caster"
	return "Ally" if data["team"] == "A" else "Enemy"


func _actor_timeline_label(idx: int) -> String:
	var data: Dictionary = _actors[idx]
	return "%s · %s" % [_role_id_for(idx), str(data.get("class", "?"))]


func _actor_detail_title(idx: int) -> String:
	return "Edit %s" % _actor_timeline_label(idx)


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
	title.text = _actor_detail_title(idx)
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
		_queue_inspector_rebuild()
	)
	box.add_child(_build_actor_detail_field("Class", class_opt))

	var pos: Array = data["pos"]
	box.add_child(_build_actor_detail_field("Q", _make_actor_spin(idx, "q", pos[0], -20, 20, false, 0)))
	box.add_child(_build_actor_detail_field("R", _make_actor_spin(idx, "r", pos[1], -20, 20, false, 0)))
	box.add_child(_build_actor_detail_field("HP", _make_actor_spin(idx, "hp", data["hp"], 0, 9999, true, 0)))

	# Passives 段: 每 actor 自己的 passive 选择 (来源 HexBattleSkillIndex.passives())。
	# 与 Skill Track 解耦 —— passive 在战斗 start() 一次性 grant, 不进 timeline。
	box.add_child(_build_actor_passive_section(idx))

	box.add_child(_build_actor_track_section(idx))

	if data["role"] != "caster":
		var rm := Button.new()
		rm.text = "Remove Actor"
		rm.tooltip_text = "Remove actor"
		rm.pressed.connect(func() -> void: _remove_actor_at(idx))
		box.add_child(rm)
	return panel


func _build_actor_passive_section(actor_idx: int) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "Passives"
	title.add_theme_font_override("font", _clay_font_bold())
	title.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	section.add_child(title)

	var current_ids: Array = (_actors[actor_idx] as Dictionary).get("passives", []) as Array
	for cfg in HexBattleSkillIndex.passives():
		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [cfg.display_name, cfg.config_id]
		cb.button_pressed = current_ids.has(cfg.config_id)
		_apply_passive_style(cb, cb.button_pressed)
		var passive_id: String = cfg.config_id  # capture for closure
		cb.toggled.connect(func(pressed: bool) -> void:
			_apply_passive_style(cb, pressed)
			_on_actor_passive_toggled(actor_idx, passive_id, pressed)
		)
		section.add_child(cb)
	return section


func _build_actor_track_section(actor_idx: int) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "Skill Track"
	title.add_theme_font_override("font", _clay_font_bold())
	title.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	section.add_child(title)

	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if track.is_empty():
		var empty := Label.new()
		empty.text = "No actions"
		empty.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
		section.add_child(empty)
	for kf_idx in track.size():
		section.add_child(_build_keyframe_summary_row(actor_idx, kf_idx))

	var add_btn := Button.new()
	add_btn.text = "+ Add Action"
	add_btn.tooltip_text = "Create an action, then edit it in Details"
	add_btn.pressed.connect(func() -> void:
		_add_keyframe(actor_idx)
		_apply_timeline_workspace_layout()
	)
	section.add_child(add_btn)
	return section


func _build_keyframe_summary_row(actor_idx: int, kf_idx: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	var kf: Dictionary = track[kf_idx] as Dictionary
	var skill_id := str(kf.get("skill", ""))
	var skill_cfg := HexBattleSkillIndex.get_by_id(skill_id)
	var skill_name := skill_cfg.display_name if skill_cfg != null else skill_id
	var label := Button.new()
	label.text = "%dms  %s" % [int(kf.get("time_ms", 0)), skill_name]
	label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = "Select keyframe"
	label.pressed.connect(func() -> void:
		_apply_timeline_workspace_layout()
		_select_spt_keyframe(actor_idx, kf_idx)
	)
	row.add_child(label)
	var rm := Button.new()
	rm.text = "Delete"
	rm.tooltip_text = "Delete this keyframe"
	rm.pressed.connect(func() -> void: _remove_keyframe(actor_idx, kf_idx))
	row.add_child(rm)
	return row


## time SpinBox: Details keyframe editor 共用。
## value_changed 调 `_on_keyframe_time_changed` 拿 final_ms (conflict bump 后),
## 同步回 SpinBox 自身, 避免显示旧值。
func _build_kf_time_spin(actor_idx: int, kf_idx: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0.0
	s.max_value = float(KF_TIME_MAX_MS)
	s.step = float(KF_TIME_STEP_MS)
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	var kf: Dictionary = track[kf_idx]
	s.value = float(int(kf.get("time_ms", 0)))
	s.suffix = "ms"
	s.tooltip_text = "Trigger time (ms). Step=%d. logic_time>=N tick 触发。" % KF_TIME_STEP_MS
	s.value_changed.connect(func(v: float) -> void:
		var requested := int(v)
		var final_ms := _on_keyframe_time_changed(actor_idx, kf_idx, requested)
		if final_ms != requested and is_instance_valid(s):
			s.set_value_no_signal(float(final_ms))
	)
	return s


## skill OptionButton: Details keyframe editor 共用。
## 选项 = HexBattleSkillIndex.actives(), metadata 存 config_id。
func _build_kf_skill_opt(actor_idx: int, kf_idx: int) -> OptionButton:
	var opt := OptionButton.new()
	opt.fit_to_longest_item = false
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	var current_skill_id: String = str((track[kf_idx] as Dictionary).get("skill", ""))
	var actives := HexBattleSkillIndex.actives()
	var selected := 0
	for i in actives.size():
		opt.add_item(actives[i].display_name)
		opt.set_item_metadata(i, actives[i].config_id)
		if actives[i].config_id == current_skill_id:
			selected = i
	if not actives.is_empty():
		opt.selected = selected
	opt.item_selected.connect(func(i: int) -> void:
		_on_keyframe_skill_changed(actor_idx, kf_idx, str(opt.get_item_metadata(i)))
	)
	return opt


func _build_keyframe_target_editor(actor_idx: int, kf_idx: int) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)

	var track: Array = (_actors[actor_idx] as Dictionary)["track"] as Array
	var kf: Dictionary = track[kf_idx]
	var keyframe_skill_cfg := HexBattleSkillIndex.get_by_id(str(kf.get("skill", "")))
	var target: Dictionary = kf.get("target", {"mode": "auto"}) as Dictionary

	var mode_opt := OptionButton.new()
	mode_opt.fit_to_longest_item = false
	for m in TARGET_MODE_NAMES:
		mode_opt.add_item(_target_mode_label(m))
		mode_opt.set_item_metadata(mode_opt.item_count - 1, m)
	var current_mode: String = target.get("mode", "auto") as String
	mode_opt.selected = max(0, TARGET_MODE_NAMES.find(current_mode))
	vb.add_child(mode_opt)

	# index 子行 (mode = enemy_index/ally_index 时显示)
	var index_row := HBoxContainer.new()
	index_row.add_theme_constant_override("separation", 4)
	var index_label := Label.new()
	index_label.text = "idx"
	index_label.custom_minimum_size = Vector2(28, 0)
	index_row.add_child(index_label)
	var index_spin := SpinBox.new()
	index_spin.min_value = 0.0
	index_spin.max_value = 20.0
	index_spin.step = 1.0
	index_spin.value = float(int(target.get("index", 0)))
	index_spin.custom_minimum_size = Vector2(60, 0)
	index_spin.value_changed.connect(func(v: float) -> void:
		_on_keyframe_target_field_changed(actor_idx, kf_idx, "index", int(v))
	)
	index_row.add_child(index_spin)
	vb.add_child(index_row)

	# pos 子行 (mode = fixed_pos 时显示)
	var pos_row := HBoxContainer.new()
	pos_row.add_theme_constant_override("separation", 4)
	var lq := Label.new()
	lq.text = "Q"
	lq.custom_minimum_size = Vector2(16, 0)
	pos_row.add_child(lq)
	var q_spin := SpinBox.new()
	q_spin.min_value = -20.0
	q_spin.max_value = 20.0
	q_spin.step = 1.0
	q_spin.value = float(int(target.get("q", 0)))
	q_spin.custom_minimum_size = Vector2(48, 0)
	q_spin.value_changed.connect(func(v: float) -> void:
		_on_keyframe_target_field_changed(actor_idx, kf_idx, "q", int(v))
	)
	pos_row.add_child(q_spin)
	var lr := Label.new()
	lr.text = "R"
	lr.custom_minimum_size = Vector2(16, 0)
	pos_row.add_child(lr)
	var r_spin := SpinBox.new()
	r_spin.min_value = -20.0
	r_spin.max_value = 20.0
	r_spin.step = 1.0
	r_spin.value = float(int(target.get("r", 0)))
	r_spin.custom_minimum_size = Vector2(48, 0)
	r_spin.value_changed.connect(func(v: float) -> void:
		_on_keyframe_target_field_changed(actor_idx, kf_idx, "r", int(v))
	)
	pos_row.add_child(r_spin)
	vb.add_child(pos_row)

	var target_hint := Label.new()
	target_hint.add_theme_color_override("font_color", CLAY_TEXT_SOFT)
	target_hint.add_theme_font_size_override("font_size", 11)
	target_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(target_hint)

	var apply_visibility := func() -> void:
		var mode := str(mode_opt.get_item_metadata(mode_opt.selected))
		var self_target := _skill_uses_self_target(keyframe_skill_cfg)
		var index_count := _target_candidate_count(actor_idx, mode)
		mode_opt.set_meta("force_disabled", self_target)
		mode_opt.disabled = self_target
		index_row.visible = mode == "enemy_index" or mode == "ally_index"
		pos_row.visible = mode == "fixed_pos"
		index_spin.max_value = float(maxi(index_count - 1, 0))
		index_spin.set_meta("force_disabled", self_target or index_count <= 0)
		index_spin.editable = (not self_target) and index_count > 0
		index_spin.get_line_edit().editable = (not self_target) and index_count > 0
		index_spin.tooltip_text = "" if index_count > 0 else "No target candidates for this mode"
		q_spin.set_meta("force_disabled", self_target)
		q_spin.editable = not self_target
		q_spin.get_line_edit().editable = not self_target
		r_spin.set_meta("force_disabled", self_target)
		r_spin.editable = not self_target
		r_spin.get_line_edit().editable = not self_target
		if actor_idx >= 0 and actor_idx < _actors.size():
			var current_track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
			if kf_idx >= 0 and kf_idx < current_track.size():
				var current_target: Dictionary = (current_track[kf_idx] as Dictionary).get("target", {}) as Dictionary
				var current_skill_id := str((current_track[kf_idx] as Dictionary).get("skill", ""))
				var current_skill_cfg := HexBattleSkillIndex.get_by_id(current_skill_id)
				target_hint.text = _target_hint_for_ui(actor_idx, current_target, current_skill_cfg)
	apply_visibility.call()
	mode_opt.item_selected.connect(func(i: int) -> void:
		var selected_mode := str(mode_opt.get_item_metadata(i))
		_on_keyframe_target_field_changed(actor_idx, kf_idx, "mode", selected_mode)
		var candidate_count := _target_candidate_count(actor_idx, selected_mode)
		var max_index := maxi(candidate_count - 1, 0)
		if actor_idx < 0 or actor_idx >= _actors.size():
			return
		var track_now: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
		if kf_idx >= 0 and kf_idx < track_now.size():
			var target_now: Dictionary = (track_now[kf_idx] as Dictionary).get("target", {}) as Dictionary
			if int(target_now.get("index", 0)) > max_index:
				_on_keyframe_target_field_changed(actor_idx, kf_idx, "index", max_index)
		apply_visibility.call()
	)

	return vb


static func _target_mode_label(mode: String) -> String:
	match mode:
		"enemy_index":
			return "Enemy #"
		"ally_index":
			return "Ally #"
		"fixed_pos":
			return "Nearest Hex"
		_:
			return "Auto Enemy"


func _target_candidate_count(actor_idx: int, mode: String) -> int:
	return _target_actor_indices_for(actor_idx, mode).size()


func _target_actor_indices_for(actor_idx: int, mode: String) -> Array[int]:
	var result: Array[int] = []
	if actor_idx < 0 or actor_idx >= _actors.size():
		return result
	var caster_data: Dictionary = _actors[actor_idx]
	var caster_team := str(caster_data.get("team", "A"))
	var want_same_team := mode == "ally_index"
	for i in _actors.size():
		if i == actor_idx:
			continue
		var data: Dictionary = _actors[i]
		var same_team := str(data.get("team", "B")) == caster_team
		if want_same_team and same_team:
			result.append(i)
		elif not want_same_team and not same_team:
			result.append(i)
	return result


func _target_hint_for_ui(actor_idx: int, target: Dictionary, skill_cfg: AbilityConfig = null) -> String:
	if _skill_uses_self_target(skill_cfg):
		return "Target: self"
	var resolved_idx := _resolve_target_actor_idx_for_ui(actor_idx, target)
	if resolved_idx >= 0:
		var target_text := "Target: %s" % _role_id_for(resolved_idx)
		if not _target_matches_skill_tags(skill_cfg, actor_idx, resolved_idx):
			target_text += " (tag mismatch)"
		return target_text
	var mode := str(target.get("mode", "auto"))
	match mode:
		"enemy_index":
			return "No valid enemy target for this actor"
		"ally_index":
			return "No valid ally target for this actor"
		"fixed_pos":
			return "No actor near this hex"
		_:
			return "No enemy target for auto mode"


static func _skill_uses_self_target(skill_cfg: AbilityConfig) -> bool:
	return skill_cfg != null and skill_cfg.ability_tags.has("self")


static func _skill_requires_external_target(skill_cfg: AbilityConfig) -> bool:
	if skill_cfg == null or _skill_uses_self_target(skill_cfg):
		return false
	return skill_cfg.ability_tags.has("enemy") or skill_cfg.ability_tags.has("ally")


func _target_matches_skill_tags(skill_cfg: AbilityConfig, actor_idx: int, target_idx: int) -> bool:
	if skill_cfg == null or not _skill_requires_external_target(skill_cfg):
		return true
	if actor_idx < 0 or actor_idx >= _actors.size() or target_idx < 0 or target_idx >= _actors.size():
		return false
	var actor_team := str((_actors[actor_idx] as Dictionary).get("team", "A"))
	var target_team := str((_actors[target_idx] as Dictionary).get("team", "B"))
	if skill_cfg.ability_tags.has("enemy"):
		return actor_team != target_team
	if skill_cfg.ability_tags.has("ally"):
		return actor_team == target_team and actor_idx != target_idx
	return true


func _resolve_target_actor_idx_for_ui(actor_idx: int, target: Dictionary) -> int:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return -1
	var mode := str(target.get("mode", "auto"))
	match mode:
		"enemy_index", "ally_index":
			var candidates := _target_actor_indices_for(actor_idx, mode)
			var target_index := int(target.get("index", 0))
			if target_index >= 0 and target_index < candidates.size():
				return candidates[target_index]
			return -1
		"fixed_pos":
			var candidates := _all_actor_indices()
			var coord := HexCoord.new(int(target.get("q", 0)), int(target.get("r", 0)))
			return _nearest_actor_idx_to(coord, candidates)
		_:
			var origin := _actor_coord(actor_idx)
			return _nearest_actor_idx_to(origin, _target_actor_indices_for(actor_idx, "enemy_index"))


func _all_actor_indices() -> Array[int]:
	var result: Array[int] = []
	for i in _actors.size():
		result.append(i)
	return result


func _nearest_actor_idx_to(origin: HexCoord, candidates: Array[int]) -> int:
	if origin == null or not origin.is_valid():
		return -1
	var best_idx := -1
	var best_dist := 0x7FFFFFFF
	for idx in candidates:
		if idx < 0 or idx >= _actors.size():
			continue
		var d := _actor_coord(idx).distance_to(origin)
		if d < best_dist:
			best_dist = d
			best_idx = idx
	return best_idx


func _actor_coord(idx: int) -> HexCoord:
	var data: Dictionary = _actors[idx]
	var pos: Array = data.get("pos", [0, 0])
	return HexCoord.new(int(pos[0]), int(pos[1]))


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


## Passive 勾选/取消: 仅 mutate 数据模型, world 编辑期不感知 passive
## (passive 在战斗 start() grant)。
func _on_actor_passive_toggled(actor_idx: int, passive_id: String, pressed: bool) -> void:
	var data: Dictionary = _actors[actor_idx]
	var arr: Array = data.get("passives", []) as Array
	if pressed:
		if not arr.has(passive_id):
			arr.append(passive_id)
	else:
		arr.erase(passive_id)
	data["passives"] = arr


# ========== Keyframe mutation ==========

## 在 actor 的 track 末尾追加一条 keyframe, requested_ms 起算找下一个空闲 100 边界。
## 返回新增 keyframe 的索引 (caller 可立即选中它); 失败返回 -1。
## Details panel "+ Add Action" 走这里; Timeline tab 只负责看、选、拖。
func _add_keyframe_at(actor_idx: int, requested_ms: int) -> int:
	var skill_id := _default_active_skill_id()
	if skill_id == "":
		_set_status("No active skill registered")
		return -1
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	# 同 skill release overlap 自动 bump; cooldown / different skill overlap 保留并 warning。
	var time_ms := _next_free_time_ms_in_track(track, skill_id, requested_ms)
	if time_ms != requested_ms:
		_set_status("Moved to %dms: same skill release window is occupied" % time_ms)
	track.append({
		"time_ms": time_ms,
		"skill": skill_id,
		"target": {"mode": "auto", "index": 0, "q": 0, "r": 0},
	})
	(_actors[actor_idx] as Dictionary)["track"] = track
	_queue_inspector_rebuild()
	return track.size() - 1


func _add_keyframe(actor_idx: int) -> void:
	var new_idx := _add_keyframe_at(actor_idx, 0)
	if new_idx >= 0:
		_set_spt_selection(actor_idx, new_idx)


func _remove_keyframe(actor_idx: int, kf_idx: int) -> void:
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return
	var removed_selection := _selected_kind == SELECT_KEYFRAME \
			and _selected_spt_actor_idx == actor_idx \
			and _selected_spt_kf_idx == kf_idx
	track.remove_at(kf_idx)
	(_actors[actor_idx] as Dictionary)["track"] = track
	if _selected_spt_actor_idx == actor_idx:
		if _selected_spt_kf_idx == kf_idx:
			_selected_spt_kf_idx = -1
		elif _selected_spt_kf_idx > kf_idx:
			_selected_spt_kf_idx -= 1
	if removed_selection:
		_select_actor_at(actor_idx, false)
	_queue_inspector_rebuild()


## time_ms 改动: 同 skill release overlap 时 push 到下一个空闲边界并提示。
## 返回最终生效的 time_ms, 供 SpinBox 同步显示。
func _on_keyframe_time_changed(actor_idx: int, kf_idx: int, requested_ms: int) -> int:
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return requested_ms
	var skill_id := str((track[kf_idx] as Dictionary).get("skill", ""))
	# next_free 只处理同 skill release overlap; cooldown / other skill overlap 保留 warning。
	var final_ms := _next_free_time_ms_in_track(track, skill_id, requested_ms, kf_idx)
	if final_ms != requested_ms:
		_set_status("Moved to %dms: same skill release window is occupied" % final_ms)
	(track[kf_idx] as Dictionary)["time_ms"] = final_ms
	_queue_inspector_rebuild()
	return final_ms


func _on_keyframe_skill_changed(actor_idx: int, kf_idx: int, skill_id: String) -> void:
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return
	(track[kf_idx] as Dictionary)["skill"] = skill_id
	# 切到 occupy 更长的 skill 时, 当前 time_ms 可能与同 actor 其它同 skill keyframe
	# 撞 occupy 窗口, 重算并 bump。time_ms 不变就是合法的, next_free 直接返回原值。
	var current_ms := int((track[kf_idx] as Dictionary).get("time_ms", 0))
	var bumped_ms := _next_free_time_ms_in_track(track, skill_id, current_ms, kf_idx)
	if bumped_ms != current_ms:
		(track[kf_idx] as Dictionary)["time_ms"] = bumped_ms
		_set_status("Skill change — time bumped to %dms (occupy)" % bumped_ms)
	_queue_inspector_rebuild()


func _on_keyframe_target_field_changed(actor_idx: int, kf_idx: int, field: String, value: Variant) -> void:
	if actor_idx < 0 or actor_idx >= _actors.size():
		return
	var track: Array = (_actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return
	var target: Dictionary = (track[kf_idx] as Dictionary).get("target", {}) as Dictionary
	target[field] = value
	(track[kf_idx] as Dictionary)["target"] = target
	_queue_inspector_rebuild()


## SkillPreviewTimeline 在 track 里找下一个空闲 time_ms。
##
## 算 occupy / 找冲突的纯逻辑住在 SkillPreviewValidation, 这里只是注入
## skill_resolver = HexBattleSkillIndex.get_by_id, 不让 UI 文件再依赖
## TimelineRegistry / HexBattleCooldownSystem。
func _next_free_time_ms_in_track(
	track: Array, candidate_skill_id: String, start_ms: int, skip_kf_idx: int = -1
) -> int:
	var resolver := func(sid: String) -> AbilityConfig:
		return HexBattleSkillIndex.get_by_id(sid)
	return SkillPreviewValidation.next_free_time_ms_in_track(
		track, candidate_skill_id, resolver, start_ms, skip_kf_idx
	)


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
					_queue_inspector_rebuild()
					return
				_actors[actor_idx]["pos"] = [coord.q, coord.r]
				if _selected_kind == SELECT_ACTOR and _selected_actor_idx == actor_idx:
					_selected_hex = coord
				if not _is_playing:
					_apply_actor_position_change(actor_idx, coord.q, coord.r)
				if coord.q != next_q or coord.r != next_r:
					_set_status("Position occupied — moved to nearest free hex")
					_queue_inspector_rebuild()
			"hp":
				_actors[actor_idx]["hp"] = v
				if not _is_playing:
					_apply_actor_hp_change(actor_idx, v)
			"atk":
				_actors[actor_idx]["atk"] = v
				if not _is_playing:
					_apply_actor_atk_change(actor_idx, v)
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
	_environment_ids.clear()

	_world.configure_grid(_build_grid_config())
	if _sanitize_actor_positions():
		_queue_inspector_rebuild()
	if _sanitize_environment_positions():
		_queue_inspector_rebuild()
	var collision_detector := MobaCollisionDetector.new()
	_world.add_system(ProjectileSystem.new(collision_detector, GameWorld.event_collector, false))
	HexBattleAllSkills.register_all_timelines()

	for i in _actors.size():
		_spawn_one_actor(i)
	for i in _environments.size():
		_spawn_one_environment(i)


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


func _sanitize_environment_positions() -> bool:
	var changed := false
	for i in _environments.size():
		var data: Dictionary = _environments[i]
		var pos: Array = data["pos"]
		var coord := HexCoord.new(int(pos[0]), int(pos[1]))
		if _can_place_environment_at_for(coord, i):
			continue
		var adjusted := _nearest_free_environment_coord_for(coord.q, coord.r, i)
		if not adjusted.is_valid():
			continue
		_environments[i]["pos"] = [adjusted.q, adjusted.r]
		changed = true
	return changed


func _nearest_free_environment_coord_for(start_q: int, start_r: int, environment_idx: int) -> HexCoord:
	var start_coord := HexCoord.new(start_q, start_r)
	if _can_place_environment_at_for(start_coord, environment_idx):
		return start_coord
	for distance in range(1, 12):
		var candidates: Array[HexCoord] = [
			HexCoord.new(start_q + distance, start_r),
			HexCoord.new(start_q - distance, start_r),
			HexCoord.new(start_q, start_r + distance),
			HexCoord.new(start_q, start_r - distance),
			HexCoord.new(start_q + distance, start_r - distance),
			HexCoord.new(start_q - distance, start_r + distance),
		]
		for coord in candidates:
			if _can_place_environment_at_for(coord, environment_idx):
				return coord
	return HexCoord.invalid()


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


func _spawn_one_environment(idx: int) -> bool:
	var data: Dictionary = _environments[idx]
	var env_type := str(data.get("type", ENV_STONE_WALL))
	if env_type != ENV_STONE_WALL:
		push_warning("[SkillPreview] unknown environment type: %s" % env_type)
		return false
	var pos: Array = data["pos"]
	var coord := HexCoord.new(int(pos[0]), int(pos[1]))
	if _world.grid == null or not _world.grid.has_tile(coord):
		push_warning("[SkillPreview] environment out of grid: %s @ (%d, %d)" % [env_type, coord.q, coord.r])
		return false

	var env_actor := HexBattleStoneWall.create()
	env_actor.hex_position = coord.duplicate()
	_world.add_actor(env_actor)
	if not _world.grid.place_occupant(coord, env_actor):
		_world.remove_actor(env_actor.get_id())
		push_warning("[SkillPreview] environment placement failed: %s @ (%d, %d)" % [env_type, coord.q, coord.r])
		return false
	if idx >= _environment_ids.size():
		_environment_ids.resize(idx + 1)
	_environment_ids[idx] = env_actor.get_id()
	_world.actor_position_changed.emit(env_actor.get_id(), coord, coord)
	return true


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


func _apply_actor_atk_change(idx: int, atk: float) -> void:
	if idx >= _actor_ids.size():
		return
	var actor_id := _actor_ids[idx]
	var actor := _world.get_actor(actor_id) as CharacterActor
	if actor == null or actor.attribute_set == null:
		return
	actor.attribute_set.set_atk_base(atk)


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
	for i in _environment_ids.size():
		var env_id := _environment_ids[i]
		if env_id == "":
			continue
		var env_actor := _world.get_actor(env_id) as EnvironmentActor
		if env_actor == null:
			continue
		var coord: HexCoord = env_actor.hex_position
		if coord == null or not coord.is_valid():
			continue
		if _world.grid != null and _world.grid.has_tile(coord):
			if not _world.grid.place_occupant(coord, env_actor):
				push_warning("[SkillPreview] environment re-place failed after grid change: %s" % env_id)
		_world.actor_position_changed.emit(env_id, coord, coord)


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


# ========== 3D scene selection / context menu ==========

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
	if not mb.pressed:
		return
	if _is_mouse_over_blocking_ui():
		return
	var coord := _hex_coord_under_mouse()
	if coord == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_select_hex_at(coord)
		get_viewport().set_input_as_handled()
		return
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	_select_hex_at(coord)
	_open_hex_context_menu(coord)
	get_viewport().set_input_as_handled()


func _hex_coord_under_mouse() -> HexCoord:
	if _camera_rig == null:
		_log("[color=red]no camera — cannot raycast[/color]")
		return null
	var cam := _camera_rig.get_camera()
	if cam == null:
		_log("[color=red]no camera — cannot raycast[/color]")
		return null
	var mouse_pos := cam.get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var to := from + dir * 1000.0
	var space := cam.get_world_3d().direct_space_state
	var ground_result := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1)
	)
	if ground_result.is_empty():
		return null
	var world_pos: Vector3 = ground_result["position"]
	if UGridMap.model == null:
		_log("[color=red]UGridMap.model null — map not configured[/color]")
		return null
	var coord := UGridMap.world_to_coord(Vector2(world_pos.x, world_pos.z))
	if not UGridMap.model.has_tile(coord):
		return null
	return coord


func _open_hex_context_menu(coord: HexCoord) -> void:
	if _hex_popup.visible:
		_hex_popup.hide()
	_popup_hex = coord
	_popup_actor_idx = _find_actor_idx_at(coord.q, coord.r)
	_popup_environment_idx = _find_environment_idx_at(coord.q, coord.r)
	_show_hex_popup()


func _show_hex_popup() -> void:
	_hex_popup.clear()
	var q := _popup_hex.q
	var r := _popup_hex.r
	_hex_popup.add_separator("(%d, %d)" % [q, r])
	if _popup_actor_idx == 0:
		_hex_popup.add_item("Caster details", 100)
		_hex_popup.set_item_disabled(_hex_popup.get_item_count() - 1, true)
	elif _popup_actor_idx > 0:
		_hex_popup.add_item("Remove Actor", 11)
	elif _popup_environment_idx >= 0:
		_hex_popup.add_item("Remove StoneWall", 21)
	else:
		_hex_popup.add_item("Add Enemy", 1)
		_hex_popup.add_item("Add Ally", 2)
		_hex_popup.add_item("Add StoneWall", 20)
		_hex_popup.add_item("Move Caster Here", 3)
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
	var coord := _hex_coord_under_mouse()
	if coord == null:
		return
	# 同 hex 不重弹(用户右键当前 popup 所在 hex, 没意图)。
	if _popup_hex != null and _popup_hex.is_valid() and _popup_hex.equals(coord):
		_hex_popup.hide()
		return
	# 不同 hex: 关旧 popup, 在新 hex 重弹。
	_hex_popup.hide()
	_select_hex_at(coord)
	_open_hex_context_menu(coord)


func _on_popup_id_pressed(id: int) -> void:
	var q := _popup_hex.q
	var r := _popup_hex.r
	match id:
		1: _add_actor("dummy", "B", "WARRIOR", q, r)
		2: _add_actor("dummy", "A", "WARRIOR", q, r)
		3: _move_caster_to(q, r)
		11: _remove_actor_at(_popup_actor_idx)
		20: _add_stone_wall(q, r)
		21: _remove_environment_at(_popup_environment_idx)


func _on_speed_changed(v: float) -> void:
	if _animator != null:
		_animator.set_speed(v)


# ========== START / Simulate ==========

func _on_start_pressed() -> void:
	_start_button.disabled = true
	_is_playing = true
	_set_inspector_editable(false)
	_reset_button.disabled = true
	_replay_button.disabled = true
	_refresh_runtime_layout()
	_last_timeline = {}
	_apply_playback_inspector_layout()
	_set_console_expanded(true)
	_set_drawer_tab("Log")
	_set_status("Running...")
	_console_log.clear()

	# 编辑期所有面板/右键操作走 event→update 增量 mutation,
	# world state 与 _actors 数据模型实时一致, 战斗前不需要再 commit。

	if _role_id_to_actor_id.get("caster", "") == "":
		_finish_with_status("No caster in world")
		return

	var setup_error := _find_preview_setup_error()
	if setup_error != "":
		_finish_with_status(setup_error)
		return

	var setups := _collect_actor_setups()
	if setups.is_empty():
		_finish_with_status("No actor setups (something is broken)")
		return

	var has_keyframe := false
	for setup in setups:
		if not (setup.get("track", []) as Array).is_empty():
			has_keyframe = true
			break
	if not has_keyframe:
		_finish_with_status("No skill keyframes — add at least one action to a track")
		return

	_log_battle_start(setups, int(_max_ticks_input.value))

	_world.queue_preview(setups, false)

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
	_replay_button.disabled = _last_timeline.is_empty()
	_set_inspector_editable(true)
	_refresh_runtime_layout()
	_set_status(s)


func _find_preview_setup_error() -> String:
	var skill_resolver := func(sid: String) -> AbilityConfig:
		return HexBattleSkillIndex.get_by_id(sid)
	for actor_idx in _actors.size():
		var actor_data: Dictionary = _actors[actor_idx]
		var track: Array = actor_data.get("track", []) as Array
		for kf_idx in track.size():
			var kf: Dictionary = track[kf_idx]
			var skill_id := str(kf.get("skill", ""))
			var time_ms := int(kf.get("time_ms", 0))
			var skill_cfg := HexBattleSkillIndex.get_by_id(skill_id)
			if skill_cfg == null:
				return "%s @ %dms has unknown skill: %s" % [
					_role_id_for(actor_idx), time_ms, skill_id,
				]
			var target: Dictionary = kf.get("target", {"mode": "auto"}) as Dictionary
			var target_idx := _resolve_target_actor_idx_for_ui(actor_idx, target)
			if _skill_requires_external_target(skill_cfg) and target_idx < 0:
				return "%s @ %dms has no valid target (%s)" % [
					_role_id_for(actor_idx), time_ms, _target_mode_label(str(target.get("mode", "auto"))),
				]
			if not _target_matches_skill_tags(skill_cfg, actor_idx, target_idx):
				return "%s @ %dms target does not match skill tags" % [
					_role_id_for(actor_idx), time_ms,
				]
		# Occupy 兜底: 编辑期已通过 next_free 阻止, 但加载 preset 等绕过路径仍要拦。
		var occupy_err := SkillPreviewValidation.find_track_occupy_violation(
			track, _role_id_for(actor_idx), skill_resolver
		)
		if occupy_err != "":
			return occupy_err
	return ""


## 把 _actors 数据模型转换成 SkillPreviewWorldGI.queue_preview 的 actor_setups 入参。
## 每个 actor: passives 数组解析为 AbilityConfig；track 每条 keyframe 解析:
##   skill (string config_id) → AbilityConfig
##   target (dict) → 具体 actor_id (按 keyframe 自身 caster 的视角解析)
func _collect_actor_setups() -> Array[Dictionary]:
	var setups: Array[Dictionary] = []
	for i in _actors.size():
		if i >= _actor_ids.size() or _actor_ids[i] == "":
			continue
		var data: Dictionary = _actors[i]
		var actor_id: String = _actor_ids[i]
		var actor := _world.get_actor(actor_id) as CharacterActor

		var passive_cfgs: Array[AbilityConfig] = []
		for pid_variant in data.get("passives", []) as Array:
			var pid: String = str(pid_variant)
			var cfg := HexBattleSkillIndex.get_by_id(pid)
			if cfg != null:
				passive_cfgs.append(cfg)

		var track_in: Array = data.get("track", []) as Array
		var track_out: Array[Dictionary] = []
		for kf_variant in track_in:
			var kf: Dictionary = kf_variant as Dictionary
			var skill_id: String = str(kf.get("skill", ""))
			var skill_cfg := HexBattleSkillIndex.get_by_id(skill_id)
			if skill_cfg == null:
				continue
			var target_dict: Dictionary = kf.get("target", {"mode": "auto"}) as Dictionary
			var target_id := _resolve_keyframe_target(target_dict, actor)
			track_out.append({
				"time_ms": int(kf.get("time_ms", 0)),
				"ability_config": skill_cfg,
				"target_id": target_id,
			})

		setups.append({
			"actor_id": actor_id,
			"passives": passive_cfgs,
			"track": track_out,
		})
	return setups


## 按 keyframe 自身 caster (action_caster) 视角解析 target dict → world actor_id 字符串。
##   auto         → action_caster 的最近敌方 character
##   enemy_index  → action_caster 视角第 N 个敌方 (跨 team 不同 actor 解析不同结果)
##   ally_index   → action_caster 视角第 N 个友方 (排除自己)
##   fixed_pos    → 离 (q,r) 最近的 character
func _resolve_keyframe_target(target: Dictionary, action_caster: CharacterActor) -> String:
	var mode: String = str(target.get("mode", "auto"))
	match mode:
		"enemy_index", "ally_index":
			if action_caster == null:
				return ""
			var caster_team := action_caster.get_team_id()
			var want_same_team := mode == "ally_index"
			var idx: int = int(target.get("index", 0))
			var matched: Array[CharacterActor] = []
			for actor in _world.get_actors():
				if not (actor is CharacterActor):
					continue
				var c := actor as CharacterActor
				var same := c.get_team_id() == caster_team
				if want_same_team and (not same or c == action_caster):
					continue
				if not want_same_team and same:
					continue
				matched.append(c)
			return matched[idx].get_id() if idx >= 0 and idx < matched.size() else ""
		"fixed_pos":
			var coord := HexCoord.new(int(target.get("q", 0)), int(target.get("r", 0)))
			var nearest := _find_nearest_character(coord, func(_c: CharacterActor) -> bool: return true)
			return nearest.get_id() if nearest != null else ""
		_:
			if action_caster == null:
				return ""
			var nearest := _find_nearest_character(
				action_caster.hex_position,
				func(c: CharacterActor) -> bool: return c.get_team_id() != action_caster.get_team_id(),
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
		_last_timeline = {}
		_log_battle_end(0)
		_finish_with_status("Empty timeline")
		return

	_dump_timeline_events(timeline)
	_last_battle_frames = _read_total_frames(timeline)
	_last_timeline = timeline
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
	_set_status("Playback ended — 按 RESET 恢复战前状态 / REPLAY 重播录像")
	_is_playing = false
	_reset_button.disabled = false
	_replay_button.disabled = _last_timeline.is_empty()
	_refresh_runtime_layout()


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
	_replay_button.disabled = true
	_last_timeline = {}
	_refresh_runtime_layout()
	_frame_stage_camera()


## 重播缓存的录像: 不动 world, 仅 animator.reset() (director 内部 _world.reset_to
## 把 RenderState 拉回第 0 帧 + view.revive() 复活视觉态) -> play()。
## actor_id 跟战时一致, _unit_views 字典 key 匹配, timeline 事件能正确打到 view。
func _on_replay_pressed() -> void:
	if _is_playing or _last_timeline.is_empty():
		return
	_is_playing = true
	_set_inspector_editable(false)
	_start_button.disabled = true
	_reset_button.disabled = true
	_replay_button.disabled = true
	_refresh_runtime_layout()
	_apply_playback_inspector_layout()
	_set_console_expanded(true)
	_set_drawer_tab("Log")
	_console_log.clear()
	_log_battle_start(_collect_actor_setups(), int(_max_ticks_input.value))
	_dump_timeline_events(_last_timeline)
	_set_status("Replaying — %d frames" % _last_battle_frames)
	_animator.set_speed(float(_speed_input.value))
	_animator.reset()
	_animator.play()


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


## 战报头: timeline 上的所有 keyframe 列出来 (按 time_ms+actor_idx 排序)。
func _log_battle_start(setups: Array[Dictionary], max_ticks: int) -> void:
	_console_log.clear()
	_log(EVENT_DIVIDER)
	_log("  [color=#FF6B6B][b]▶ Timeline[/b][/color]  [color=#A89580]max_ticks=%d[/color]" % max_ticks)
	# 反向 actor_id → role_id 映射, 一次性 O(N) 构建, 内层查 O(1)。
	var actor_id_to_role: Dictionary[String, String] = {}
	for k in _role_id_to_actor_id.keys():
		actor_id_to_role[_role_id_to_actor_id[k]] = k
	# 平铺 + 排序展示
	var rows: Array = []
	for actor_idx in setups.size():
		var setup: Dictionary = setups[actor_idx]
		var actor_id: String = setup.get("actor_id", "?") as String
		var role_id: String = actor_id_to_role.get(actor_id, actor_id)
		# Passive
		var passives: Array = setup.get("passives", []) as Array
		if not passives.is_empty():
			var pids: Array[String] = []
			for cfg in passives:
				if cfg is AbilityConfig:
					pids.append((cfg as AbilityConfig).config_id)
			_log("  [color=#A89580]passive[/color] %s: %s" % [role_id, ", ".join(pids)])
		# Track
		for kf_idx in (setup.get("track", []) as Array).size():
			var kf: Dictionary = (setup["track"] as Array)[kf_idx] as Dictionary
			var ability_cfg := kf.get("ability_config") as AbilityConfig
			rows.append({
				"time_ms": int(kf.get("time_ms", 0)),
				"actor_idx": actor_idx,
				"role_id": role_id,
				"skill_name": ability_cfg.display_name if ability_cfg != null else "?",
				"target_id": str(kf.get("target_id", "")),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["time_ms"] != b["time_ms"]:
			return a["time_ms"] < b["time_ms"]
		return a["actor_idx"] < b["actor_idx"]
	)
	for r in rows:
		var tgt := r["target_id"] as String
		_log("  [color=#6B4F3E]%5dms[/color]  [b]%s[/b]  [color=#FF6B6B]%s[/color]  → %s" % [
			r["time_ms"], r["role_id"], r["skill_name"],
			tgt if tgt != "" else "(none)",
		])
	_log(EVENT_DIVIDER)


func _log_battle_end(last_frame: int) -> void:
	_log(EVENT_DIVIDER)
	_log("  [color=#7FB56B][b]■ ENDED[/b][/color]  [color=#6B4F3E](%d frames · %d ms)[/color]" % [
		last_frame, last_frame * TICK_INTERVAL_MS,
	])
	_log(EVENT_DIVIDER)


## 反查 actor_id → role label ("caster" / "ally_0" / ...), 找不到回退 actor_id。
func _role_label_for_actor_id(actor_id: String) -> String:
	for role_id in _role_id_to_actor_id.keys():
		if _role_id_to_actor_id[role_id] == actor_id:
			return role_id
	return actor_id


## 反查 config_id → display_name, 找不到回退 config_id。
func _skill_display_name_by_config_id(config_id: String) -> String:
	var cfg := HexBattleSkillIndex.get_by_id(config_id)
	if cfg != null:
		return cfg.display_name
	return config_id


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
		"abilityActivateFailed":
			# LGF ActiveUseComponent push: condition / cost 检查失败时上报。
			# 典型场景: SkillPreview 用户排了 timeline 间隔合法 (≥ timeline.total_duration)
			# 但 < cooldown 的 keyframe — UI 不拦, 跑到这里被 cooldown 拒。
			var role := _role_label_for_actor_id(str(ev.get("sourceId", "")))
			var skill_name := _skill_display_name_by_config_id(str(ev.get("abilityConfigId", "")))
			line = "%s  [color=#FF6B6B]⛔[/color] [b]%s[/b]  [color=#FF6B6B]%s 释放失败[/color]  [color=#A89580]%s: %s[/color]" % [
				ts, role, skill_name,
				str(ev.get("failedComponentType", "?")),
				str(ev.get("reason", "?")),
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
	if not _is_preset_v2(data_variant as Dictionary):
		_log("[color=red]Preset version unsupported (v2 required): %s[/color]" % path)
		return
	_deserialize_ui_state(data_variant as Dictionary)
	_log("Preset loaded: %s" % _preset_load_option.get_item_text(idx))


## Preset JSON 格式 (v2, 统一 actors):
##   {
##     "version": 2,
##     "map": {"radius", "orientation", "hex_size"},
##     "actors": [
##       {"role", "team", "class", "pos":[q,r], "hp", "atk",
##        "passives": [String], "track": [Keyframe]},
##       ...
##     ],
##     "environments": [{"type":"stone_wall", "pos":[q,r]}],
##     "controls": {"max_ticks", "speed"}
##   }
##   Keyframe = {"time_ms": int, "skill": String,
##               "target": {"mode", "index", "q", "r"}}
const PRESET_VERSION := 2


func _serialize_ui_state() -> Dictionary:
	return {
		"version": PRESET_VERSION,
		"map": {
			"radius": int(_map_radius_input.value),
			"orientation": "flat" if _map_orientation_option.selected == 1 else "pointy",
			"hex_size": float(_map_hex_size_input.value),
		},
		"actors": _actors.duplicate(true),
		"environments": _environments.duplicate(true),
		"controls": {
			"max_ticks": int(_max_ticks_input.value),
			"speed": _speed_input.value,
		},
	}


func _build_scene_config() -> Dictionary:
	var allies: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	for i in _actors.size():
		var actor_data: Dictionary = _actors[i]
		var pos: Array = actor_data["pos"]
		var payload := {
			"class": str(actor_data.get("class", "WARRIOR")),
			"pos": [int(pos[0]), int(pos[1])],
			"hp": float(actor_data.get("hp", 100.0)),
			"atk": float(actor_data.get("atk", 0.0)),
		}
		if i == 0:
			continue
		if str(actor_data.get("team", "B")) == "A":
			allies.append(payload)
		else:
			enemies.append(payload)
	var caster_pos: Array = (_actors[0] as Dictionary)["pos"]
	return {
		"map": {
			"radius": int(_map_radius_input.value),
			"orientation": "flat" if _map_orientation_option.selected == 1 else "pointy",
			"hex_size": float(_map_hex_size_input.value),
		},
		"caster": {
			"class": str((_actors[0] as Dictionary).get("class", "WARRIOR")),
			"pos": [int(caster_pos[0]), int(caster_pos[1])],
			"hp": float((_actors[0] as Dictionary).get("hp", 100.0)),
			"atk": float((_actors[0] as Dictionary).get("atk", 0.0)),
		},
		"allies": allies,
		"enemies": enemies,
		"environment": _environments.duplicate(true),
	}


## 反序列化 v2 preset; 旧版 (无 version 或 version<2) 直接拒绝, 不做兼容转换。
## 调方需保证 d 已通过 _is_preset_v2 校验。
func _deserialize_ui_state(d: Dictionary) -> void:
	# Map
	var map_cfg: Dictionary = d.get("map", {})
	_map_radius_input.value = map_cfg.get("radius", 5)
	_map_orientation_option.selected = 1 if map_cfg.get("orientation", "flat") == "flat" else 0
	_map_hex_size_input.value = map_cfg.get("hex_size", 1.0)

	# Actors (v2: 内嵌 passives + track)
	var loaded_actors: Array = d.get("actors", [])
	_actors = []
	for a_variant in loaded_actors:
		var a := a_variant as Dictionary
		var pos: Array = a.get("pos", [0, 0])
		var passives_in: Array = a.get("passives", []) as Array
		var passives_str: Array[String] = []
		for p in passives_in:
			passives_str.append(str(p))
		var track_in: Array = a.get("track", []) as Array
		var track_norm: Array[Dictionary] = []
		for kf_variant in track_in:
			var kf := kf_variant as Dictionary
			var target_dict: Dictionary = kf.get("target", {"mode": "auto"}) as Dictionary
			track_norm.append({
				"time_ms": int(kf.get("time_ms", 0)),
				"skill": str(kf.get("skill", "")),
				"target": {
					"mode": str(target_dict.get("mode", "auto")),
					"index": int(target_dict.get("index", 0)),
					"q": int(target_dict.get("q", 0)),
					"r": int(target_dict.get("r", 0)),
				},
			})
		_actors.append({
			"role": a.get("role", "dummy"),
			"team": a.get("team", "B"),
			"class": a.get("class", "WARRIOR"),
			"pos": [int(pos[0]), int(pos[1])],
			"hp": float(a.get("hp", 100.0)),
			"atk": float(a.get("atk", 0.0)),
			"passives": passives_str,
			"track": track_norm,
		})
	if _actors.is_empty() or _actors[0]["role"] != "caster":
		_actors.insert(0, {
			"role": "caster", "team": "A", "class": "WARRIOR",
			"pos": [0, 0], "hp": 0.0, "atk": 0.0,
			"passives": [] as Array[String],
			"track": [] as Array[Dictionary],
		})

	var loaded_environments: Array = d.get("environments", [])
	_environments = []
	for env_variant in loaded_environments:
		var env_data := env_variant as Dictionary
		var env_pos: Array = env_data.get("pos", [0, 0])
		var env_type := str(env_data.get("type", ENV_STONE_WALL))
		if env_type != ENV_STONE_WALL:
			continue
		_environments.append({
			"type": ENV_STONE_WALL,
			"pos": [int(env_pos[0]), int(env_pos[1])],
		})
	_select_actor_at(0, false)
	_rebuild_inspector()

	# Controls
	var ctrl: Dictionary = d.get("controls", {})
	_max_ticks_input.value = ctrl.get("max_ticks", 2000)
	_speed_input.value = ctrl.get("speed", 1.0)

	_reset_world_to_model()


## 阶段一只支持 v2; 未来 v3+ schema 改了字段会被 v2 反序列化静默吞掉默认值,
## 故用 == 拒绝, 加新版时显式扩 supported list。
static func _is_preset_v2(d: Dictionary) -> bool:
	return int(d.get("version", 0)) == PRESET_VERSION


# ========== 工具 ==========

func _set_status(s: String) -> void:
	_status_label.text = "Status: " + s
	if _console_summary_label != null:
		_console_summary_label.text = s
	_update_timeline_mode_buttons()


func _on_console_toggle_pressed() -> void:
	_set_console_expanded(not _console_expanded)


func _on_control_toggle_pressed() -> void:
	_set_controls_collapsed(not _controls_collapsed)


func _set_console_expanded(expanded: bool) -> void:
	_console_expanded = expanded
	if _drawer_tabs != null:
		_drawer_tabs.visible = expanded
	_console_toggle_button.text = "v" if expanded else "^"
	_console_toggle_button.tooltip_text = "Collapse workspace" if expanded else "Expand workspace"
	_update_workspace_layout()


func _set_controls_collapsed(collapsed: bool) -> void:
	_controls_collapsed = collapsed
	if _control_toggle_button != null:
		_control_toggle_button.text = "<" if collapsed else ">"
		_control_toggle_button.tooltip_text = "Expand controls" if collapsed else "Collapse controls"
	_update_workspace_layout()


func _set_drawer_tab(tab_name: String) -> void:
	if _drawer_tabs == null:
		return
	for i in _drawer_tabs.get_tab_count():
		if _drawer_tabs.get_tab_title(i) == tab_name:
			_drawer_tabs.current_tab = i
			return


func _set_inspector_editable(editable: bool) -> void:
	_left_panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if editable else 0.72)
	_set_controls_editable(_left_panel, editable)
	if _drawer_tabs != null:
		_drawer_tabs.modulate = Color(1.0, 1.0, 1.0, 1.0 if editable else 0.72)
		_set_controls_editable(_drawer_tabs, editable)
	if _details_popup != null:
		_details_popup.modulate = Color(1.0, 1.0, 1.0, 1.0 if editable else 0.72)
		_set_controls_editable(_details_popup, editable)
	if _character_panel != null:
		_character_panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if editable else 0.78)
		_set_controls_editable(_character_panel, editable)
	_speed_input.editable = true
	_speed_input.get_line_edit().editable = true
	_refresh_runtime_layout()


func _set_controls_editable(node: Node, editable: bool) -> void:
	for child in node.get_children():
		if child == _reset_button:
			continue
		if child is Button:
			var button := child as Button
			button.disabled = false if _control_always_enabled(button) else (not editable) or _control_force_disabled(button)
		elif child is SpinBox:
			var spin := child as SpinBox
			var can_edit := editable and not _control_force_disabled(spin)
			spin.editable = can_edit
			spin.get_line_edit().editable = can_edit
		elif child is OptionButton:
			(child as OptionButton).disabled = (not editable) or _control_force_disabled(child as Control)
		elif child is CheckBox:
			(child as CheckBox).disabled = (not editable) or _control_force_disabled(child as Control)
		_set_controls_editable(child, editable)


func _control_force_disabled(control: Control) -> bool:
	return control.has_meta("force_disabled") and bool(control.get_meta("force_disabled"))


func _control_always_enabled(control: Control) -> bool:
	return control.has_meta("always_enabled") and bool(control.get_meta("always_enabled"))


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
const PASSIVE_SELECTED_BG := Color("DCFCE7")
const PASSIVE_SELECTED_HOVER := Color("BBF7D0")
const PASSIVE_SELECTED_PRESSED := Color("86EFAC")
const PASSIVE_SELECTED_BORDER := Color("22C55E")
const PASSIVE_SELECTED_TEXT := Color("14532D")
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
	_style_character_panel()
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


func _style_floating_toggle_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _clay_sb(Color("FFFFFF"), 6, 8, 4, 1, 5))
	btn.add_theme_stylebox_override("hover", _clay_sb(Color("EAF2FF"), 6, 8, 4, 1, 6))
	btn.add_theme_stylebox_override("pressed", _clay_sb(Color("CFE1FF"), 6, 8, 4, 0, 0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", _clay_font_bold())
	btn.add_theme_color_override("font_color", CLAY_TEXT)
	btn.add_theme_color_override("font_hover_color", CLAY_TEXT)
	btn.add_theme_color_override("font_pressed_color", START_PRESSED)


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


func _style_character_panel() -> void:
	var title := get_node_or_null("ConfigUI/Root/CharacterPanel/CharacterPanelVBox/CharacterPanelHeader/CharacterPanelTitle") as Label
	if title != null:
		title.add_theme_font_override("font", _clay_font_bold())
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", CLAY_TEXT)
	if _character_panel_mode_label != null:
		_character_panel_mode_label.add_theme_font_override("font", _clay_font_bold())
		_character_panel_mode_label.add_theme_font_size_override("font_size", 11)
		_character_panel_mode_label.add_theme_color_override("font_color", START_PRESSED)
		_character_panel_mode_label.add_theme_stylebox_override(
			"normal",
			_outlined_sb(Color("EAF2FF"), Color("7AA7F7"), 5, 7, 3)
		)


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


## Passive CheckBox 选中/未选中视觉: 选中 = 浅绿底 + 深绿字,
## 未选中 = 默认白底。直接 override 每个状态 stylebox 让渲染顺序无歧义。
##
## passive 选择只 mutate _actors[idx]["passives"] 数据模型, 编辑期 world 不感知
## passive (passive 是战斗 start() 时 grant 给 actor), 因此勾选/取消勾选不需要
## 触发 world mutation。
func _apply_passive_style(cb: CheckBox, selected: bool) -> void:
	if selected:
		var sb := _clay_sb(PASSIVE_SELECTED_BG, 6, 6, 3, 0, 0)
		sb.border_color = PASSIVE_SELECTED_BORDER
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		cb.add_theme_stylebox_override("normal", sb)
		cb.add_theme_stylebox_override("hover",
			_outlined_sb(PASSIVE_SELECTED_HOVER, PASSIVE_SELECTED_BORDER, 6, 6, 3))
		cb.add_theme_stylebox_override("pressed",
			_outlined_sb(PASSIVE_SELECTED_PRESSED, PASSIVE_SELECTED_BORDER, 6, 6, 3))
		cb.add_theme_stylebox_override("hover_pressed",
			_outlined_sb(PASSIVE_SELECTED_HOVER, PASSIVE_SELECTED_BORDER, 6, 6, 3))
		cb.add_theme_color_override("font_color", PASSIVE_SELECTED_TEXT)
		cb.add_theme_color_override("font_hover_color", PASSIVE_SELECTED_TEXT)
		cb.add_theme_color_override("font_pressed_color", PASSIVE_SELECTED_TEXT)
		cb.add_theme_color_override("font_hover_pressed_color", PASSIVE_SELECTED_TEXT)
	else:
		cb.remove_theme_stylebox_override("normal")
		cb.remove_theme_stylebox_override("hover")
		cb.remove_theme_stylebox_override("pressed")
		cb.remove_theme_stylebox_override("hover_pressed")
		cb.remove_theme_color_override("font_color")
		cb.remove_theme_color_override("font_hover_color")
		cb.remove_theme_color_override("font_pressed_color")
		cb.remove_theme_color_override("font_hover_pressed_color")


## Console: 深紫底 + 亮字, 对比 vibrant 主面板
func _style_console() -> void:
	_console_panel.add_theme_stylebox_override("panel",
		_clay_sb(CONSOLE_BG, 8, 12, 10, 2, 8))
	_console_log.add_theme_color_override("default_color", CONSOLE_FG)
	_console_log.add_theme_font_size_override("normal_font_size", 12)
	_console_summary_label.add_theme_color_override("font_color", Color("CBD5E1"))
	_console_summary_label.add_theme_font_size_override("font_size", 12)
	_style_floating_toggle_button(_console_toggle_button)
