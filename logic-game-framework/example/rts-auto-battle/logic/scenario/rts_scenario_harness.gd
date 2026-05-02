## RtsScenarioHarness - 声明式 RTS scenario 跑测器 (P3.3)
##
## 与 hex example HexBattleSkillScenarioHarness 同构. 输入一个 RtsScenario, 输出
## {success, ticks, fail_reason, scenario_name} 结果 dict, 中间装配 world / actors /
## procedure / 玩家命令 / tick 循环 / 断言上下文.
##
## 用法 (smoke 入口里调):
## ```
## extends Node
## func _ready() -> void:
##     GameWorld.init()
##     var s := MyScenario.new()
##     var result: Dictionary = RtsScenarioHarness.run(s, self)
##     if result.success:
##         print("SMOKE_TEST_RESULT: PASS - %s ticks=%d" % [s.get_name(), result.ticks])
##         get_tree().quit(0)
##     else:
##         print("SMOKE_TEST_RESULT: FAIL - %s: %s" % [s.get_name(), result.fail_reason])
##         get_tree().quit(1)
## ```
##
## 关键设计:
##   - 不动 GameWorld.init / destroy: caller 自己负责. harness 内只 create_instance + world.end()
##   - host: Node 参数, 用来 add_child(RtsNavAgent). caller 把自己 (smoke Node) 传进来。
##   - 多个 scenario 在同一 smoke 里串跑: caller 在每 scenario 之间不 destroy GameWorld 也行;
##     harness 内 world.end() 后, 下一 scenario 调 RtsScenarioHarness.run 时再 create_instance
##   - selector 展开: scenario.get_player_commands 用 unit_selector dict 引用 unit_ids,
##     harness spawn 完 units 后展开为实际 actor_id 列表, 再构 RtsMoveUnitsCommand
##
## 决策来源: phase-3-advanced.md §P3.3
class_name RtsScenarioHarness


# ========== 常量 ==========

## 默认 tick interval (ms). scenario 不在 scene_config 指定时用此值.
const DEFAULT_TICK_INTERVAL_MS: float = 50.0

## 安全上限 ticks (scenario.get_max_ticks 不超过此). 防止 scenario 死循环.
const MAX_TICKS_HARD_CAP: int = 2000


# ========== 主入口 ==========

## 跑一个 scenario. 返回 dict:
##   { "success": bool, "ticks": int, "fail_reason": String, "scenario_name": String,
##     "events_count": int, "player_commands_count": int }
##
## host 必须是 Node — RtsNavAgent 是 Node-based, 需要 add_child 进 scene tree。
## 通常 caller (smoke .gd 自身) 直接传 self。
static func run(scenario: RtsScenario, host: Node) -> Dictionary:
	if scenario == null:
		return _error_result("scenario is null", "?")
	if host == null:
		return _error_result("host is null", scenario.get_name())

	var scenario_name: String = scenario.get_name()
	var scene_config: Dictionary = scenario.get_scene_config()

	# ===== 装配 =====

	var map_size: Vector2 = scene_config.get("map_size", Vector2(600, 500)) as Vector2
	var rng_seed: int = int(scene_config.get("rng_seed", 0))
	var tick_interval_ms: float = float(scene_config.get("tick_interval_ms", DEFAULT_TICK_INTERVAL_MS))
	var team_configs: Dictionary = scene_config.get("team_configs", {}) as Dictionary

	var grid := RtsBattleGrid.new(map_size, RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)

	var world := GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	if world == null:
		return _error_result("create_instance returned null", scenario_name)
	world.set_grid(grid)

	# 容器 — 装配过程需要的 mapping
	var team_unit_ids: Dictionary = { 0: [] as Array, 1: [] as Array }
	var team_building_ids: Dictionary = { 0: [] as Array, 1: [] as Array }
	var team_actors: Dictionary = { 0: [] as Array, 1: [] as Array }
	var controllers: Dictionary = {}  # actor_id → RtsUnitController
	var agents: Dictionary = {}  # actor_id → RtsNavAgent (用于 host parenting)

	# Spawn buildings (顺序记录 ids)
	var buildings_cfg: Array = scene_config.get("buildings", []) as Array
	for entry in buildings_cfg:
		var b_cfg: Dictionary = entry as Dictionary
		var kind: String = b_cfg.get("kind", "") as String
		var team_id: int = int(b_cfg.get("team", 0))
		var pos: Vector2 = b_cfg.get("pos", Vector2.ZERO) as Vector2
		var building := _create_building_by_kind(kind)
		if building == null:
			world.end()
			return _error_result("unknown building kind: %s" % kind, scenario_name)
		building.set_team_id(team_id)
		world.add_actor(building)
		building.position_2d = pos
		if b_cfg.has("hp_override"):
			building.attribute_set.set_hp_base(float(b_cfg["hp_override"]))
		(team_actors[team_id] as Array).append(building)
		(team_building_ids[team_id] as Array).append(building.get_id())

	# Spawn units (顺序记录 ids)
	var units_cfg: Array = scene_config.get("units", []) as Array
	for entry in units_cfg:
		var u_cfg: Dictionary = entry as Dictionary
		var unit_class: int = int(u_cfg.get("class", RtsUnitClassConfig.UnitClass.MELEE))
		var team_id_u: int = int(u_cfg.get("team", 0))
		var pos_u: Vector2 = u_cfg.get("pos", Vector2.ZERO) as Vector2
		var unit := RtsUnitActor.new(unit_class)
		unit.set_team_id(team_id_u)
		world.add_actor(unit)
		unit.position_2d = pos_u
		if u_cfg.has("stance"):
			unit.stance = int(u_cfg["stance"])
		var agent := RtsNavAgent.new()
		host.add_child(agent)
		agent.bind_actor(unit, grid)
		var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
		var controller := RtsUnitController.new(unit, agent, strategy)
		controllers[unit.get_id()] = controller
		agents[unit.get_id()] = agent
		(team_actors[team_id_u] as Array).append(unit)
		(team_unit_ids[team_id_u] as Array).append(unit.get_id())

	# 默认 team_configs (caller 不传 → unconfigured 占位); place_building 类 scenario 应自配
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []
	for a in (team_actors[0] as Array):
		left_actors.append(a as RtsBattleActor)
	for a in (team_actors[1] as Array):
		right_actors.append(a as RtsBattleActor)

	# Event sink (镜像每 tick events 给 ctx.events_by_tick)
	var events_by_tick: Array = []
	var event_sink := func(events: Array) -> void:
		var copy: Array = []
		for e in events:
			copy.append(e)
		events_by_tick.append(copy)

	var procedure := world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": tick_interval_ms,
		"unit_runtimes": controllers,
		"team_configs": team_configs,
		"rng_seed": rng_seed,
		"event_sink": event_sink,
	})

	# ===== Player commands 装配 =====

	# 拿 raw commands; 按 tick 升序稳定排序; 解析 selector → 实际命令对象 enqueue
	# place_building 走真实 RtsPlaceBuildingCommand; add_static_obstacle 走 deferred 列表
	# (绕 build_zone 校验, 在 tick 主循环里用 world.add_actor + grid.place_building)
	var raw_commands: Array[Dictionary] = scenario.get_player_commands()
	# 按 tick 稳定排序 (相同 tick 保 insertion order)
	raw_commands = _stable_sort_by_tick(raw_commands)

	var deferred_obstacles: Array[Dictionary] = []  # 每条 {tick, building_kind, team, pos}

	for raw in raw_commands:
		var cmd: Dictionary = raw as Dictionary
		var tick_stamp: int = int(cmd.get("tick", 0))
		var kind: String = cmd.get("kind", "") as String
		var team_id_c: int = int(cmd.get("team_id", 0))

		match kind:
			"move_units":
				var selector: Dictionary = cmd.get("unit_selector", {}) as Dictionary
				var unit_ids := _expand_unit_selector(selector, team_unit_ids)
				var target_pos: Vector2 = cmd.get("target_pos", Vector2.ZERO) as Vector2
				var move_cmd := RtsMoveUnitsCommand.new(tick_stamp, team_id_c, unit_ids, target_pos)
				procedure.enqueue_player_command(move_cmd)
			"place_building":
				var bk: String = cmd.get("building_kind", "") as String
				var bp: Vector2 = cmd.get("pos", Vector2.ZERO) as Vector2
				var place_cmd := RtsPlaceBuildingCommand.new(tick_stamp, team_id_c, bk, bp)
				procedure.enqueue_player_command(place_cmd)
			"add_static_obstacle":
				deferred_obstacles.append({
					"tick": tick_stamp,
					"team_id": team_id_c,
					"building_kind": cmd.get("building_kind", "") as String,
					"pos": cmd.get("pos", Vector2.ZERO) as Vector2,
				})
			_:
				world.end()
				return _error_result("unknown player command kind: %s" % kind, scenario_name)

	# ===== Tick 循环 =====

	var max_ticks: int = min(scenario.get_max_ticks(), MAX_TICKS_HARD_CAP)

	# Sample 起始位置
	var start_positions: Dictionary = {}
	var sampled_positions: Dictionary = {}
	for actor in world.get_alive_actors():
		if actor is RtsBattleActor:
			var ba := actor as RtsBattleActor
			var p := ba.position_2d
			start_positions[ba.get_id()] = p
			sampled_positions[ba.get_id()] = [p] as Array

	for tick_i in range(max_ticks):
		# Apply deferred obstacles for tick == tick_i + 1 (procedure._current_tick 在 tick_once 内 +1)
		var current_tick_target := tick_i + 1
		for ob in deferred_obstacles:
			if int(ob.tick) == current_tick_target:
				_inject_static_obstacle(world, grid, ob)

		procedure.tick_once()

		# 采样 alive actors position (含建筑 — 建筑 stationary 但记录死活也用)
		for actor in world.get_alive_actors():
			if actor is RtsBattleActor:
				var ba := actor as RtsBattleActor
				var aid := ba.get_id()
				if not sampled_positions.has(aid):
					# 战中新加 actor (deferred obstacle / production spawn) → 起始 sample 在第一次出现时
					start_positions[aid] = ba.position_2d
					sampled_positions[aid] = [ba.position_2d] as Array
				else:
					(sampled_positions[aid] as Array).append(ba.position_2d)

		if procedure.should_end():
			break

	procedure.finish()

	# ===== 构 ctx + assert_replay =====

	var ctx := RtsScenarioAssertContext.new(
		world, procedure, sampled_positions, events_by_tick,
		team_unit_ids, team_building_ids, start_positions, scenario_name,
	)

	scenario.assert_replay(ctx)

	var result: Dictionary = {
		"success": not ctx.has_failed(),
		"ticks": procedure.get_current_tick(),
		"fail_reason": ctx.get_fail_reason(),
		"scenario_name": scenario_name,
		"events_count": _count_events(events_by_tick),
		"player_commands_count": procedure.get_player_commands_log().size(),
	}

	# 清理 nav agent (host 上仍挂着)
	for aid in agents.keys():
		var ag: RtsNavAgent = agents[aid]
		if ag != null and is_instance_valid(ag):
			ag.queue_free()

	world.end()

	return result


# ========== 辅助 ==========

static func _expand_unit_selector(
	selector: Dictionary, team_unit_ids: Dictionary,
) -> Array[String]:
	var result: Array[String] = []
	var team_id: int = int(selector.get("team", 0))
	var ids: Array = team_unit_ids.get(team_id, []) as Array
	if selector.get("all", false):
		for id in ids:
			result.append(id as String)
		return result
	if selector.has("indices"):
		var indices: Array = selector["indices"] as Array
		for idx in indices:
			var i: int = int(idx)
			if i >= 0 and i < ids.size():
				result.append(ids[i] as String)
		return result
	return result


static func _create_building_by_kind(kind: String) -> RtsBuildingActor:
	match kind:
		RtsBuildingConfig.KIND_BARRACKS:
			return RtsBuildings.create_barracks()
		RtsBuildingConfig.KIND_CRYSTAL_TOWER:
			return RtsBuildings.create_crystal_tower()
		RtsBuildingConfig.KIND_ARCHER_TOWER:
			return RtsBuildings.create_archer_tower()
		_:
			return null


## 直接 add_actor + 写 grid blocking, 不走 RtsBuildingPlacement 校验.
##
## 用于 dynamic obstacle scenario: 战斗中段忽然出现障碍 (绕过 build_zone 限制),
## 让 stuck detector + local repath 触发。
static func _inject_static_obstacle(
	world: RtsWorldGameplayInstance, grid: RtsBattleGrid, ob: Dictionary,
) -> void:
	var building := _create_building_by_kind(ob.get("building_kind", "") as String)
	if building == null:
		return
	building.set_team_id(int(ob.get("team_id", 0)))
	world.add_actor(building)
	building.position_2d = ob.get("pos", Vector2.ZERO) as Vector2
	var footprint: Array = building.get_footprint_cells(grid)
	grid.place_building(building.get_id(), footprint)


static func _stable_sort_by_tick(commands: Array[Dictionary]) -> Array[Dictionary]:
	# 给每条命令打原始 idx 保稳定; 排序后剥 idx
	var indexed: Array = []
	for i in commands.size():
		indexed.append({"_idx": i, "cmd": commands[i]})
	indexed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = int((a["cmd"] as Dictionary).get("tick", 0))
		var tb: int = int((b["cmd"] as Dictionary).get("tick", 0))
		if ta != tb:
			return ta < tb
		return int(a["_idx"]) < int(b["_idx"])
	)
	var result: Array[Dictionary] = []
	for entry in indexed:
		result.append((entry as Dictionary)["cmd"] as Dictionary)
	return result


static func _count_events(events_by_tick: Array) -> int:
	var total: int = 0
	for arr in events_by_tick:
		total += (arr as Array).size()
	return total


static func _error_result(reason: String, scenario_name: String) -> Dictionary:
	return {
		"success": false,
		"ticks": 0,
		"fail_reason": reason,
		"scenario_name": scenario_name,
		"events_count": 0,
		"player_commands_count": 0,
	}
