## RTS bit-identical replay smoke (P2.7 — AC10 实现)
##
## 目标 (Phase 2 acceptance AC10): 同 seed + 同 player_commands 跑 2 次 → 产出 bit-identical
## event_timeline + bit-identical player_commands_log.
##
## 与 smoke_determinism 的区别:
##   - smoke_determinism (P1.7): 仅验证 winner + ticks ± 1 (light determinism, 战略层)
##   - smoke_replay_bit_identical (P2.7): 验证 timeline events 数量 + 每个 event 的 kind / damage /
##     distance 完全 bit-equal; 验证 player_commands_log 长度 + entry-by-entry 结果一致
##
## 实现要点:
##   - 两次跑前调 IdGenerator.reset_id_counter() 让 actor_id 一致 (否则 source/target id 跨两跑不等)
##   - 跑 short scenario (固定 100 ticks 截断, 不依赖战斗自然结束) 让对比可控
##   - player_commands: tick 5 放 left barracks; tick 10 放 right barracks (双 ct + 兵营; 对称)
##   - 跑完用 procedure.finish 拿 record dict, 比对 record["timeline"] + record["player_commands"]
##
## 决策来源:
##   - phase-2-core-systems.md AC10 (bit-identical replay)
##   - phase-2-core-systems.md P2.6 (player_commands_log 字段铺垫)
##   - phase-2-core-systems.md P2.7 (BattleRecorder 接入 player_commands; 见 procedure.finish 注释)
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 50.0
const MAX_TICKS: int = 100
const FIXED_SEED: int = 42


func _ready() -> void:
	# Run 1
	IdGenerator.reset_id_counter()
	var run1 := _run_scenario()
	if run1.is_empty():
		_fail("run 1 failed to produce a record")
		return

	# Run 2 — id 计数器重置, 同 seed + 同 commands → 应得同样结果
	IdGenerator.reset_id_counter()
	var run2 := _run_scenario()
	if run2.is_empty():
		_fail("run 2 failed to produce a record")
		return

	# === 1. 比对 player_commands ===
	var pc1: Array = run1["player_commands"]
	var pc2: Array = run2["player_commands"]
	if pc1.size() != pc2.size():
		_fail("player_commands size mismatch: run1=%d run2=%d" % [pc1.size(), pc2.size()])
		return
	for i in range(pc1.size()):
		var e1: Dictionary = pc1[i] as Dictionary
		var e2: Dictionary = pc2[i] as Dictionary
		if not _dict_equal(e1, e2):
			_fail("player_commands[%d] mismatch:\n  run1=%s\n  run2=%s" % [i, e1, e2])
			return

	# === 2. 比对 timeline events ===
	var tl1: Array = run1["timeline"] as Array
	var tl2: Array = run2["timeline"] as Array
	if tl1.size() != tl2.size():
		_fail("timeline frame count mismatch: run1=%d run2=%d" % [tl1.size(), tl2.size()])
		return

	var total_events: int = 0
	for i in range(tl1.size()):
		var f1: Dictionary = tl1[i] as Dictionary
		var f2: Dictionary = tl2[i] as Dictionary
		var frame1: int = int(f1.get("frame", -1))
		var frame2: int = int(f2.get("frame", -1))
		if frame1 != frame2:
			_fail("frame[%d] number mismatch: %d vs %d" % [i, frame1, frame2])
			return
		var ev1: Array = f1.get("events", []) as Array
		var ev2: Array = f2.get("events", []) as Array
		if ev1.size() != ev2.size():
			_fail("frame %d events size mismatch: run1=%d run2=%d" % [frame1, ev1.size(), ev2.size()])
			return
		total_events += ev1.size()
		for j in range(ev1.size()):
			var event1: Dictionary = ev1[j] as Dictionary
			var event2: Dictionary = ev2[j] as Dictionary
			if not _dict_equal(event1, event2):
				_fail("frame %d event[%d] mismatch:\n  run1=%s\n  run2=%s" % [frame1, j, event1, event2])
				return

	# === 3. 比对 rng_seed (sanity) ===
	if int(run1.get("rng_seed", -1)) != int(run2.get("rng_seed", -2)):
		_fail("rng_seed mismatch: run1=%d run2=%d" % [run1.get("rng_seed", -1), run2.get("rng_seed", -2)])
		return

	print("bit-identical replay smoke: seed=%d, commands=%d, frames=%d, events=%d" % [
		FIXED_SEED, pc1.size(), tl1.size(), total_events,
	])
	print("SMOKE_TEST_RESULT: PASS - same seed + same player_commands produce bit-identical event_timeline + commands_log")
	get_tree().quit(0)


# ========== 内部 ==========

## 跑一次 scenario (双队 4v4 + 双 ct + tick 5/10 各放 barracks), 返回 procedure.finish() 的 record dict.
func _run_scenario() -> Dictionary:
	GameWorld.init()

	var battle_map := RtsBattleMap.new()
	add_child(battle_map)

	var world := GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	world.set_grid(battle_map.grid)

	# 4v4 同 smoke_determinism roster
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
		left_actors.append(_spawn_unit(world, battle_map, roster[i], 0,
			RtsBattleMap.sample_team_spawn(0, i, roster.size()), controllers))
		right_actors.append(_spawn_unit(world, battle_map, roster[i], 1,
			RtsBattleMap.sample_team_spawn(1, i, roster.size()), controllers))

	# 玩家命令队列: tick 5 放 left barracks, tick 10 放 right barracks
	var queue := RtsPlayerCommandQueue.new()
	var cmd_left := RtsPlaceBuildingCommand.new(
		5,
		0,
		RtsBuildingConfig.KIND_BARRACKS,
		Vector2(150.0, 230.0),
	)
	queue.enqueue(cmd_left)
	var cmd_right := RtsPlaceBuildingCommand.new(
		10,
		1,
		RtsBuildingConfig.KIND_BARRACKS,
		Vector2(350.0, 270.0),
	)
	queue.enqueue(cmd_right)

	# Team configs: build_zone + 起手资源 + crystal_tower_id (战斗中放置, 此 smoke 不需要绑 ct_id)
	# M2.1 Phase D — starting_resources 给足 (双方各放 1 barracks 80g+50w; 500/500 留充裕 buffer)
	var team_configs: Dictionary[int, RtsTeamConfig] = {
		0: RtsTeamConfig.create(0, "left_faction", {"gold": 500, "wood": 500}, Rect2(0, 0, 250, 500)),
		1: RtsTeamConfig.create(1, "right_faction", {"gold": 500, "wood": 500}, Rect2(250, 0, 250, 500)),
	}

	var procedure := world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": controllers,
		"rng_seed": FIXED_SEED,
		"team_configs": team_configs,
		"player_command_queue": queue,
	})

	# 跑固定 MAX_TICKS (不依赖自然胜负, 让两次跑都跑满 100 帧)
	for _i in range(MAX_TICKS):
		procedure.tick_once()
		# 注意: 不调 should_end() 提前 break — 我们想跑满确定 tick 数, 让 timeline 长度也确定

	var record: Dictionary = procedure.finish()

	# 清理本轮节点 + GameWorld 实例 (不影响 IdGenerator 计数器, 由调方 reset)
	battle_map.queue_free()
	world.end()
	GameWorld.destroy()

	return record


func _spawn_unit(
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


## Dict deep equal — 递归比对.
##
## 不能直接用 ==:
##   - Dictionary == 在 Godot 4 走值比较, 但嵌套 Object 子项走引用 (HexCoord 实例不同 → false)
## 不能直接用 hash():
##   - Object 类型 hash 走 instance id, 同结构不同实例 hash 不等
## 所以走递归 deep equal, 对 HexCoord (RTS 事件里常见的自定义 Object) 显式 q/r 字段比对.
func _dict_equal(a: Dictionary, b: Dictionary) -> bool:
	return _deep_equal(a, b)


func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		var da: Dictionary = a as Dictionary
		var db: Dictionary = b as Dictionary
		if da.size() != db.size():
			return false
		for k in da:
			if not db.has(k):
				return false
			if not _deep_equal(da[k], db[k]):
				return false
		return true
	if a is Array:
		var arr_a: Array = a as Array
		var arr_b: Array = b as Array
		if arr_a.size() != arr_b.size():
			return false
		for i in range(arr_a.size()):
			if not _deep_equal(arr_a[i], arr_b[i]):
				return false
		return true
	if a is HexCoord:
		var ha: HexCoord = a as HexCoord
		var hb: HexCoord = b as HexCoord
		return ha.q == hb.q and ha.r == hb.r
	return a == b


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
