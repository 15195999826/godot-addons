## RtsPathfindingDemo - 寻路验证可交互 demo (P3.2 + P3.3 合体应用)
##
## 编辑器 F6 运行: 8 个 team 0 melee 起在左下 + 3 个 team 1 静态 barracks 中央作障碍 +
## 1 个 team 1 dummy barracks 角落保 fallback 不立即判败. 玩家通过鼠标:
##   - 左键拖框: 框选 team 0 单位 (拖距 < 5px 视为单击, 选最近 unit; 否则 rect 选)
##   - 左键单击空白处: 清选中 (clicked nothing)
##   - 右键: 对选中单位 enqueue MoveUnitsCommand 走到 click pos (formation 排队)
##   - K 键: (调试) 在选中 unit 当前位置加 static obstacle 验证 dynamic obstacle 路径
##
## 与 castle-war demo 的差异:
##   - 没有 ct / 没有 archer / 没有 production / 没有 AI 进军
##   - 单位 stance=HOLD_FIRE — 不主动找敌, 玩家命令才动
##   - 主战线 = 玩家选 + 命令 → 走到 + 看 formation + 看绕障
##
## 4 寻路验证点对应玩家操作 (假定 600x500 viewport):
##   (a) 绕 barracks footprint: 框选 8 unit → 右键 (550, 250) → 看穿越中央 3 barracks 路径
##   (b) 多单位互避障不卡: 同上 → pairwise 不重叠
##   (c) Formation 保形: 抵达后看方阵
##   (d) 动态 obstacle: 选单 unit → 右键远端 → K 加路上 obstacle → 看绕路
##
## 关键不变量:
##   - demo 不读 actor.position_2d 决定渲染 (push 模式 — visualizer 走 director state)
##   - 选中态业务逻辑只在 demo 里 (_selected_unit_ids); visualizer 仅渲染 set_selected 标志
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")


# ========== 配置 ==========

const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 0  # 0 = 随机 (每次 F6 不同 RNG)
const MAP_SIZE: Vector2 = Vector2(600.0, 500.0)
const SINGLE_CLICK_THRESHOLD: float = 5.0  # 拖距 < 此值视为单击
const SINGLE_CLICK_PICK_RADIUS: float = 24.0  # 单击查找最近 unit 半径

# 8 个 team 0 melee 起始 (左下角散布)
const TEAM0_START_POSITIONS: Array[Vector2] = [
	Vector2(50.0, 380.0), Vector2(80.0, 380.0), Vector2(110.0, 380.0), Vector2(140.0, 380.0),
	Vector2(50.0, 420.0), Vector2(80.0, 420.0), Vector2(110.0, 420.0), Vector2(140.0, 420.0),
]

# 3 个 team 1 barracks 中央作障碍 (cells 散布)
const OBSTACLE_POSITIONS: Array[Vector2] = [
	Vector2(250.0, 200.0),
	Vector2(350.0, 280.0),
	Vector2(450.0, 180.0),
]

# 角落 dummy barracks 让 fallback team-wipeout 不立即判右胜
const DUMMY_BARRACKS_POS: Vector2 = Vector2(590.0, 470.0)


# ========== 节点引用 ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _director: RtsBattleDirector = null
var _world_view: RtsWorldView = null

var _agents: Dictionary = {}        # actor_id → RtsNavAgent
var _controllers: Dictionary = {}   # actor_id → RtsUnitController
var _team0_unit_ids: Array[String] = []

var _hud_label: Label = null
var _drag_overlay: _DragOverlay = null

var _started: bool = false
var _finalized: bool = false

# Selection / drag state (frontend-only, 不进 logic)
var _selected_unit_ids: Array[String] = []
var _drag_start: Vector2 = Vector2.ZERO
var _drag_curr: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _last_command_summary: String = "(none)"


# ========== 生命周期 ==========

func _ready() -> void:
	GameWorld.init()

	# 1. 战场地图 (含 grid)
	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	# 2. World instance
	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_battle_map.grid)

	# 3. Director + WorldView (P2.7 流式 sim)
	_director = RtsBattleDirector.new()
	_director.name = "BattleDirector"
	add_child(_director)

	_world_view = RtsWorldView.new()
	_world_view.name = "WorldView"
	_battle_map.add_child(_world_view)
	_world_view.bind(_world, _director)

	# 4. 起手 spawn: 3 obstacle barracks + 1 dummy + 8 team 0 melee (HOLD_FIRE)
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	for ob_pos in OBSTACLE_POSITIONS:
		var ob := RtsBuildings.create_barracks()
		ob.set_team_id(1)  # team 1 占位
		_world.add_actor(ob)
		ob.position_2d = ob_pos
		right_actors.append(ob)

	var dummy := RtsBuildings.create_barracks()
	dummy.set_team_id(1)
	_world.add_actor(dummy)
	dummy.position_2d = DUMMY_BARRACKS_POS
	right_actors.append(dummy)

	for sp in TEAM0_START_POSITIONS:
		var unit := _spawn_unit(Config.UnitClass.MELEE, 0, sp)
		unit.stance = RtsUnitActor.Stance.HOLD_FIRE  # 玩家命令才动
		left_actors.append(unit)
		_team0_unit_ids.append(unit.get_id())

	# 5. 启动战斗 (无 team_configs build_zone — pathfinding demo 不放兵营走 PlaceBuildingCommand;
	#    但 team 1 至少有 alive actor 让 fallback team-wipeout 不立即判败)
	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"rng_seed": RNG_SEED,
	})

	_director.attach(_world, _procedure)
	_started = true

	_setup_hud()
	_setup_drag_overlay()


func _process(_delta: float) -> void:
	if _hud_label != null and _procedure != null:
		_hud_label.text = "selected: %d  |  last cmd: %s  |  tick: %d\nLeft-drag select / right-click move (formation) / K to add obstacle at first selected unit" % [
			_selected_unit_ids.size(), _last_command_summary, _procedure.get_current_tick(),
		]
	# Drag overlay 同步当前 mouse pos
	if _is_dragging and _drag_overlay != null:
		_drag_curr = get_viewport().get_mouse_position()
		_drag_overlay.update_rect(_drag_start, _drag_curr)


# ========== 玩家输入 ==========

func _unhandled_input(event: InputEvent) -> void:
	if not _started or _finalized:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		_handle_key_k()
		return

	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_start = mb.position
			_drag_curr = mb.position
			_is_dragging = true
			if _drag_overlay != null:
				_drag_overlay.update_rect(_drag_start, _drag_curr)
				_drag_overlay.visible = true
		else:
			# release
			_is_dragging = false
			if _drag_overlay != null:
				_drag_overlay.visible = false
			var release_pos: Vector2 = mb.position
			var drag_dist: float = release_pos.distance_to(_drag_start)
			if drag_dist < SINGLE_CLICK_THRESHOLD:
				_handle_single_click(release_pos)
			else:
				_handle_rect_select(_drag_start, release_pos)
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_handle_right_click(mb.position)
		return


# ========== Selection 操作 ==========

func _handle_single_click(pos: Vector2) -> void:
	# 找最近 team 0 alive unit (within SINGLE_CLICK_PICK_RADIUS); 找不到 → 清选
	var best_id: String = ""
	var best_d: float = SINGLE_CLICK_PICK_RADIUS
	for uid in _team0_unit_ids:
		var actor := _world.get_actor(uid) as RtsUnitActor
		if actor == null or actor.is_dead():
			continue
		var d: float = actor.position_2d.distance_to(pos)
		if d <= best_d:
			best_d = d
			best_id = uid
	_set_selection([best_id] if best_id != "" else [])


func _handle_rect_select(start: Vector2, end: Vector2) -> void:
	var rect: Rect2 = Rect2(start, Vector2.ZERO).expand(end)
	var ids: Array[String] = []
	for uid in _team0_unit_ids:
		var actor := _world.get_actor(uid) as RtsUnitActor
		if actor == null or actor.is_dead():
			continue
		if rect.has_point(actor.position_2d):
			ids.append(uid)
	_set_selection(ids)


func _set_selection(new_ids: Array[String]) -> void:
	# 取消旧选中
	for uid in _selected_unit_ids:
		_set_visualizer_selected(uid, false)
	_selected_unit_ids = new_ids.duplicate()
	for uid in _selected_unit_ids:
		_set_visualizer_selected(uid, true)


func _set_visualizer_selected(actor_id: String, selected: bool) -> void:
	if _world_view == null:
		return
	var vis := _world_view.get_visualizer(actor_id)
	if vis != null and vis.has_method("set_selected"):
		vis.call("set_selected", selected)


# ========== 命令 ==========

func _handle_right_click(pos: Vector2) -> void:
	if _selected_unit_ids.is_empty():
		_last_command_summary = "no selection (right-click ignored)"
		return
	var current_tick: int = _procedure.get_current_tick() if _procedure != null else 0
	var cmd := RtsMoveUnitsCommand.new(current_tick, 0, _selected_unit_ids.duplicate(), pos)
	_procedure.enqueue_player_command(cmd)
	_last_command_summary = "MoveUnits N=%d → %s @ tick=%d" % [
		_selected_unit_ids.size(), str(pos), current_tick,
	]


func _handle_key_k() -> void:
	# 在第一个选中 unit 当前位置投放一个 barracks 当 obstacle (绕过 build_zone — 直接 add_actor)
	if _selected_unit_ids.is_empty():
		_last_command_summary = "no selection (K ignored)"
		return
	var first_uid: String = _selected_unit_ids[0]
	var actor := _world.get_actor(first_uid) as RtsUnitActor
	if actor == null:
		return
	var ob_pos: Vector2 = actor.position_2d + Vector2(40.0, 0.0)  # 在前方 40px 投放
	var ob := RtsBuildings.create_barracks()
	ob.set_team_id(1)
	_world.add_actor(ob)
	ob.position_2d = ob_pos
	var footprint: Array = ob.get_footprint_cells(_battle_map.grid)
	_battle_map.grid.place_building(ob.get_id(), footprint)
	_last_command_summary = "K: spawned obstacle @ %s" % str(ob_pos)


# ========== Spawn ==========

func _spawn_unit(unit_class: Config.UnitClass, team_id: int, pos: Vector2) -> RtsUnitActor:
	var actor := RtsUnitActor.new(unit_class)
	actor.set_team_id(team_id)
	_world.add_actor(actor)
	actor.position_2d = pos

	var agent := RtsNavAgent.new()
	_battle_map.add_child(agent)
	agent.bind_actor(actor, _battle_map.grid)
	_agents[actor.get_id()] = agent

	var strategy := RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(actor, agent, strategy)
	_controllers[actor.get_id()] = controller
	return actor


# ========== HUD / Overlay ==========

func _setup_hud() -> void:
	_hud_label = Label.new()
	_hud_label.name = "Hud"
	_hud_label.position = Vector2(10.0, 10.0)
	_hud_label.add_theme_font_size_override("font_size", 14)
	_hud_label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	add_child(_hud_label)


func _setup_drag_overlay() -> void:
	_drag_overlay = _DragOverlay.new()
	_drag_overlay.name = "DragOverlay"
	_drag_overlay.visible = false
	add_child(_drag_overlay)


# ========== _DragOverlay ==========

## 拖框框线: 黄色半透明 stroke. 内嵌类避免暴露 demo 内部.
class _DragOverlay extends Node2D:
	const STROKE_COLOR: Color = Color(1.0, 0.9, 0.2, 0.85)
	const FILL_COLOR: Color = Color(1.0, 0.9, 0.2, 0.10)
	const STROKE_WIDTH: float = 2.0
	var _rect: Rect2 = Rect2()

	func update_rect(start: Vector2, end: Vector2) -> void:
		_rect = Rect2(start, Vector2.ZERO).expand(end)
		queue_redraw()

	func _draw() -> void:
		if _rect.size == Vector2.ZERO:
			return
		draw_rect(_rect, FILL_COLOR, true)
		draw_rect(_rect, STROKE_COLOR, false, STROKE_WIDTH)
