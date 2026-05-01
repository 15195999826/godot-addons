## RTS auto-battle skeleton smoke
##
## 渐进式 smoke, 每个 phase 升级:
##   M0.1: 验证目录树 + .tscn 加载
##   M0.2: 1v1 stub actor, procedure tick 1 次 + 杀左方判 right_win
##   M0.3: 4v4 RtsUnitActor (各 2 melee + 2 ranged), 验证 attribute set 数值正确
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
	var melee_actor := left_team[0] as RtsUnitActor
	if melee_actor.attribute_set.max_hp != 200.0 or melee_actor.attribute_set.atk != 25.0 or melee_actor.attribute_set.attack_range != Config.MELEE_RANGE_THRESHOLD:
		_fail("melee stats wrong: hp=%.1f atk=%.1f range=%.1f" % [
			melee_actor.attribute_set.max_hp, melee_actor.attribute_set.atk, melee_actor.attribute_set.attack_range,
		])
		return
	var ranged_actor := left_team[2] as RtsUnitActor
	if ranged_actor.attribute_set.max_hp != 120.0 or ranged_actor.attribute_set.atk != 18.0 or ranged_actor.attribute_set.attack_range != 120.0:
		_fail("ranged stats wrong: hp=%.1f atk=%.1f range=%.1f" % [
			ranged_actor.attribute_set.max_hp, ranged_actor.attribute_set.atk, ranged_actor.attribute_set.attack_range,
		])
		return

	# 起手不在 cooldown(P1.6 走 tag-duration, has_tag 应 false)
	if melee_actor.is_attack_on_cooldown():
		_fail("expected fresh actor not on cooldown, got tag set")
		return

	# Procedure 走一帧, 验证不崩 (P1.3: 不传 per_tick, 内化主循环自动 tick cooldown)
	# 模拟 attack: 起手给 melee_actor 上 cooldown, 让内化主循环 tick 它(走 tag-duration)
	# 必须在 procedure 启动后再上 cooldown — start_rts_battle 调 procedure.start() 前 ability_set
	# 还没注册 tick context, 直接调 add_auto_duration_tag 也行但 logic_time 起点是 0(等同 cooldown
	# 立即起 expiresAt = 1000ms)。
	var procedure := world.start_rts_battle(left_team, right_team, {
		"tick_interval_ms": 50.0,
	})
	melee_actor.start_attack_cooldown()
	procedure.tick_once()
	procedure.tick_once()

	# 双方仍活, 不应判结束
	if procedure.should_end():
		_fail("procedure ended too early; result=%s" % procedure.get_result())
		return

	# Cooldown 走了 100ms, melee 周期 1000ms, 应该仍 active(还差 900ms 才过期)
	if not melee_actor.is_attack_on_cooldown():
		_fail("expected melee_actor still on cooldown after 100ms, but tag has expired")
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


func _spawn_unit(world: RtsWorldGameplayInstance, unit_class: Config.UnitClass, team_id: int) -> RtsUnitActor:
	var actor := RtsUnitActor.new(unit_class)
	actor.set_team_id(team_id)
	world.add_actor(actor)
	return actor


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
