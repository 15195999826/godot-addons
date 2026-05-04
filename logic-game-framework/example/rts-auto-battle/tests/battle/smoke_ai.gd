## RTS auto-battle AI smoke (M0.5 → P1.5 controller refactor)
##
## 验证: 1v1 两个 melee 单位分别在 (50, 250) / (450, 250), AI 让两人互相靠近,
## 在 melee_attack_range (24 px) 范围内停下来不再前进, 不会无限对穿。
##
## 中央 (200..300, 200..300) 障碍 → 走纵向(各自走到 y≈200 一侧)绕过, 在中央上方相遇。
## 步进上限 ~20s, 期望 final 距离 ≤ attack_range × 1.10; 双方都进入 attack 决策。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 20.0


var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _controllers: Dictionary = {}   # actor.id → RtsUnitController


func _ready() -> void:
	GameWorld.init()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance

	_world.set_grid(_battle_map.grid)

	var left_actor := _spawn(Config.UnitClass.MELEE, 0, Vector2(50.0, 250.0))
	var right_actor := _spawn(Config.UnitClass.MELEE, 1, Vector2(450.0, 250.0))

	var left_team: Array[RtsBattleActor] = [left_actor]
	var right_team: Array[RtsBattleActor] = [right_actor]

	_procedure = _world.start_rts_battle(left_team, right_team, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
	})

	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	var both_attacking_for_ticks: int = 0
	for i in range(max_ticks):
		_procedure.tick_once()

		var left_ctrl := _controllers[left_actor.get_id()] as RtsUnitController
		var right_ctrl := _controllers[right_actor.get_id()] as RtsUnitController
		if left_ctrl.wants_to_attack() and right_ctrl.wants_to_attack():
			both_attacking_for_ticks += 1
			if both_attacking_for_ticks >= 5:  # 稳定 5 帧 = 250ms
				break
		else:
			both_attacking_for_ticks = 0

	_procedure.finish()

	# 主断言: 两单位最终在 attack range 内
	var final_dist := left_actor.position_2d.distance_to(right_actor.position_2d)
	var atk_range: float = (left_actor as RtsUnitActor).attribute_set.attack_range
	if final_dist > atk_range * 1.10:
		_fail("units did not engage: final_dist=%.2f attack_range=%.2f (left at %s, right at %s)" % [
			final_dist, atk_range, left_actor.position_2d, right_actor.position_2d,
		])
		return

	# 双方都报告 attack 决策
	var left_intent: String = (_controllers[left_actor.get_id()] as RtsUnitController).get_intent_action()
	var right_intent: String = (_controllers[right_actor.get_id()] as RtsUnitController).get_intent_action()
	if left_intent != "attack":
		_fail("left controller not attacking: intent=%s" % left_intent)
		return
	if right_intent != "attack":
		_fail("right controller not attacking: intent=%s" % right_intent)
		return

	print("ai smoke: final_dist=%.2f atk_range=%.2f left=%s right=%s" % [
		final_dist, atk_range, left_actor.position_2d, right_actor.position_2d,
	])

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 1v1 melee engage at attack_range")
	get_tree().quit(0)


func _spawn(unit_class: Config.UnitClass, team_id: int, pos: Vector2) -> RtsUnitActor:
	var actor := RtsUnitActor.new(unit_class)
	actor.set_team_id(team_id)
	_world.add_actor(actor)
	actor.position_2d = pos

	var motion_component := RtsMotionComponent.attach_default(actor, _world)

	var strategy := RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(actor, motion_component, strategy)
	_controllers[actor.get_id()] = controller

	return actor


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
