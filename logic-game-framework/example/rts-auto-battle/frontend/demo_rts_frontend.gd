## RtsFrontendDemo - 经济闭环 + AI vs AI RTS demo (M2.2 — AI 对手 落地)
##
## 编辑器 F6 运行: 双方各 5 worker + 1 crystal_tower + 2 gold node + 2 wood node;
## 双方都 attach RtsComputerPlayer (E9 — demo F6 启用方式: AI vs AI); 各自 worker 自动
## harvest → 攒 80g + 50w → AI 在 ct 偏移点 (E4) 放 barracks → barracks 周期生产 melee →
## ≥3 melee 后 attack-move 攻敌方 ct (only-once); 任一 ct 被毁判胜负。
##
## 玩家鼠标左键 click 仍可在左方 build_zone 内 enqueue PlaceBuildingCommand barracks
## (M2.2 不做 override AI 模式 — 双 barracks cap=1 玩家命令会被 AI 命令竞争; 通常 AI 在
## tick 30 抢先放下, 玩家命令失败 reason=cells_occupied / 资源不足 等)。
##
## Phase D D19 改动 (相比 P2.8 城堡战争 demo):
##   - 删除起手 archer_tower / 4 ground / 1 flying_scout (Phase D 主题切到经济闭环, 不验防空 / 4v4)
##   - 起手双方各 5 worker (走 RtsHarvestStrategy 自动 harvest 中立 ResourceNode → drop 到己方 ct)
##   - 起手中立 (team_id=-1) ResourceNode: 双方各 2 gold + 2 wood (4 node × 2 侧 = 8 node 共)
##   - starting_resources {gold: 100, wood: 100} (D17): 起手能造 1 barracks (80g+50w) 之后必须 harvest 补
##   - HUD 提示文字更新 (cost gold 80 + wood 50)
##
## 注意: ResourceNode 当前没有 RtsResourceNodeVisualizer (WorldView._spawn_visualizer 仅对
## RtsUnitActor / RtsBuildingActor 创 visualizer); F6 时 node 不可见, 视觉上 worker 走到 (220, ?)
## 周围 harvest 然后回 ct, HUD 资源数字增长。后续若需可视 node, 可加 RtsResourceNodeVisualizer。
##
## 关键不变量:
##   - demo 不读 actor 状态 (position / hp 等都是 director 内部投影; HUD 走 director.get_render_state)
##   - 玩家命令通过 procedure.enqueue_player_command + tick_stamp = current_tick 即时应用
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

# ========== 配置 ==========

const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 0  # 0 = 随机种子 (每次 F6 不同战斗); 调试用可固定到任意正数

# Phase D D17 finalized — 起手能造 1 barracks (80g+50w) 之后必须 worker harvest 补
const STARTING_GOLD_LEFT: int = 100
const STARTING_WOOD_LEFT: int = 100

# 双方阵地基线 x; 主战线在 y=200~280 之间.
const LEFT_BASE_X: float = 80.0
const RIGHT_BASE_X: float = 420.0

const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 200.0, 400.0)

# Phase D D19 worker / node 起手布局
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


# ========== 节点引用 ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null

var _director: RtsBattleDirector = null
var _world_view: RtsWorldView = null

var _agents: Dictionary = {}        # actor.id → RtsNavAgent (logic 层)
var _controllers: Dictionary = {}   # actor.id → RtsUnitController (logic 层)

# 关键 actor 引用 (HUD / 玩家命令上下文)
var _left_ct: RtsBuildingActor = null
var _right_ct: RtsBuildingActor = null
var _hud_label: Label = null

var _started: bool = false
var _finalized: bool = false


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

	# 3. Director + WorldView (P2.7)
	_director = RtsBattleDirector.new()
	_director.name = "BattleDirector"
	add_child(_director)
	_director.battle_ended.connect(_on_battle_ended)

	_world_view = RtsWorldView.new()
	_world_view.name = "WorldView"
	_battle_map.add_child(_world_view)
	_world_view.bind(_world, _director)

	# 4. 起手 spawn: 双方 ct + 5 worker + 中立 4 node (Phase D D19)
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	# 双方 crystal_tower (主基地 + drop-off)
	_left_ct = RtsBuildings.create_crystal_tower()
	_left_ct.set_team_id(0)
	_world.add_actor(_left_ct)
	_left_ct.position_2d = LEFT_CT_POS
	left_actors.append(_left_ct)

	_right_ct = RtsBuildings.create_crystal_tower()
	_right_ct.set_team_id(1)
	_world.add_actor(_right_ct)
	_right_ct.position_2d = RIGHT_CT_POS
	right_actors.append(_right_ct)

	# 双方各 5 worker
	for i in range(NUM_WORKERS_PER_TEAM):
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
	# Phase D D17 — starting_resources {gold: 100, wood: 100}
	var left_cfg := RtsTeamConfig.create(
		0, "human", {"gold": STARTING_GOLD_LEFT, "wood": STARTING_WOOD_LEFT},
		LEFT_BUILD_ZONE,
	)
	var right_cfg := RtsTeamConfig.create(1, "ai", {}, Rect2())
	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"unit_spawner": Callable(self, "_spawn_unit_for_building"),
		"team_configs": { 0: left_cfg, 1: right_cfg },
		"rng_seed": RNG_SEED,
	})

	# 6. Director attach (procedure 已存在, 接管 event_sink + broadcast 起手 state)
	_director.attach(_world, _procedure)

	# 7. M2.2 — 双方都 attach AI (E9 — demo F6 启用方式: AI vs AI)
	#    procedure 默认不创建 AI (E10), 由 demo 显式 attach; 玩家鼠标 click 仍可 enqueue
	#    PlaceBuildingCommand (左方 build_zone 内), 不强制 override AI 决策 (M2.2 不做 override 模式)。
	_procedure.attach_computer_player(0)
	_procedure.attach_computer_player(1)

	_started = true

	# 8. HUD 简易 Label (resources / 操作提示)
	_setup_hud()


func _process(_delta: float) -> void:
	# HUD 刷新 — 不读 actor 状态, 资源走 procedure / hp 走 director.get_render_state.
	# Phase D HUD 文字更新 cost 提示 (gold 80 + wood 50).
	if _hud_label != null and _procedure != null and _director != null:
		var resources: Dictionary = _procedure.get_team_resources(0)
		var gold: int = int(resources.get("gold", 0))
		var wood: int = int(resources.get("wood", 0))
		var left_state: Dictionary = _director.get_render_state(_left_ct.get_id()) if _left_ct != null else {}
		var right_state: Dictionary = _director.get_render_state(_right_ct.get_id()) if _right_ct != null else {}
		var left_hp: float = float(left_state.get("hp", 0.0))
		var right_hp: float = float(right_state.get("hp", 0.0))
		_hud_label.text = "Gold: %d | Wood: %d  |  Click left mouse in left zone to place barracks (cost: gold 80 + wood 50)\nLeft CT HP: %.0f  Right CT HP: %.0f" % [
			gold, wood, left_hp, right_hp,
		]


# ========== 玩家输入 (鼠标点击放兵营) ==========

func _unhandled_input(event: InputEvent) -> void:
	if not _started or _finalized:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var pos: Vector2 = mb.position
	# 落在 build_zone 外 → 仅打 console (UI 反馈留给 PlaceBuildingCommand 失败 reason)
	if not LEFT_BUILD_ZONE.has_point(pos):
		print("[RtsFrontendDemo] click outside build_zone, pos=%s" % str(pos))
		return
	# tick_stamp = 当前 tick → 立即应用 (tick_once step 1.5)
	var current_tick: int = _procedure.get_current_tick() if _procedure != null else 0
	_procedure.enqueue_player_command(RtsPlaceBuildingCommand.new(
		current_tick, 0, RtsBuildingConfig.KIND_BARRACKS, pos,
	))
	print("[RtsFrontendDemo] enqueued PlaceBuildingCommand barracks @ %s tick_stamp=%d" % [
		str(pos), current_tick,
	])


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
	# 不 set_activity_chain — strategy.decide / AutoTargetSystem 自然驱动 (单位选最近 enemy ct)
	return unit


# ========== HUD ==========

func _setup_hud() -> void:
	_hud_label = Label.new()
	_hud_label.name = "Hud"
	_hud_label.position = Vector2(10.0, 10.0)
	_hud_label.add_theme_font_size_override("font_size", 14)
	_hud_label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	add_child(_hud_label)


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
