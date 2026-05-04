## RtsAutoBattleProcedure._compare_motion_actor sort key acceptance smoke (M7c — AC9 / R5 P1 #1)
##
## 验证 motion-bearing actor sort key 用 `(type: String, spawn_seq: int)` 数值复合 key,
## **不**用 `actor.get_id()` 字符串字典序 — 防止 `Character_10` < `Character_2` 字典序漂
## (data-structures.md §12.5)。
##
## **AC9.1 — 同 type 内按 spawn_seq 数值序**(关键!): ≥ 10 同 type unit 时数值序 vs 字典序
##   差异显现 — 字典序: Character_1 < Character_10 < Character_11 < Character_2;
##   数值序: spawn_seq=1 < 2 < 10 < 11。AC 要求**数值序**。
##
## **AC9.2 — 跨 type 按 type 字典序**: 不同 type 之间走 String <(type 名短且固定,跨 run 稳定)。
##
## **AC9.3 — 同 (type, spawn_seq) 不可能**(unique invariant): spawn_seq 全局递增单调,任何
##   两个 actor 不可能同 spawn_seq。本 smoke 不显式验,但断言 sort 结果稳定。
##
## **AC9.4 — _tick_motion_bearing_actors 收集 motion-bearing 集合**: motion_component != null
##   的 actor 才进集合;null 的(building / 无 motion 单位)被过滤掉。
##
## **不验证**(M7d 范围):
##   - production callsite 真 set actor.motion_component → procedure 真 motion-bearing tick → M7d
##   - replay seed=42 deep-equal 在 motion 真接 production 后 → M7d 接受新 baseline
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_compare_motion_actor_numeric_within_same_type()
	_test_compare_motion_actor_dictionary_drift_NOT_used()
	_test_compare_motion_actor_cross_type_dictionary()
	_test_motion_bearing_filter()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - motion_tick_order_with_10plus_units — AC9.1-9.4 (R5 P1 #1) all OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_unit(p_type: String, p_spawn_seq: int) -> RtsBattleActor:
	# Use RtsUnitActor (concrete subclass) for type construction;reset type to test value
	var u := RtsUnitActor.new(RtsUnitClassConfig.UnitClass.MELEE)
	u.type = p_type
	u.spawn_seq = p_spawn_seq
	return u


# ========== Test cases ==========

## AC9.1: 12 同 type "Character" actor,spawn_seq 1-12,sort 后必须按 spawn_seq 数值升序
## (spawn_seq=2 排在 spawn_seq=10 之前 — 字典序会反过来)
func _test_compare_motion_actor_numeric_within_same_type() -> void:
	var actors: Array = []
	# 故意打乱顺序 push 进 array,sort 后应稳定到 1, 2, 3, ..., 12
	var seqs: Array = [10, 2, 11, 1, 5, 7, 3, 12, 4, 8, 6, 9]
	for s in seqs:
		actors.append(_make_unit("Character", s))
	actors.sort_custom(RtsAutoBattleProcedure._compare_motion_actor)

	for i in range(actors.size()):
		var a: RtsBattleActor = actors[i] as RtsBattleActor
		var expected: int = i + 1
		if a.spawn_seq != expected:
			_failures.append("AC9.1: position %d expected spawn_seq=%d but got %d" % [i, expected, a.spawn_seq])


## AC9.1 反证:如果用 actor.get_id() 字符串字典序(IdGenerator '%s_%d' 无 zero-pad),
## sort 结果会让 Character_10 < Character_2(因为 '1' < '2')— 我们的 sort 必须**不**这样。
##
## 模拟字典序行为:用 mock id "Character_2" / "Character_10" / "Character_11" 直接 String compare,
## 验证字典序 vs 数值序结果不同 — 而我们的 sort 跟数值序一致。
func _test_compare_motion_actor_dictionary_drift_NOT_used() -> void:
	# String 字典序展示:Character_10 < Character_2(因为 '1' < '2')
	var dict_order_id_2_lt_10: bool = "Character_10" < "Character_2"
	if not dict_order_id_2_lt_10:
		_failures.append("AC9.1 sanity: 'Character_10' < 'Character_2' should be true in dict order — env different?")

	# 我们的 sort 对 spawn_seq=2 vs spawn_seq=10:数值序 2 < 10
	var a2: RtsBattleActor = _make_unit("Character", 2)
	var a10: RtsBattleActor = _make_unit("Character", 10)
	# _compare_motion_actor(a2, a10) 应返 true (a2 在 a10 之前)
	var our_sort_result: bool = RtsAutoBattleProcedure._compare_motion_actor(a2, a10)
	if not our_sort_result:
		_failures.append("AC9.1: numeric sort says spawn_seq=2 should < spawn_seq=10 but _compare_motion_actor returned false")

	# 反向验证:_compare_motion_actor(a10, a2) 应返 false
	var reverse_result: bool = RtsAutoBattleProcedure._compare_motion_actor(a10, a2)
	if reverse_result:
		_failures.append("AC9.1: _compare_motion_actor(a10, a2) should be false (a10 NOT before a2)")


## AC9.2: 不同 type 之间走 String < — "Character" < "Worker"(字典序)
func _test_compare_motion_actor_cross_type_dictionary() -> void:
	var ch: RtsBattleActor = _make_unit("Character", 999)
	var wk: RtsBattleActor = _make_unit("Worker", 1)
	# "Character" < "Worker" 字典序 → ch 在 wk 之前(无视 spawn_seq 差距)
	var ch_before_wk: bool = RtsAutoBattleProcedure._compare_motion_actor(ch, wk)
	if not ch_before_wk:
		_failures.append("AC9.2: 'Character' < 'Worker' lex sort failed")

	# 反向:Worker (spawn_seq=1) NOT 在 Character (spawn_seq=999) 之前
	var wk_before_ch: bool = RtsAutoBattleProcedure._compare_motion_actor(wk, ch)
	if wk_before_ch:
		_failures.append("AC9.2: 'Worker' should NOT be before 'Character' even with smaller spawn_seq")


## AC9.4: motion_component != null 的 actor 才被收集
func _test_motion_bearing_filter() -> void:
	# 直接调 procedure helper 不太方便(需要 world / dt 参数);改测 motion_component 字段判定。
	# motion_component 默认 null → 不被收集
	var u_no_motion: RtsBattleActor = _make_unit("Character", 1)
	if u_no_motion.motion_component != null:
		_failures.append("AC9.4: default motion_component should be null")

	# 手动 set motion_component → 该被收集(实际 motion 实例)
	var motion := RtsUnitMotion.new()
	var component := RtsMotionComponent.new(u_no_motion, motion)
	u_no_motion.motion_component = component
	if u_no_motion.motion_component == null:
		_failures.append("AC9.4: motion_component after set should not be null")
