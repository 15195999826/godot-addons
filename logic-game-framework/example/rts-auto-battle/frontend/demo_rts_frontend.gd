## RtsFrontendDemo - 4v4 RTS 自动战斗前端 demo
##
## 编辑器 F6 运行可视化版本: 8 个圆圈在 500×500 navmesh 上互相靠近 / 攻击 / 死亡消失。
## headless 也能跑 (但看不到画面), 此时按 procedure tick + 累计 dt 推进, 战斗结束自动 quit。
##
## 与 hex example/demo_frontend 的差异:
##   - 没有 3D camera / battle_animator / 投射物 / replay
##   - 单位用最简圆形 visualizer 染色 stub
##   - 不接 SimulationManager / web 桥接 (M0 范围外)
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _agents: Dictionary = {}        # actor.id → RtsNavAgent
var _ais: Dictionary = {}           # actor.id → RtsBasicAI
var _visualizers: Dictionary = {}   # actor.id → RtsUnitVisualizer

var _accumulated_ms: float = 0.0
var _started: bool = false


func _ready() -> void:
	GameWorld.init()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance

	await get_tree().physics_frame
	_world.set_navigation_region(_battle_map.navigation_region)

	# 4v4: 同 smoke 套路, 各队 2 melee + 2 ranged
	var roster: Array[Config.UnitClass] = [
		Config.UnitClass.MELEE,
		Config.UnitClass.MELEE,
		Config.UnitClass.RANGED,
		Config.UnitClass.RANGED,
	]
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []
	for i in range(roster.size()):
		left_actors.append(_spawn(roster[i], 0, RtsBattleMap.sample_team_spawn(0, i, roster.size())))
		right_actors.append(_spawn(roster[i], 1, RtsBattleMap.sample_team_spawn(1, i, roster.size())))

	_procedure = RtsAutoBattleProcedure.new(_world, left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"per_tick": _per_tick,
	})
	_procedure.start()
	_started = true


func _process(dt: float) -> void:
	if not _started or _procedure == null:
		return
	if _procedure.should_end():
		_finalize()
		return

	# 累计 dt 到 tick_interval, 每攒够一帧推一次
	_accumulated_ms += dt * 1000.0
	while _accumulated_ms >= TICK_INTERVAL_MS:
		_procedure.tick_once()
		_accumulated_ms -= TICK_INTERVAL_MS
		if _procedure.should_end():
			break

	# Sync 所有 visualizer
	for actor_id in _visualizers.keys():
		var vis := _visualizers[actor_id] as RtsUnitVisualizer
		if vis != null:
			vis.sync()


func _spawn(unit_class: Config.UnitClass, team_id: int, pos: Vector2) -> RtsCharacterActor:
	var actor := RtsCharacterActor.new(unit_class)
	actor.set_team_id(team_id)
	_world.add_actor(actor)
	actor.position_2d = pos

	var agent := RtsNavAgent.new()
	_battle_map.add_child(agent)
	agent.bind_actor(actor)
	_agents[actor.get_id()] = agent

	var ai := RtsBasicAI.new()
	ai.bind(actor, agent)
	_ais[actor.get_id()] = ai

	var vis := RtsUnitVisualizer.new()
	_battle_map.add_child(vis)
	vis.bind_actor(actor)
	_visualizers[actor.get_id()] = vis

	return actor


func _per_tick(_proc: RtsAutoBattleProcedure, dt: float) -> void:
	for actor in _world.get_alive_actors():
		if not (actor is RtsCharacterActor):
			continue
		var character := actor as RtsCharacterActor
		var ai := _ais.get(actor.get_id(), null) as RtsBasicAI
		var agent := _agents.get(actor.get_id(), null) as RtsNavAgent

		if ai != null:
			ai.tick(dt, _world)
		if agent != null:
			agent.tick(dt)
		character.tick_attack_cooldown(dt)

		if ai != null and ai.last_decision == "in_range" and character.can_attack():
			var target_id := character.current_target_id
			if target_id != "":
				var target := _world.get_actor(target_id) as RtsCharacterActor
				if target != null and not target.is_dead():
					RtsBasicAttackAction.execute(character, target, _world)
					character.reset_attack_cooldown()


func _finalize() -> void:
	_procedure.finish()
	print("[RtsFrontendDemo] battle finished: %s in %d ticks" % [
		_procedure.get_result(),
		_procedure.get_current_tick(),
	])
	_started = false
