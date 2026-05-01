## RtsFrontendDemo - 4v4 RTS 自动战斗前端 demo (P2.7 改写: 接 BattleDirector 流式 events)
##
## 编辑器 F6 运行: 8 个圆圈在 500×500 grid 战场上互相靠近 / 攻击 / 死亡; 60FPS 渲染插值给
## 30Hz logic tick (D3-A) 平滑过渡, 不再有 sync() 拉模式 polling.
##
## P2.7 wire 顺序:
##   1. world / battle_map / director / world_view 创建
##   2. world_view.bind(world, director)         — 起手监听 actor_added, hydrate (此时 0 actor)
##   3. spawn 4v4 actors                         — world.add_actor 触发 actor_added → WorldView 创建 visualizer
##   4. world.start_rts_battle(...) → procedure
##   5. director.attach(world, procedure)        — 起手 _seed_render_state + broadcast 给 visualizer
##   6. (director._process 自动跑 sim + 推 visualizer 渲染状态; demo 无需 _process 逻辑)
##
## 关键不变量:
##   - demo 不读 actor.position_2d (那是 director 内部投影; demo 控制 wire, 不接 sim 状态)
##   - demo 仍持 _agents / _controllers (logic 层 runtime, 与 visualizer 无关; P2.2 movement 拆)
##   - 战斗结束 director.battle_ended 触发 _finalize → procedure.finish + print 结果
##
## 与 hex demo_frontend 的差异 (Phase 1 既有 + P2.7 持续):
##   - 没有 3D camera / battle_animator / 投射物 / replay (M1 范围内简化 stub)
##   - frontend 实时跑 (sim + render 同 _process), 不像 hex 的 "跑完战斗 → animator 离线播放"
##   - 不接 SimulationManager / web 桥接 (M0 范围外)
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")


# ========== 节点引用 ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null

var _director: RtsBattleDirector = null
var _world_view: RtsWorldView = null

var _agents: Dictionary = {}        # actor.id → RtsNavAgent (logic 层)
var _controllers: Dictionary = {}   # actor.id → RtsUnitController (logic 层)

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
	_world_view.bind(_world, _director)  # 必须在 spawn 前监听 actor_added

	# 4. Spawn 4v4 (各队 2 melee + 2 ranged) — 触发 actor_added → WorldView 自动创建 visualizer
	var roster: Array[Config.UnitClass] = [
		Config.UnitClass.MELEE,
		Config.UnitClass.MELEE,
		Config.UnitClass.RANGED,
		Config.UnitClass.RANGED,
	]
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []
	for i in range(roster.size()):
		left_actors.append(_spawn_unit(roster[i], 0, RtsBattleMap.sample_team_spawn(0, i, roster.size())))
		right_actors.append(_spawn_unit(roster[i], 1, RtsBattleMap.sample_team_spawn(1, i, roster.size())))

	# 5. 启动战斗
	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"unit_runtimes": _controllers,
	})

	# 6. Director attach (procedure 已存在, 接管 event_sink + broadcast 起手 state 给 visualizer)
	_director.attach(_world, _procedure)
	_started = true


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
