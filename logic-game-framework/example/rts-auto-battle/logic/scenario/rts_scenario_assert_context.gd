## RtsScenarioAssertContext - scenario 断言上下文 (P3.3)
##
## harness 跑完战斗后构造此上下文给 scenario.assert_replay 用。持:
##   - world / procedure 引用 (查询用; 不修改)
##   - sampled_positions: 主 tick 循环每 tick 采的 actor.position_2d 副本
##                        (path_length_traveled / detour_ratio 累积来源)
##   - events: 全局 event_collector 镜像 (events_filtered 用)
##   - team_unit_ids / team_building_ids: scenario 声明顺序的 actor_id 列表
##                                        (selector 展开 + ctx.get_unit_by_index 用)
##   - fail_reason: 第一次 assert_* 失败的描述; 后续 assert 不再继续报错
##                  (避免 chained failures 噪音)
##
## 决策来源: phase-3-advanced.md §P3.3
class_name RtsScenarioAssertContext
extends RefCounted


# ========== 字段 ==========

var world: RtsWorldGameplayInstance = null
var procedure: RtsAutoBattleProcedure = null

## actor_id (String) → Array[Vector2] (per-tick position 采样)
##
## 第 0 项 = tick 1 entry 时 (即第一次 sample) 的 position; 后续每 tick 一项。
## 仅 alive 时采; actor 死后停采 (Array 长度即 alive ticks)。
var sampled_positions: Dictionary = {}

## tick_index → events array (复制自 GameWorld.event_collector); 每 tick 一项。
var events_by_tick: Array[Array] = []

## team_id → Array[String] actor_id (按 scenario 声明顺序; selector 解析用)
var team_unit_ids: Dictionary = {}
var team_building_ids: Dictionary = {}

## actor_id → 起始 position (start_position 查询用; 第一次 sample 即起始)
var start_positions: Dictionary = {}

var _fail_reason: String = ""
var _scenario_name: String = "?"


# ========== 初始化 ==========

func _init(
	p_world: RtsWorldGameplayInstance,
	p_procedure: RtsAutoBattleProcedure,
	p_sampled_positions: Dictionary,
	p_events_by_tick: Array,
	p_team_unit_ids: Dictionary,
	p_team_building_ids: Dictionary,
	p_start_positions: Dictionary,
	p_scenario_name: String,
) -> void:
	world = p_world
	procedure = p_procedure
	sampled_positions = p_sampled_positions
	# 复制 event 数组到 typed Array[Array]
	for arr in p_events_by_tick:
		events_by_tick.append(arr as Array)
	team_unit_ids = p_team_unit_ids
	team_building_ids = p_team_building_ids
	start_positions = p_start_positions
	_scenario_name = p_scenario_name


# ========== 失败状态 ==========

func has_failed() -> bool:
	return _fail_reason != ""


func get_fail_reason() -> String:
	return _fail_reason


func fail(reason: String) -> void:
	if _fail_reason == "":
		_fail_reason = reason


# ========== Actor 查询 ==========

func get_actor(actor_id: String) -> Actor:
	if world == null:
		return null
	return world.get_actor(actor_id)


## team 所有 alive units (RtsUnitActor 子类).
##
## 注意: 顺序不保证 = scenario 声明顺序 — world.get_alive_units 是 procedure tick 期间动态变化。
## 想按 scenario 声明顺序拿 unit, 用 get_unit_by_index。
func get_units_by_team(team_id: int) -> Array:
	var result: Array = []
	if world == null:
		return result
	for actor in world.get_alive_actors():
		if actor is RtsUnitActor and (actor as RtsUnitActor).get_team_id() == team_id:
			result.append(actor)
	return result


func get_buildings_by_team(team_id: int) -> Array:
	var result: Array = []
	if world == null:
		return result
	for actor in world.get_alive_actors():
		if actor is RtsBuildingActor and (actor as RtsBuildingActor).get_team_id() == team_id:
			result.append(actor)
	return result


## 按 scenario 声明顺序拿单位 (含已死的; assert_replay 经常需要"那个声明的第 0 个 unit",
## 此时 alive 状态可能已变).
##
## 越界返回 null; team 不存在返回 null。
func get_unit_by_index(team_id: int, index: int) -> RtsUnitActor:
	var ids: Array = team_unit_ids.get(team_id, []) as Array
	if index < 0 or index >= ids.size():
		return null
	var actor := get_actor(ids[index] as String)
	return actor as RtsUnitActor


func get_building_by_index(team_id: int, index: int) -> RtsBuildingActor:
	var ids: Array = team_building_ids.get(team_id, []) as Array
	if index < 0 or index >= ids.size():
		return null
	var actor := get_actor(ids[index] as String)
	return actor as RtsBuildingActor


## scenario 声明的 team team_id 全部 unit_ids (含已死者; assert_replay 关心声明顺序)
func get_unit_ids_by_team(team_id: int) -> Array:
	return (team_unit_ids.get(team_id, []) as Array).duplicate()


# ========== Position / 路径 ==========

## actor 战斗结束时的 position. 死 actor 用最后一帧位置 (sampled_positions 末项)。
func final_position(actor_id: String) -> Vector2:
	var actor := get_actor(actor_id)
	if actor != null and actor is RtsBattleActor:
		return (actor as RtsBattleActor).position_2d
	# 死 actor 走 sample 末项
	var samples: Array = sampled_positions.get(actor_id, []) as Array
	if samples.is_empty():
		return Vector2.ZERO
	return samples[-1] as Vector2


## actor 起始 position (sample 第 0 项). 不存在返回 ZERO。
func start_position(actor_id: String) -> Vector2:
	return start_positions.get(actor_id, Vector2.ZERO) as Vector2


## actor.attribute_set.hp 末态 (含 0 — 死亡). 找不到返回 -1。
func final_hp(actor_id: String) -> float:
	var actor := get_actor(actor_id)
	if actor == null:
		return -1.0
	if actor is RtsUnitActor:
		return (actor as RtsUnitActor).attribute_set.hp
	if actor is RtsBuildingActor:
		return (actor as RtsBuildingActor).attribute_set.hp
	return -1.0


## actor 累计走过的路径长度 (sampled_positions delta 累加).
##
## 不在 sample dict 里 → 返回 0。
func path_length_traveled(actor_id: String) -> float:
	var samples: Array = sampled_positions.get(actor_id, []) as Array
	if samples.size() < 2:
		return 0.0
	var total: float = 0.0
	for i in range(1, samples.size()):
		total += (samples[i] as Vector2).distance_to(samples[i - 1] as Vector2)
	return total


## actor 起点到指定终点的直线距离.
func straight_line_distance(actor_id: String, end_pos: Vector2) -> float:
	var start: Vector2 = start_position(actor_id)
	return start.distance_to(end_pos)


## actor 实际路径长度 / 直线距离 (绕路系数).
##
## 直线距离 ≈ 0 (起点 = 终点) 返回 1.0 (避免除零)。
func detour_ratio(actor_id: String, end_pos: Vector2) -> float:
	var straight := straight_line_distance(actor_id, end_pos)
	if straight < 1.0:
		return 1.0
	return path_length_traveled(actor_id) / straight


# ========== Formation / 多单位 ==========

## 一组 unit 之间最小成对距离. < 2 单位返回 INF (无成对可比).
func pairwise_min_distance(unit_ids: Array) -> float:
	var actors: Array[RtsBattleActor] = []
	for id in unit_ids:
		var a := get_actor(id as String)
		if a is RtsBattleActor and not (a as RtsBattleActor).is_dead():
			actors.append(a as RtsBattleActor)
	if actors.size() < 2:
		return INF
	var min_dist: float = INF
	for i in range(actors.size()):
		for j in range(i + 1, actors.size()):
			var d := actors[i].position_2d.distance_to(actors[j].position_2d)
			if d < min_dist:
				min_dist = d
	return min_dist


## 一组 unit 当前位置的几何中心. 空数组返回 ZERO。
func formation_centroid(unit_ids: Array) -> Vector2:
	var sum := Vector2.ZERO
	var count: int = 0
	for id in unit_ids:
		var a := get_actor(id as String)
		if a is RtsBattleActor and not (a as RtsBattleActor).is_dead():
			sum += (a as RtsBattleActor).position_2d
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)


## 一组 unit 当前位置距 centroid 的平均距离 (formation 紧凑度指标).
##
## 越小越紧凑; 完全重合 = 0; 完全散开 = avg pairwise spread。
func formation_offset_avg(unit_ids: Array) -> float:
	var centroid := formation_centroid(unit_ids)
	var sum: float = 0.0
	var count: int = 0
	for id in unit_ids:
		var a := get_actor(id as String)
		if a is RtsBattleActor and not (a as RtsBattleActor).is_dead():
			sum += (a as RtsBattleActor).position_2d.distance_to(centroid)
			count += 1
	if count == 0:
		return 0.0
	return sum / float(count)


# ========== Event 查询 ==========

## 跑完所有 events 扁平化数组 (events_by_tick[tick_idx] flatten 后).
func all_events() -> Array:
	var flat: Array = []
	for tick_events in events_by_tick:
		flat.append_array(tick_events)
	return flat


## 按 predicate(event_dict) -> bool 过滤. predicate 不可空。
func events_filtered(predicate: Callable) -> Array:
	var result: Array = []
	for event in all_events():
		if predicate.call(event):
			result.append(event)
	return result


## procedure 完整 player commands 流式 log (含 success / fail entry).
func player_commands_log() -> Array:
	if procedure == null:
		return []
	return procedure.get_player_commands_log()


## battle 总 tick 数 (procedure._current_tick 末态).
func tick_count() -> int:
	if procedure == null:
		return 0
	return procedure.get_current_tick()


# ========== 断言 API ==========
#
# 失败行为: 第一次 assert_* 不通过 → 写入 _fail_reason; 后续 assert 仍跑但仅在 _fail_reason
# 为空时记录新 reason (避免 chained failures 噪音).
# 也可以直接调 fail() 写自定义 reason。

func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		var prefix := msg if msg != "" else "assert_eq"
		fail("%s: expected=%s actual=%s" % [prefix, str(expected), str(actual)])


func assert_float_in(actual: float, low: float, high: float, msg: String = "") -> void:
	if actual < low or actual > high:
		var prefix := msg if msg != "" else "assert_float_in"
		fail("%s: actual=%.3f expected in [%.3f, %.3f]" % [prefix, actual, low, high])


func assert_ge(actual: float, threshold: float, msg: String = "") -> void:
	if actual < threshold:
		var prefix := msg if msg != "" else "assert_ge"
		fail("%s: actual=%.3f >= %.3f failed" % [prefix, actual, threshold])


func assert_le(actual: float, threshold: float, msg: String = "") -> void:
	if actual > threshold:
		var prefix := msg if msg != "" else "assert_le"
		fail("%s: actual=%.3f <= %.3f failed" % [prefix, actual, threshold])


## actor 是否在指定半径内. 用于 "abc 单位是否抵达 xyz 附近"
func assert_within(actor_id: String, target_pos: Vector2, radius: float, msg: String = "") -> void:
	var pos := final_position(actor_id)
	var d := pos.distance_to(target_pos)
	if d > radius:
		var prefix := msg if msg != "" else "assert_within"
		fail("%s: actor %s pos=%s dist=%.3f > radius=%.3f to target=%s" % [
			prefix, actor_id, str(pos), d, radius, str(target_pos),
		])
