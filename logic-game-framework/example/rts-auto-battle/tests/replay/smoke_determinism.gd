## RTS light determinism smoke (P1.7)
##
## 决策来源:
##   - phase-1-foundation.md P1.7 (Light determinism)
##   - architecture-baseline.md §6 (RtsRecording.world_snapshot.rng_seed)
##
## 验证: 同 seed 跑 2 次 4v4 战斗 → 同 winner + 同 total_ticks ± 1 (容许 1 帧漂移因 floating
## point order, 但战略结果不变)。
##
## **不验证 bit-identical event_timeline** — 那个等 Phase 2 P2.6+P2.7 (player_commands 接入 + 流式
## recorder 落地) 才完整。
##
## 单 procedure 运行内部不调 randf/randi (M0 → P1.6 都没引入随机), 所以本 smoke 实际是
## "无随机源条件下 procedure 是否决定性" 的回归测试 — Phase 2 加 random damage / spawn jitter 时,
## 此 smoke 能立即捕捉脱离 RtsRng 的 randf 调用。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_SECONDS: float = 60.0
const FIXED_SEED: int = 12345

## 容许的 tick 漂移
const TICK_TOLERANCE: int = 1


func _ready() -> void:
	# Run 1
	var run1 := _run_battle()
	if run1.is_empty():
		_fail("run 1 did not produce a result")
		return

	# Run 2 — 重新 init GameWorld + 重建 world 实例 + 同 seed
	var run2 := _run_battle()
	if run2.is_empty():
		_fail("run 2 did not produce a result")
		return

	var winner1: String = run1["winner"]
	var winner2: String = run2["winner"]
	var ticks1: int = run1["ticks"]
	var ticks2: int = run2["ticks"]

	if winner1 != winner2:
		_fail("determinism violated: winner differs (run1=%s, run2=%s)" % [winner1, winner2])
		return

	var tick_diff: int = absi(ticks1 - ticks2)
	if tick_diff > TICK_TOLERANCE:
		_fail("determinism violated: tick count differs by %d (run1=%d, run2=%d, tolerance=%d)" % [
			tick_diff, ticks1, ticks2, TICK_TOLERANCE,
		])
		return

	print("determinism smoke: seed=%d, run1=(winner=%s, ticks=%d), run2=(winner=%s, ticks=%d), tick_diff=%d" % [
		FIXED_SEED, winner1, ticks1, winner2, ticks2, tick_diff,
	])

	print("SMOKE_TEST_RESULT: PASS - same seed produces same winner + ticks ± %d" % TICK_TOLERANCE)
	get_tree().quit(0)


# ========== 内部 ==========

func _run_battle() -> Dictionary:
	GameWorld.init()

	var battle_map := RtsBattleMap.new()
	add_child(battle_map)

	var world := GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance

	world.set_grid(battle_map.grid)

	# 4v4 同 smoke_rts_auto_battle 的 roster: 2 melee + 2 ranged
	var roster: Array[Config.UnitClass] = [
		Config.UnitClass.MELEE,
		Config.UnitClass.MELEE,
		Config.UnitClass.RANGED,
		Config.UnitClass.RANGED,
	]
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []
	var controllers: Dictionary = {}

	for i in range(roster.size()):
		var left_pos := RtsBattleMap.sample_team_spawn(0, i, roster.size())
		var right_pos := RtsBattleMap.sample_team_spawn(1, i, roster.size())
		left_actors.append(_spawn_with_controller(world, battle_map, roster[i], 0, left_pos, controllers))
		right_actors.append(_spawn_with_controller(world, battle_map, roster[i], 1, right_pos, controllers))

	var procedure := world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": controllers,
		"rng_seed": FIXED_SEED,
	})

	var max_ticks: int = int(MAX_SECONDS * 1000.0 / TICK_INTERVAL_MS)
	for i in range(max_ticks):
		procedure.tick_once()
		if procedure.should_end():
			break

	procedure.finish()

	var result := procedure.get_result()
	var ticks := procedure.get_current_tick()

	# 清理供下一轮用 — 卸载场景节点 + 销毁 GameWorld
	battle_map.queue_free()
	world.end()
	GameWorld.destroy()
	# queue_free 异步生效, 但下轮 _run_battle 会重新 GameWorld.init + 创建新 RtsBattleMap, 所以
	# 旧节点不会污染。

	if result == "":
		return {}
	return { "winner": result, "ticks": ticks }


func _spawn_with_controller(
	world: RtsWorldGameplayInstance,
	battle_map: RtsBattleMap,
	unit_class: Config.UnitClass,
	team_id: int,
	pos: Vector2,
	controllers: Dictionary,
) -> RtsUnitActor:
	var actor := RtsUnitActor.new(unit_class)
	actor.set_team_id(team_id)
	world.add_actor(actor)
	actor.position_2d = pos

	var agent := RtsNavAgent.new()
	battle_map.add_child(agent)
	agent.bind_actor(actor, battle_map.grid)

	var strategy := RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(actor, agent, strategy)
	controllers[actor.get_id()] = controller

	return actor


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
