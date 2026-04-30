## RTS auto-battle AI smoke (M0.5)
##
## 验证: 1v1 两个 melee 单位分别在 (50, 250) / (450, 250), AI 让两人互相靠近,
## 在 melee_attack_range (24 px) 范围内停下来不再前进, 不会无限对穿。
##
## 中央 (200..300, 200..300) 障碍 → 走纵向(各自走到 y≈200 一侧)绕过, 在中央上方相遇。
## 步进上限 ~12s, 期望 final 距离 ≤ attack_range × 1.05; 双方都进入 in_range 状态。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 20.0


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _agents: Dictionary = {}  # actor.id → RtsNavAgent
var _ais: Dictionary = {}     # actor.id → RtsBasicAI


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

	var left_actor := _spawn(Config.UnitClass.MELEE, 0, Vector2(50.0, 250.0))
	var right_actor := _spawn(Config.UnitClass.MELEE, 1, Vector2(450.0, 250.0))

	var left_team: Array[RtsBattleActor] = [left_actor]
	var right_team: Array[RtsBattleActor] = [right_actor]

	_procedure = RtsAutoBattleProcedure.new(_world, left_team, right_team, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"per_tick": _per_tick,
	})
	_procedure.start()

	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	var both_in_range_for_ticks: int = 0
	for i in range(max_ticks):
		_procedure.tick_once()
		if i % 4 == 0:
			await get_tree().physics_frame

		var left_ai := _ais[left_actor.get_id()] as RtsBasicAI
		var right_ai := _ais[right_actor.get_id()] as RtsBasicAI
		if left_ai.last_decision == "in_range" and right_ai.last_decision == "in_range":
			both_in_range_for_ticks += 1
			if both_in_range_for_ticks >= 5:  # 稳定 5 帧 = 250ms
				break
		else:
			both_in_range_for_ticks = 0

	_procedure.finish()

	# 主断言: 两单位最终在 attack range 内
	var final_dist := left_actor.position_2d.distance_to(right_actor.position_2d)
	var atk_range: float = (left_actor as RtsCharacterActor).attribute_set.attack_range
	if final_dist > atk_range * 1.10:
		_fail("units did not engage: final_dist=%.2f attack_range=%.2f (left at %s, right at %s)" % [
			final_dist, atk_range, left_actor.position_2d, right_actor.position_2d,
		])
		return

	# 双方都报告 in_range
	if (_ais[left_actor.get_id()] as RtsBasicAI).last_decision != "in_range":
		_fail("left ai not in_range: last=%s" % (_ais[left_actor.get_id()] as RtsBasicAI).last_decision)
		return
	if (_ais[right_actor.get_id()] as RtsBasicAI).last_decision != "in_range":
		_fail("right ai not in_range: last=%s" % (_ais[right_actor.get_id()] as RtsBasicAI).last_decision)
		return

	print("ai smoke: final_dist=%.2f atk_range=%.2f left=%s right=%s" % [
		final_dist, atk_range, left_actor.position_2d, right_actor.position_2d,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 1v1 melee engage at attack_range")
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
		var ai := _ais.get(actor.get_id(), null) as RtsBasicAI
		if ai != null:
			ai.tick(dt, _world)
		var agent := _agents.get(actor.get_id(), null) as RtsNavAgent
		if agent != null:
			agent.tick(dt)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
