## RtsFrontendDemo - 经济闭环 + AI vs AI RTS demo + 玩家 BuildPanel 放置 + Minimap.
##
## F6 运行: 双方各 5 worker + 1 crystal_tower + 2 gold node + 2 wood node; 双方都 attach
## RtsComputerPlayer; worker 自动 harvest → AI 攒资源放 barracks → barracks 生产 melee →
## attack-move 攻敌 ct; 任一 ct 死判胜负.
##
## 玩家通过屏幕底部 BuildPanel 选 building_kind → 进入 placement mode → ghost 跟鼠标 +
## grid snap → 左键放下 (失败留 mode) / ESC / 右键取消.
##
## Camera2D zoom=3 居中 (250, 250); WASD 移动主 camera (placement mode 下禁 WASD 避免冲突).
## 屏幕右下角 Minimap 实时画 actor 点 + camera viewport 框; 点 minimap → camera 跳.
##
## 不变量:
##   - demo 不读 actor 状态 — position / hp / team_id 走 director.get_render_state, 资源走 procedure
##   - 玩家命令 tick_stamp = current_tick → 立即 apply (procedure step 1.5)
##   - BuildPanel + ghost + minimap + camera 是纯 frontend 状态机 → replay 不破
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

# ========== 配置 ==========

const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 0  # 0 = 随机种子 (每次 F6 不同战斗); 调试用可固定到任意正数

# Demo 起手资源 (仅 fallback path; preset 路径走 RtsMatchPreset.starting_resources_left).
# 调高让玩家手测 placement 链路时不被资源限死 — 起手能放 ~6 barracks (80g+50w 一个) +
# 几个 archer_tower (60g+100w 一个).
const STARTING_GOLD_LEFT: int = 500
const STARTING_WOOD_LEFT: int = 500

# 双方阵地基线 x; 主战线在 y=200~280 之间.
const LEFT_BASE_X: float = 80.0
const RIGHT_BASE_X: float = 420.0

const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 200.0, 400.0)

# worker / node 起手布局
const NUM_WORKERS_PER_TEAM: int = 5
const WORKER_SPAWN_DELTA_Y: float = 30.0
const LEFT_WORKER_SPAWN_X: float = LEFT_BASE_X + 50.0   # 130
const RIGHT_WORKER_SPAWN_X: float = RIGHT_BASE_X - 50.0  # 370
const WORKER_SPAWN_BASE_Y: float = 200.0
const LEFT_CT_POS: Vector2 = Vector2(LEFT_BASE_X, 350.0)
const RIGHT_CT_POS: Vector2 = Vector2(RIGHT_BASE_X, 350.0)

# 各侧 2 gold + 2 wood 中立 node (team_id=-1); worker 选最近自然分流
const LEFT_GOLD_NODE_POSITIONS: Array[Vector2] = [
	Vector2(180.0, 220.0),
	Vector2(180.0, 280.0),
]
const LEFT_WOOD_NODE_POSITIONS: Array[Vector2] = [
	Vector2(180.0, 350.0),
	Vector2(180.0, 410.0),
]
const RIGHT_GOLD_NODE_POSITIONS: Array[Vector2] = [
	Vector2(320.0, 220.0),
	Vector2(320.0, 280.0),
]
const RIGHT_WOOD_NODE_POSITIONS: Array[Vector2] = [
	Vector2(320.0, 350.0),
	Vector2(320.0, 410.0),
]


# ========== 节点引用 (scene-driven, 全部 .tscn 拼好 + @onready 拿引用) ==========
#
# Scene 树见 demo_rts_frontend.tscn:
#   RtsFrontendDemo (root)
#   ├── BattleMap (RtsBattleMap)
#   │   ├── MainCamera (Camera2D)
#   │   ├── WorldView (RtsWorldView)        ← actor visualizer 仍 dynamic spawn
#   │   └── PlacementGhost (ColorRect)
#   ├── BattleDirector (RtsBattleDirector)
#   ├── Hud (VBox: Row_Gold/Row_Wood/Hint/Hp)
#   ├── BuildPanel (instance .tscn)
#   └── Minimap (instance .tscn)

@onready var _battle_map: RtsBattleMap = $BattleMap
@onready var _world_view: RtsWorldView = $BattleMap/WorldView
@onready var _camera: Camera2D = $BattleMap/MainCamera
@onready var _placement_ghost: ColorRect = $BattleMap/PlacementGhost
@onready var _director: RtsBattleDirector = $BattleDirector
@onready var _gold_label: Label = $UI/Hud/Row_Gold/Value
@onready var _wood_label: Label = $UI/Hud/Row_Wood/Value
@onready var _hud_hint_label: Label = $UI/Hud/Hint
@onready var _hud_hp_label: Label = $UI/Hud/Hp
@onready var _build_panel: RtsBuildPanel = $UI/BuildPanel
@onready var _minimap: RtsMinimap = $UI/Minimap

# 运行时构造的 logic 层对象 (scene tree 之外, 数据驱动)
var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _agents: Dictionary = {}        # actor.id → RtsNavAgent (logic 层)
var _controllers: Dictionary = {}   # actor.id → RtsUnitController (logic 层)

# 关键 actor 引用 (HUD / 玩家命令上下文)
var _left_ct: RtsBuildingActor = null
var _right_ct: RtsBuildingActor = null

# Placement mode state
const _NO_PLACEMENT_KIND: String = ""
const _GHOST_OK_COLOR: Color = Color(0.30, 0.90, 0.30, 0.35)
const _GHOST_BAD_COLOR: Color = Color(0.95, 0.25, 0.25, 0.35)

## 当前 placement mode 选中的 building_kind; `_NO_PLACEMENT_KIND` = 未在 mode.
var _placement_kind: String = _NO_PLACEMENT_KIND
## 进 mode 时缓存 stats / bbox 偏置, 避免每帧重算 footprint 偶数偏置 + new StatBlock.
var _placement_stats: RtsBuildingConfig.StatBlock = null
var _placement_ghost_offset: Vector2 = Vector2.ZERO

# Camera 配置常量
const _CAMERA_MOVE_SPEED: float = 200.0  # px/sec (world-space, 不受 zoom 影响)
const _MAP_SIZE: Vector2 = Vector2(500.0, 500.0)

# Optional setup (main_menu 选预设后注入; null = 走 hardcode fallback).
var _preset: RtsMatchPreset = null

var _started: bool = false
var _finalized: bool = false


# ========== 预设入口 ==========

## main_menu 实例化 demo 后立刻调用, _ready 之前注入. 之后 _ready 内字段读 preset 优先.
func apply_preset(p: RtsMatchPreset) -> void:
	_preset = p


# ========== 生命周期 ==========

func _ready() -> void:
	GameWorld.init()
	_register_camera_keys()

	# preset 字段优先, 缺则走 hardcode fallback (frontend smoke headless 路径不破).
	var fallback_left: Dictionary[String, int] = {"gold": STARTING_GOLD_LEFT, "wood": STARTING_WOOD_LEFT}
	var fallback_right: Dictionary[String, int] = {}
	var eff_resources_left: Dictionary[String, int] = _preset.starting_resources_left if _preset != null else fallback_left
	var eff_resources_right: Dictionary[String, int] = _preset.starting_resources_right if _preset != null else fallback_right
	var eff_num_workers: int = _preset.num_workers_per_team if _preset != null else NUM_WORKERS_PER_TEAM
	# Fallback (F6 直接跑 demo, 无 preset): 左队=玩家手控 (attach_left_ai=false), 右队=AI 对手.
	# 玩家自由测 BuildPanel placement 链路, 对面 AI 攒资源造兵营来打 — 不会自己起手帮玩家建.
	var eff_attach_left_ai: bool = _preset.attach_left_ai if _preset != null else false
	var eff_attach_right_ai: bool = _preset.attach_right_ai if _preset != null else true
	var eff_show_build_panel: bool = _preset.show_build_panel if _preset != null else true

	# Scene tree 已挂好 BattleMap (含 grid) / Camera / WorldView / Director / Hud /
	# BuildPanel / Minimap; 此处只做 logic 层 wiring.

	# 1. Camera 接管 viewport (Camera2D 默认不 current)
	_camera.make_current()

	# 2. World instance
	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_battle_map.grid)

	# 3. Director + WorldView wiring (节点已存在, 只 connect / bind)
	_director.battle_ended.connect(_on_battle_ended)
	_world_view.bind(_world, _director)

	# 4. 起手 spawn: 双方 ct + 5 worker + 中立 4 node
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	# 双方 crystal_tower (主基地 + drop-off)
	_left_ct = RtsBuildings.create_crystal_tower()
	_left_ct.set_team_id(0)
	_world.add_actor(_left_ct)
	_left_ct.position_2d = LEFT_CT_POS
	# M0.5 — sync obstruction_shape.center 到 position_2d (place_building 由 procedure.start 在后续做)
	_left_ct.sync_obstruction_shape()
	left_actors.append(_left_ct)

	_right_ct = RtsBuildings.create_crystal_tower()
	_right_ct.set_team_id(1)
	_world.add_actor(_right_ct)
	_right_ct.position_2d = RIGHT_CT_POS
	_right_ct.sync_obstruction_shape()
	right_actors.append(_right_ct)

	# 双方各 N worker (preset.num_workers_per_team / fallback NUM_WORKERS_PER_TEAM)
	for i in range(eff_num_workers):
		var lp: Vector2 = Vector2(LEFT_WORKER_SPAWN_X, WORKER_SPAWN_BASE_Y + WORKER_SPAWN_DELTA_Y * float(i))
		left_actors.append(_spawn_unit(Config.UnitClass.WORKER, 0, lp))
		var rp: Vector2 = Vector2(RIGHT_WORKER_SPAWN_X, WORKER_SPAWN_BASE_Y + WORKER_SPAWN_DELTA_Y * float(i))
		right_actors.append(_spawn_unit(Config.UnitClass.WORKER, 1, rp))

	# 中立 ResourceNode 双方各 2 gold + 2 wood (worker 选最近自然分流)
	_spawn_resource_nodes(LEFT_GOLD_NODE_POSITIONS, true)
	_spawn_resource_nodes(LEFT_WOOD_NODE_POSITIONS, false)
	_spawn_resource_nodes(RIGHT_GOLD_NODE_POSITIONS, true)
	_spawn_resource_nodes(RIGHT_WOOD_NODE_POSITIONS, false)

	# 5. 启动战斗 (含 team_configs + production spawner)
	var left_cfg := RtsTeamConfig.create(0, "human", eff_resources_left, LEFT_BUILD_ZONE)
	var right_cfg := RtsTeamConfig.create(1, "ai", eff_resources_right, Rect2())
	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": RNG_SEED,
	})

	# 6. Director attach (procedure 已存在, 接管 event_sink + broadcast 起手 state)
	_director.attach(_world, _procedure)

	# 7. AI attach — 由 preset 决定哪侧 AI; 玩家鼠标命令仍可同步 enqueue.
	if eff_attach_left_ai:
		_procedure.attach_computer_player(0)
	if eff_attach_right_ai:
		_procedure.attach_computer_player(1)

	_started = true

	# Scene 已挂好 BuildPanel + Minimap; 此处只 connect signal + 按 preset 收尾配置.
	_build_panel.building_selected.connect(_on_building_selected)
	if not eff_show_build_panel:
		_build_panel.visible = false
	_minimap.bind(_MAP_SIZE, _director, _camera)
	_minimap.world_position_clicked.connect(_on_minimap_clicked)


func _process(delta: float) -> void:
	if _procedure == null or _director == null:
		return

	# 资源 dict 同帧复用 — HUD + ghost tint 都读, 避免 procedure 内 2 次 dict 拷贝
	var resources: Dictionary = _procedure.get_team_resources(0)

	if _gold_label != null and _wood_label != null:
		_gold_label.text = "%d" % int(resources.get("gold", 0))
		_wood_label.text = "%d" % int(resources.get("wood", 0))

		var left_state: Dictionary = _director.get_render_state(_left_ct.get_id()) if _left_ct != null else {}
		var right_state: Dictionary = _director.get_render_state(_right_ct.get_id()) if _right_ct != null else {}
		var left_hp: float = float(left_state.get("hp", 0.0))
		var right_hp: float = float(right_state.get("hp", 0.0))
		_hud_hp_label.text = "Left CT HP: %.0f   Right CT HP: %.0f" % [left_hp, right_hp]

		_hud_hint_label.text = (
			"[Placement: %s] left mouse to place | ESC / right mouse to cancel" % _placement_kind
			if _placement_kind != _NO_PLACEMENT_KIND
			else "WASD: pan camera | click BuildPanel: build (left zone) | click minimap: jump"
		)

	if _placement_kind != _NO_PLACEMENT_KIND:
		_update_placement_ghost(resources)
	else:
		_update_camera_from_input(delta)

	if _minimap != null:
		_minimap.queue_redraw()


## WASD 主 camera 移动 — 仅在非 placement mode 调; Camera2D limit_* 自动 clamp 边界.
func _update_camera_from_input(delta: float) -> void:
	if _camera == null:
		return
	var dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir.is_zero_approx():
		return
	_camera.position += dir * _CAMERA_MOVE_SPEED * delta


# ========== 玩家输入 ==========

## placement mode 下处理鼠标放置 / 取消 / ESC; 否则忽略 (玩家必须先点 BuildPanel).
func _unhandled_input(event: InputEvent) -> void:
	if not _started or _finalized or _placement_kind == _NO_PLACEMENT_KIND:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# event.position 是 viewport 屏幕坐标; Camera2D zoom!=1 / position 偏移时
				# 跟世界坐标不同. 用 BattleMap.get_local_mouse_position() 拿到 Node2D 局部 = 世界坐标,
				# 跟 ghost 预览路径一致 (_update_placement_ghost 也用此 API).
				var grid := _battle_map.grid
				var mouse_world: Vector2 = _battle_map.get_local_mouse_position()
				var snapped_world: Vector2 = grid.coord_to_world(grid.world_to_coord(mouse_world))
				_try_place_at(snapped_world)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_exit_placement_mode("right_click")
				get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_exit_placement_mode("escape")
		get_viewport().set_input_as_handled()


## 左键点放尝试 — _validate_player_placement 同步预检; 通过 → enqueue + 退 mode;
## 失败 → console log + 留 mode 让玩家重选 (resources / cells_occupied / out_of_zone 都同处理).
func _try_place_at(world_pos: Vector2) -> void:
	var check: Dictionary = _validate_player_placement(world_pos, _procedure.get_team_resources(0))
	if not check.get("success", false):
		print("[RtsFrontendDemo] placement failed: %s @ %s (kind=%s; stay in mode)" % [
			check.get("reason", "?"), world_pos, _placement_kind,
		])
		return

	var current_tick: int = _procedure.get_current_tick()
	_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		current_tick, 0, _placement_kind, world_pos,
	))
	print("[RtsFrontendDemo] enqueued PlaceBuildingCommand %s @ %s tick_stamp=%d" % [
		_placement_kind, world_pos, current_tick,
	])
	_exit_placement_mode("placed")


## 玩家 (team_id=0) 放置合法性检查 — 调方提供 team_remaining (避免 _process 内每帧 2 次拷 dict).
func _validate_player_placement(world_pos: Vector2, team_remaining: Dictionary) -> Dictionary:
	return RtsBuildingPlacement.validate(
		_battle_map.grid,
		_procedure.get_team_config(0),
		team_remaining,
		_placement_kind,
		world_pos,
	)


# ========== Spawn ==========

## 创建 unit + nav agent + controller; visualizer 由 WorldView 自动创建.
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


## 中立 (team_id=-1) ResourceNode 起手 spawn helper.
func _spawn_resource_nodes(positions: Array[Vector2], is_gold: bool) -> void:
	for pos in positions:
		var node: RtsResourceNode = RtsResourceNodes.create_gold_node() if is_gold else RtsResourceNodes.create_wood_node()
		node.set_team_id(-1)
		_world.add_actor(node)
		node.position_2d = pos


## 玩家放兵营后 production_system 调用 spawner — 让 spawn 出来的 melee 朝对方 ct 进军。
func _spawn_unit_for_building(building: RtsBuildingActor) -> RtsUnitActor:
	if building == null or building.is_dead():
		return null
	var unit_class: int = building.spawn_unit_kind
	if unit_class < 0:
		return null
	var team_id: int = building.get_team_id()

	# 朝对方阵营前方 spawn (左 → +x; 右 → -x)
	var spawn_offset: float = 28.0
	var spawn_pos: Vector2
	if team_id == 0:
		spawn_pos = building.position_2d + Vector2(spawn_offset, 0.0)
	else:
		spawn_pos = building.position_2d - Vector2(spawn_offset, 0.0)

	var unit := _spawn_unit(unit_class, team_id, spawn_pos)
	unit.stance = building.spawn_unit_stance
	_procedure.add_unit_to_team(unit, team_id)
	# Rally 规则 = "朝对方基地走 + 沿途遇敌打": set RtsAttackMoveActivity(enemy_ct)
	# + override=true. controller.tick (player_command 路径) 每 tick 把 actor._cached_target_id
	# 注入 attack_move.set_engagement_target — 但加 ENGAGEMENT_RADIUS_SQ gate (100px) +
	# 仅 enemy combat unit 触发(building/worker 不触发,免 detour 远端目标 / 杀农民). 路过
	# 敌方军事 unit 时切 attack child;敌死 cache 空了切回 MoveTo 续走 enemy_ct. 玩家想改 rally
	# 选中单位下 MoveUnitsCommand.
	var enemy_ct: RtsBuildingActor = _right_ct if team_id == 0 else _left_ct
	if enemy_ct != null and not enemy_ct.is_dead():
		var controller := _controllers.get(unit.get_id()) as RtsUnitController
		if controller != null:
			controller.set_activity_chain(RtsAttackMoveActivity.new(enemy_ct.position_2d), true)
	return unit


# ========== BuildPanel + Placement Mode ==========

func _on_building_selected(kind: String) -> void:
	_enter_placement_mode(kind)


## 进 mode 时缓存 stats + bbox 偏置 (mode 期间 kind 不变, 避免每帧 new StatBlock + 重算偶数偏置).
##
## **M0.5**: ghost size 切到走 stats.obstruction_size (Vector2 px) 而不是 footprint_size × cell_size,
## 让 ghost 跟最终 actor.obstruction_shape 占地完全对齐 (spec §M0.5 步骤 4).
## obstruction_offset = ZERO (M0.3 默认) 时, 跟旧 ghost 视觉 bit-identical;
## 非零时 ghost 跟着 obstruction_offset 偏移, 玩家看到的占地和最终生效占地一致.
func _enter_placement_mode(kind: String) -> void:
	_placement_kind = kind
	_placement_stats = RtsBuildingConfig.get_stats(kind)
	var cs: float = _battle_map.grid.cell_size
	var fp: Vector2i = _placement_stats.footprint_size
	_placement_ghost_offset = _bbox_center_offset(fp, cs)
	# M0.5 — ghost size = obstruction_size (Vector2 px); 跟 actor.obstruction_shape 占地一致
	_placement_ghost.size = _placement_stats.obstruction_size
	_placement_ghost.color = _GHOST_OK_COLOR
	_placement_ghost.visible = true
	print("[RtsFrontendDemo] enter placement mode kind=%s footprint=%s obstruction=%s" % [kind, fp, _placement_stats.obstruction_size])


func _exit_placement_mode(reason: String) -> void:
	if _placement_kind == _NO_PLACEMENT_KIND:
		return
	print("[RtsFrontendDemo] exit placement mode kind=%s reason=%s" % [_placement_kind, reason])
	_placement_kind = _NO_PLACEMENT_KIND
	_placement_stats = null
	_placement_ghost.visible = false


## 跟鼠标 + grid snap, validate 决定 tint. resources 由 _process 头部抓好后传入避免每帧 2 次拷贝.
##
## ghost bbox center 加上 obstruction_offset, 让 ghost 视觉中心落在最终 obstruction.center
## (= position_2d + obstruction_offset) 上, 跟 actor 落地后真实占地完全一致.
##
## hint label 实时显示 validate reason — 红色时让玩家知道为什么不能放
## (out_of_build_zone / cells_blocked / not_enough_gold 等).
func _update_placement_ghost(team_remaining: Dictionary) -> void:
	var grid := _battle_map.grid
	var mouse_world: Vector2 = _battle_map.get_local_mouse_position()
	var snapped_world: Vector2 = grid.coord_to_world(grid.world_to_coord(mouse_world))
	var bbox_center: Vector2 = snapped_world + _placement_ghost_offset + _placement_stats.obstruction_offset
	_placement_ghost.position = bbox_center - _placement_ghost.size * 0.5

	var check: Dictionary = _validate_player_placement(snapped_world, team_remaining)
	var ok: bool = check.get("success", false)
	_placement_ghost.color = _GHOST_OK_COLOR if ok else _GHOST_BAD_COLOR
	if _hud_hint_label != null:
		var pos_str: String = "(%d, %d)" % [int(snapped_world.x), int(snapped_world.y)]
		_hud_hint_label.text = (
			"[Placement: %s @ %s] left mouse to place | ESC / right mouse to cancel" % [_placement_kind, pos_str]
			if ok
			else "[Placement: %s @ %s] BLOCKED: %s" % [_placement_kind, pos_str, check.get("reason", "?")]
		)


## 与 RtsBuildingPlacement._compute_footprint_cells 同算法的 bbox 中心相对 cell 中心的偏置.
## 偶数 footprint 中心偏向 cell 边界 (half_lo > half_hi → 负向偏); 奇数为 0.
static func _bbox_center_offset(footprint_size: Vector2i, cell_size: float) -> Vector2:
	var half_x_lo: int = footprint_size.x / 2
	var half_x_hi: int = footprint_size.x - 1 - half_x_lo
	var half_y_lo: int = footprint_size.y / 2
	var half_y_hi: int = footprint_size.y - 1 - half_y_lo
	return Vector2(
		float(half_x_hi - half_x_lo) * cell_size * 0.5,
		float(half_y_hi - half_y_lo) * cell_size * 0.5,
	)


# ========== Camera2D + Minimap ==========

## InputMap 是 project-level setting, 不能在 .tscn 里设; demo _ready 头部调一次.
## 默认只绑 arrow keys, RTS 玩家更习惯 WASD.
static func _register_camera_keys() -> void:
	_add_action_key("ui_left", KEY_A)
	_add_action_key("ui_right", KEY_D)
	_add_action_key("ui_up", KEY_W)
	_add_action_key("ui_down", KEY_S)


static func _add_action_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).keycode == keycode:
			return
	var key := InputEventKey.new()
	key.keycode = keycode
	InputMap.action_add_event(action, key)


## minimap 点击 → camera 跳到 world_pos (Camera2D limit_* 自动 clamp).
func _on_minimap_clicked(world_pos: Vector2) -> void:
	if _camera == null:
		return
	_camera.position = world_pos


# ========== 战斗结束 ==========

func _on_battle_ended(result: String) -> void:
	if _finalized:
		return
	_finalized = true
	if _procedure != null:
		_procedure.finish()
	print("[RtsFrontendDemo] battle finished: %s in %d ticks" % [
		result if result != "" else (_procedure.get_result() if _procedure else "?"),
		_procedure.get_current_tick() if _procedure else -1,
	])
	_started = false
