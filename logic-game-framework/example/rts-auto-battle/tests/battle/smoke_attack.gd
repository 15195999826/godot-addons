## RTS auto-battle attack smoke (M0.6)
##
## 验证: 1v1 melee, 左方 hp 200, 右方 hp 大幅减低(30 hp), AI 让两人接敌, 接敌后左方
## 在几次 attack 内击杀右方; procedure 自动报 left_win, actor_died event 入 logger。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 30.0


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _logger: RtsBattleLogger = null
var _agents: Dictionary = {}
var _ais: Dictionary = {}


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

	_logger = RtsBattleLogger.new()

	# 左方满血; 右方 hp=30 给 melee 一两下就死
	var left_actor := _spawn(Config.UnitClass.MELEE, 0, Vector2(50.0, 250.0))
	var right_actor := _spawn(Config.UnitClass.MELEE, 1, Vector2(450.0, 250.0))
	right_actor.attribute_set.set_max_hp_base(40.0)
	right_actor.attribute_set.set_hp_base(30.0)

	var left_team: Array[RtsBattleActor] = [left_actor]
	var right_team: Array[RtsBattleActor] = [right_actor]

	_procedure = RtsAutoBattleProcedure.new(_world, left_team, right_team, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"per_tick": _per_tick,
	})
	_procedure.start()

	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for i in range(max_ticks):
		_procedure.tick_once()
		if i % 4 == 0:
			await get_tree().physics_frame
		if _procedure.should_end():
			break

	_procedure.finish()

	# 主断言: procedure 报 left_win
	if not _procedure.should_end():
		_fail("battle did not end within %d seconds" % MAX_SECONDS)
		return
	if _procedure.get_result() != "left_win":
		_fail("expected left_win, got '%s'" % _procedure.get_result())
		return

	# 死亡 event 数 ≥ 1
	if _logger.get_death_count() < 1:
		_fail("expected ≥ 1 death event, got %d" % _logger.get_death_count())
		return

	# 至少 1 次 attack 发生(ranged 不会有, melee 必然有)
	if _logger.get_attack_count() < 1:
		_fail("expected ≥ 1 attack event, got 0")
		return

	# 攻击距离断言: melee unit 的所有 attack 距离都应 <= melee_range × 1.05
	var melee_dists := _logger.get_attack_distances_for_class(int(Config.UnitClass.MELEE))
	for d in melee_dists:
		if d > Config.MELEE_RANGE_THRESHOLD * 1.05:
			_fail("melee attack at distance %.2f exceeds threshold %.2f" % [
				d, Config.MELEE_RANGE_THRESHOLD * 1.05,
			])
			return

	print("attack smoke: result=%s ticks=%d attacks=%d deaths=%d melee_max_dist=%.2f" % [
		_procedure.get_result(),
		_procedure.get_current_tick(),
		_logger.get_attack_count(),
		_logger.get_death_count(),
		_max_in(melee_dists),
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 1v1 melee left wins by killing right")
	get_tree().quit(0)


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

		# Attack: AI 报 in_range + cooldown 到 + target 还活着
		if ai != null and ai.last_decision == "in_range" and character.can_attack():
			var target_id := character.current_target_id
			if target_id != "":
				var target := _world.get_actor(target_id) as RtsCharacterActor
				if target != null and not target.is_dead():
					RtsBasicAttackAction.execute(character, target, _world)
					character.reset_attack_cooldown()

	# 在 procedure flush 前把这帧累计的事件 mirror 到 logger
	_logger.ingest_frame_events(GameWorld.event_collector.collect())


func _max_in(arr: Array[float]) -> float:
	var m: float = -INF
	for v in arr:
		if v > m:
			m = v
	return m if m != -INF else 0.0


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
