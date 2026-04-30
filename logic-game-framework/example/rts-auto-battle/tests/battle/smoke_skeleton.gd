## RTS auto-battle skeleton smoke
##
## 渐进式 smoke, 每个 phase 升级:
##   M0.1: 验证目录树 + .tscn 加载
##   M0.2: 1v1 stub actor, procedure tick 1 次 + 杀左方判 right_win
##   M0.3: 4v4 RtsCharacterActor (各 2 melee + 2 ranged), 验证 attribute set 数值正确
##         + procedure tick 不崩 + cooldown 推进可观察
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")


func _ready() -> void:
	GameWorld.init()

	var world := GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance

	var left_team: Array[RtsBattleActor] = []
	var right_team: Array[RtsBattleActor] = []

	left_team.append(_spawn_unit(world, Config.UnitClass.MELEE, 0))
	left_team.append(_spawn_unit(world, Config.UnitClass.MELEE, 0))
	left_team.append(_spawn_unit(world, Config.UnitClass.RANGED, 0))
	left_team.append(_spawn_unit(world, Config.UnitClass.RANGED, 0))
	right_team.append(_spawn_unit(world, Config.UnitClass.MELEE, 1))
	right_team.append(_spawn_unit(world, Config.UnitClass.MELEE, 1))
	right_team.append(_spawn_unit(world, Config.UnitClass.RANGED, 1))
	right_team.append(_spawn_unit(world, Config.UnitClass.RANGED, 1))

	if world.get_actor_count() != 8:
		_fail("expected 8 actors, got %d" % world.get_actor_count())
		return

	# 抽查数值: melee 单位 hp=200/atk=25, ranged hp=120/atk=18
	var melee_actor := left_team[0] as RtsCharacterActor
	if melee_actor.attribute_set.max_hp != 200.0 or melee_actor.attribute_set.atk != 25.0 or melee_actor.attribute_set.attack_range != Config.MELEE_RANGE_THRESHOLD:
		_fail("melee stats wrong: hp=%.1f atk=%.1f range=%.1f" % [
			melee_actor.attribute_set.max_hp, melee_actor.attribute_set.atk, melee_actor.attribute_set.attack_range,
		])
		return
	var ranged_actor := left_team[2] as RtsCharacterActor
	if ranged_actor.attribute_set.max_hp != 120.0 or ranged_actor.attribute_set.atk != 18.0 or ranged_actor.attribute_set.attack_range != 120.0:
		_fail("ranged stats wrong: hp=%.1f atk=%.1f range=%.1f" % [
			ranged_actor.attribute_set.max_hp, ranged_actor.attribute_set.atk, ranged_actor.attribute_set.attack_range,
		])
		return

	# Cooldown 起手为 0, 推进 0.5s 仍 0(没攻击过, 不会涨)
	if melee_actor.attack_cooldown_remaining != 0.0:
		_fail("expected fresh actor cooldown=0, got %f" % melee_actor.attack_cooldown_remaining)
		return

	# Procedure 走一帧, 验证不崩
	var procedure := RtsAutoBattleProcedure.new(world, left_team, right_team, {
		"tick_interval_ms": 50.0,
		"per_tick": func(_proc: RtsAutoBattleProcedure, dt: float) -> void:
			# 模拟 attack: 给 melee_actor 起一个 cooldown 看会不会减
			if melee_actor.attack_cooldown_remaining == 0.0:
				melee_actor.reset_attack_cooldown()
			melee_actor.tick_attack_cooldown(dt)
	})
	procedure.start()
	procedure.tick_once()
	procedure.tick_once()

	# 双方仍活, 不应判结束
	if procedure.should_end():
		_fail("procedure ended too early; result=%s" % procedure.get_result())
		return

	# Cooldown 应该已推进(< 1 / attack_speed = 1s). 走了两帧 50ms, 应当是 1.0 - 0.05 - 0.05 = 0.9
	if not is_equal_approx(melee_actor.attack_cooldown_remaining, 0.9):
		_fail("cooldown tick wrong: expected ~0.9, got %f" % melee_actor.attack_cooldown_remaining)
		return

	# 杀掉左方所有, 下一 tick 判 right_win
	for actor in left_team:
		actor.mark_dead()
	procedure.tick_once()
	if not procedure.should_end():
		_fail("procedure should have ended after left team wiped")
		return
	if procedure.get_result() != "right_win":
		_fail("expected right_win, got '%s'" % procedure.get_result())
		return

	procedure.finish()
	world.end()
	GameWorld.destroy()

	print("SMOKE_TEST_RESULT: PASS - skeleton 4v4 ok, stats ok, cooldown tick ok, _check_battle_end ok")
	get_tree().quit(0)


func _spawn_unit(world: RtsWorldGameplayInstance, unit_class: Config.UnitClass, team_id: int) -> RtsCharacterActor:
	var actor := RtsCharacterActor.new(unit_class)
	actor.set_team_id(team_id)
	world.add_actor(actor)
	return actor


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
