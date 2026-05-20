## ScenarioAssertContext - 在 scenario 内做断言的工具
##
## 传给 SkillScenario.assert_replay(ctx)。提供:
##   - 扁平化 event 访问（replay.timeline 已被展平到 events 数组）
##   - 过滤/查询工具（按 kind / target / damage_type 等）
##   - actor id 访问（caster_id / ally_id(i) / enemy_id(i)）
##   - 断言 API（assert_eq / assert_true / assert_actor_hp_eq / ...）
##
## 用法:
## [codeblock]
## func assert_replay(ctx: ScenarioAssertContext) -> void:
##     var dmgs := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
##     ctx.assert_eq(dmgs.size(), 3, "3 DOT ticks")
##     ctx.assert_actor_ability_absent(ctx.enemy_id(0), HexBattlePoisonBuff.CONFIG_ID, "buff revoked")
## [/codeblock]
class_name ScenarioAssertContext
extends RefCounted


var events: Array[Dictionary] = []  ## 扁平化的所有事件（跨所有 frame）
var caster_id: String = ""
var ally_ids: Array[String] = []
var enemy_ids: Array[String] = []
var environment_ids: Array[String] = []

## actor_id → Array[config_id]，战斗结束瞬间该 actor 身上还在生效的 ability config_id 列表
var final_ability_states: Dictionary = {}
## actor_id → hp，战斗结束瞬间各 actor 的血量
var final_actor_hps: Dictionary = {}
## §0.X actor_id → { attr_name: current_value }，战斗结束瞬间全属性快照
var final_actor_attributes: Dictionary = {}
## §0.3 actor_id → int 0..5, 战斗结束瞬间 CharacterActor 朝向
var final_facing_directions: Dictionary = {}

var _failures: Array[String] = []


func _init(preview_result: Dictionary) -> void:
	caster_id = str(preview_result.get("caster_id", ""))
	ally_ids = preview_result.get("ally_ids", []) as Array[String]
	enemy_ids = preview_result.get("enemy_ids", []) as Array[String]
	environment_ids = preview_result.get("environment_ids", []) as Array[String]
	final_ability_states = preview_result.get("final_ability_states", {}) as Dictionary
	final_actor_hps = preview_result.get("final_actor_hps", {}) as Dictionary
	final_actor_attributes = preview_result.get("final_actor_attributes", {}) as Dictionary
	final_facing_directions = preview_result.get("final_facing_directions", {}) as Dictionary
	events = _flatten_events(preview_result.get("replay", {}) as Dictionary)


# ========== 访问 ==========

func ally_id(index: int) -> String:
	return ally_ids[index] if index >= 0 and index < ally_ids.size() else ""


func enemy_id(index: int) -> String:
	return enemy_ids[index] if index >= 0 and index < enemy_ids.size() else ""


func environment_id(index: int) -> String:
	return environment_ids[index] if index >= 0 and index < environment_ids.size() else ""


# ========== 事件过滤 ==========

## 按 kind 过滤
func events_of_kind(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		if str(e.get("kind", "")) == kind:
			result.append(e)
	return result


## 按字段 dict 过滤 damage 事件。filters 的所有 key/value 都必须 == event 字段。
func filter_damage_events(filters: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		if str(e.get("kind", "")) != "damage":
			continue
		var ok := true
		for k in filters.keys():
			if e.get(k) != filters[k]:
				ok = false
				break
		if ok:
			result.append(e)
	return result


## 按字段 dict 过滤事件（跨 kind）
func filter_events(filters: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		var ok := true
		for k in filters.keys():
			if e.get(k) != filters[k]:
				ok = false
				break
		if ok:
			result.append(e)
	return result


# ========== 高层语义断言 ==========

## 对某 actor 造成的实际生命伤害之和（即 sum(actual_life_damage)）。
##
## 护盾系统上线后，damage event 的 damage 字段是「修正后但未扣护盾」的总伤害，
## actual_life_damage 才是真正打到生命的部分。本 helper 反映的是 HP 实际损失量，
## 与「target.hp 在战斗后下降了多少」语义一致。
##
## 老 scenario（无护盾参与）actual_life_damage 默认 = damage，行为不变。
## 需要原始 modified damage 总和的场景请用 total_modified_damage_to。
func total_damage_to(target_id: String) -> float:
	var sum := 0.0
	for e in filter_damage_events({"target_actor_id": target_id}):
		sum += e.get("actual_life_damage", e.get("damage", 0.0)) as float
	return sum


## 对某 actor 造成的「修正后总伤害」之和（含被护盾吸收的部分）。
func total_modified_damage_to(target_id: String) -> float:
	var sum := 0.0
	for e in filter_damage_events({"target_actor_id": target_id}):
		sum += e.get("damage", 0.0) as float
	return sum


## 对某 actor 上的护盾总吸收量
func total_shield_absorbed_for(target_id: String) -> float:
	var sum := 0.0
	for e in filter_damage_events({"target_actor_id": target_id}):
		sum += e.get("shield_absorbed", 0.0) as float
	return sum


## 战斗结束瞬间某 actor 是否还持有某 config_id 的 ability（用于验证 buff 已被 revoke）。
##
## 数据源:HexBattleSkillScenarioHarness.run_with_config 在 GameWorld.destroy 前抓的 final_ability_states 快照，
## 不依赖 replay 事件流（grant/revoke 不经 event_collector）。
func actor_has_ability_config(target_id: String, config_id: String) -> bool:
	var config_ids: Array = final_ability_states.get(target_id, [])
	return config_ids.has(config_id)


## 战斗结束瞬间某 actor 的 HP
func actor_final_hp(target_id: String) -> float:
	return final_actor_hps.get(target_id, 0.0) as float


## §0.X 战斗结束瞬间某 actor 的指定属性 current value (含所有 modifier 累加结果)。
## 找不到 actor / 属性时返回 fallback (默认 0.0)。
##
## 典型用法 (Demon Form scenario):
##   var atk := ctx.final_actor_attribute(ctx.caster_id, "atk")
##   ctx.assert_float_eq(atk, initial_atk + tick_count * 2.0, "atk 加成与 tick 数对齐")
func final_actor_attribute(target_id: String, attr_name: String, fallback: float = 0.0) -> float:
	var actor_attrs: Dictionary = final_actor_attributes.get(target_id, {}) as Dictionary
	if not actor_attrs.has(attr_name):
		return fallback
	return actor_attrs[attr_name] as float


## §0.3 战斗结束瞬间某 CharacterActor 的朝向 (HexFacing.DIR_* 0..5)。
## 默认 -1 表示未抓到 (非 CharacterActor / 不存在)。
func actor_final_facing(target_id: String) -> int:
	return final_facing_directions.get(target_id, -1) as int


# ========== 断言 ==========

func fail(msg: String) -> void:
	_failures.append(msg)


func is_pass() -> bool:
	return _failures.is_empty()


func get_failures() -> Array[String]:
	return _failures


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual != expected:
		fail("%s — expected %s, got %s" % [msg, str(expected), str(actual)])


func assert_float_eq(actual: float, expected: float, msg: String, tolerance: float = 0.01) -> void:
	if absf(actual - expected) > tolerance:
		fail("%s — expected %.4f, got %.4f (tolerance %.4f)" % [msg, expected, actual, tolerance])


## 断言 actual 与 candidates 中任一值的差在 tolerance 内（处理 crit / 随机结果这种有限分支场景）
func assert_float_in(actual: float, candidates: Array, msg: String, tolerance: float = 0.01) -> void:
	for c in candidates:
		if absf(actual - (c as float)) <= tolerance:
			return
	fail("%s — got %.4f, not any of %s" % [msg, actual, str(candidates)])


func assert_array_float_eq(actual: Array, expected: Array, msg: String, tolerance: float = 0.01) -> void:
	if actual.size() != expected.size():
		fail("%s — size mismatch (expected %d, got %d): %s vs %s" % [msg, expected.size(), actual.size(), str(expected), str(actual)])
		return
	for i in range(actual.size()):
		var a := actual[i] as float
		var e := expected[i] as float
		if absf(a - e) > tolerance:
			fail("%s — index %d: expected %.4f, got %.4f" % [msg, i, e, a])
			return


func assert_actor_ability_absent(target_id: String, config_id: String, msg: String) -> void:
	if actor_has_ability_config(target_id, config_id):
		fail("%s — actor %s still has ability %s" % [msg, target_id, config_id])


func assert_actor_ability_present(target_id: String, config_id: String, msg: String) -> void:
	if not actor_has_ability_config(target_id, config_id):
		fail("%s — actor %s missing ability %s" % [msg, target_id, config_id])


# ========== 内部工具 ==========

## replay.timeline 是 [{frame, events}] 数组，展平成纯 events 列表
static func _flatten_events(replay_data: Dictionary) -> Array[Dictionary]:
	var flat: Array[Dictionary] = []
	var timeline: Array = replay_data.get("timeline", [])
	for frame_data in timeline:
		if not (frame_data is Dictionary):
			continue
		var frame_events: Array = (frame_data as Dictionary).get("events", [])
		for e in frame_events:
			if e is Dictionary:
				flat.append(e as Dictionary)
	return flat
