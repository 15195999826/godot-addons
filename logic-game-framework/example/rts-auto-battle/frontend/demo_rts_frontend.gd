## RtsFrontendDemo - 城堡战争最小可玩 RTS demo (P2.7 Director + P2.8 飞行 / 防空 / 玩家命令)
##
## 编辑器 F6 运行: 双方各有 crystal_tower + archer_tower (anti-air) + 4 个 ground 单位 +
## 1 个 flying_scout; 玩家点左键在左方 build_zone 内放置 barracks; barracks 周期生产 melee
## 朝对方 crystal_tower 进军; 任一 crystal_tower 被毁判胜负。
##
## P2.8 改动:
##   - 起手布局: 双方 crystal_tower + archer_tower + 4 个起手 ground 单位 (2 melee + 2 ranged)
##   - 飞行单位: 各方 1 个 flying_scout 朝对方 ct 进军 (8px 上空渲染); 被对方 archer_tower 拦截
##   - 玩家命令: 左键在左方 build_zone (50,50)~(250,450) 内 → PlaceBuildingCommand barracks
##   - 资源 / build_zone HUD: 简易 Label, F6 时实时刷新
##
## P2.7 wire 顺序保持不变 (world / battle_map / director / world_view 的搭线; spawn → start → attach)。
##
## 关键不变量:
##   - demo 不读 actor.position_2d (那是 director 内部投影)
##   - flying_scout 用 RtsAttackMoveActivity override_strategy=true 让它直奔目标 (不被 strategy 替换)
##   - 玩家命令通过 procedure.enqueue_player_command + tick_stamp = current_tick 即时应用
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

# ========== 配置 ==========

const TICK_INTERVAL_MS: float = 50.0
const RNG_SEED: int = 0  # 0 = 随机种子 (每次 F6 不同战斗); 调试用可固定到任意正数

const STARTING_GOLD_LEFT: int = 300  # 够放 3 个 barracks (cost.gold=100 each)
const STARTING_WOOD_LEFT: int = 0    # M2.1 Phase A — wood 字段就位; Phase D 重平衡后启用
const RIGHT_CT_HP: float = 400.0  # 让战斗时间合理 (~20-30s)

# 双方阵地基线 x; 主战线在 y=200~280 之间.
const LEFT_BASE_X: float = 80.0
const RIGHT_BASE_X: float = 420.0

const LEFT_BUILD_ZONE: Rect2 = Rect2(50.0, 50.0, 200.0, 400.0)


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

	# 4. 起手 spawn: 双方 ct + archer_tower + ground 单位 + flying_scout
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []

	# 双方 crystal_tower (左方放置在 base x; 右方在 base x; 各方主基地)
	_left_ct = RtsBuildings.create_crystal_tower()
	_left_ct.set_team_id(0)
	_world.add_actor(_left_ct)
	_left_ct.position_2d = Vector2(LEFT_BASE_X, 350.0)
	left_actors.append(_left_ct)

	_right_ct = RtsBuildings.create_crystal_tower()
	_right_ct.set_team_id(1)
	_world.add_actor(_right_ct)
	_right_ct.position_2d = Vector2(RIGHT_BASE_X, 350.0)
	_right_ct.attribute_set.set_hp_base(RIGHT_CT_HP)  # 故意降 hp 让战斗有节奏
	right_actors.append(_right_ct)

	# 双方 archer_tower (P2.8 anti-air; mask=AIR — 只打飞行)
	var left_archer := RtsBuildings.create_archer_tower()
	left_archer.set_team_id(0)
	_world.add_actor(left_archer)
	left_archer.position_2d = Vector2(LEFT_BASE_X, 200.0)
	left_actors.append(left_archer)

	var right_archer := RtsBuildings.create_archer_tower()
	right_archer.set_team_id(1)
	_world.add_actor(right_archer)
	right_archer.position_2d = Vector2(RIGHT_BASE_X, 200.0)
	right_actors.append(right_archer)

	# 4 ground 单位 / 方 (2 melee + 2 ranged) — 与 Phase 1 demo 同样 spawn 模式
	var roster: Array[Config.UnitClass] = [
		Config.UnitClass.MELEE,
		Config.UnitClass.MELEE,
		Config.UnitClass.RANGED,
		Config.UnitClass.RANGED,
	]
	for i in range(roster.size()):
		var lp: Vector2 = RtsBattleMap.sample_team_spawn(0, i, roster.size())
		left_actors.append(_spawn_unit(roster[i], 0, lp))
		var rp: Vector2 = RtsBattleMap.sample_team_spawn(1, i, roster.size())
		right_actors.append(_spawn_unit(roster[i], 1, rp))

	# 1 个 flying_scout / 方 — 被对方 archer_tower 防空拦截
	var left_scout := _spawn_unit(Config.UnitClass.FLYING_SCOUT, 0, Vector2(LEFT_BASE_X + 30.0, 100.0))
	left_actors.append(left_scout)
	var right_scout := _spawn_unit(Config.UnitClass.FLYING_SCOUT, 1, Vector2(RIGHT_BASE_X - 30.0, 100.0))
	right_actors.append(right_scout)
	# 飞行单位 override-strategy 朝对方 ct 飞 — 让它们持续进攻不被 strategy 替换
	(_controllers[left_scout.get_id()] as RtsUnitController).set_activity_chain(
		RtsAttackMoveActivity.new(_right_ct.position_2d), true,
	)
	(_controllers[right_scout.get_id()] as RtsUnitController).set_activity_chain(
		RtsAttackMoveActivity.new(_left_ct.position_2d), true,
	)

	# 5. 启动战斗 (含 team_configs + player_command_queue + production spawner)
	# M2.1 Phase A — starting_resources 改 Dictionary[String, int] (gold + wood)
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
	_started = true

	# 7. HUD 简易 Label (resources / 操作提示)
	_setup_hud()


func _process(_delta: float) -> void:
	# HUD 刷新 — 不读 actor, 仅查 procedure 资源 / 状态
	# M2.1 Phase A — get_team_resources 返回 Dictionary[String, int]; HUD 拆 Gold / Wood 双显示
	if _hud_label != null and _procedure != null:
		var resources: Dictionary = _procedure.get_team_resources(0)
		var gold: int = int(resources.get("gold", 0))
		var wood: int = int(resources.get("wood", 0))
		_hud_label.text = "Gold: %d | Wood: %d  |  Click left mouse in left zone to place barracks (cost: gold 100)\nLeft CT HP: %.0f  Right CT HP: %.0f" % [
			gold, wood,
			_left_ct.get_attribute_set().get_raw().get_current_value("hp"),
			_right_ct.get_attribute_set().get_raw().get_current_value("hp"),
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
