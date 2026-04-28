## SkillPreviewValidation 单元测试
##
## 不依赖 UI scene, 直接调 SkillPreviewValidation 的 static helper。
## 用真实的 HexBattleStrike / HexBattleSwiftStrike AbilityConfig, 走真的
## TimelineRegistry + TimedCooldownCost 路径, 保证与 UI 调点行为一致。
extends Node


func _init() -> void:
	TestFramework.register_test("ability_occupy_ms returns max(timeline, cooldown)", _test_occupy_strike)
	TestFramework.register_test("ability_occupy_ms returns 0 for null cfg", _test_occupy_null)
	TestFramework.register_test("find_track_occupy_violation: empty/single keyframe → no error", _test_violation_empty)
	TestFramework.register_test("find_track_occupy_violation: same skill within occupy → error", _test_violation_overlap)
	TestFramework.register_test("find_track_occupy_violation: same skill outside occupy → no error", _test_violation_legal_gap)
	TestFramework.register_test("find_track_occupy_violation: different skills don't conflict", _test_violation_diff_skills)
	TestFramework.register_test("next_free_time_ms_in_track: bumps to next free 100ms boundary", _test_next_free_bump)


# ========== 测试夹具 ==========

func _ensure_timelines_registered() -> void:
	# 注册 strike / swift_strike timeline,occupy 计算需要从 TimelineRegistry 取 total_duration。
	# Idempotent: TimelineRegistry.has(...) 检查避免重复注册 warning。
	if not TimelineRegistry.has(HexBattleStrike.TIMELINE_ID):
		TimelineRegistry.register(HexBattleStrike.STRIKE_TIMELINE)
	if not TimelineRegistry.has(HexBattleSwiftStrike.TIMELINE_ID):
		TimelineRegistry.register(HexBattleSwiftStrike.SWIFT_STRIKE_TIMELINE)


func _strike_resolver() -> Callable:
	# mock skill_resolver: 只识别 strike / swift_strike, 别的返回 null
	return func(sid: String) -> AbilityConfig:
		if sid == HexBattleStrike.CONFIG_ID:
			return HexBattleStrike.ABILITY
		if sid == HexBattleSwiftStrike.CONFIG_ID:
			return HexBattleSwiftStrike.ABILITY
		return null


# ========== ability_occupy_ms ==========

func _test_occupy_strike() -> void:
	_ensure_timelines_registered()
	# Strike: timeline=500ms (cooldown 2000ms 不再计入 occupy)
	TestFramework.assert_equal(500, SkillPreviewValidation.ability_occupy_ms(HexBattleStrike.ABILITY))
	# SwiftStrike: timeline=400ms
	TestFramework.assert_equal(400, SkillPreviewValidation.ability_occupy_ms(HexBattleSwiftStrike.ABILITY))


func _test_occupy_null() -> void:
	TestFramework.assert_equal(0, SkillPreviewValidation.ability_occupy_ms(null))


# ========== find_track_occupy_violation ==========

func _test_violation_empty() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 空 track
	TestFramework.assert_equal("",
		SkillPreviewValidation.find_track_occupy_violation([], "caster", resolver))
	# 单 keyframe (没有 pair 可比)
	var single: Array = [{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID}]
	TestFramework.assert_equal("",
		SkillPreviewValidation.find_track_occupy_violation(single, "caster", resolver))


func _test_violation_overlap() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 同 skill 间隔 200ms < occupy 500ms (timeline) → 必有错误
	var track: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 200, "skill": HexBattleStrike.CONFIG_ID},
	]
	var err := SkillPreviewValidation.find_track_occupy_violation(track, "caster", resolver)
	TestFramework.assert_true(err != "")
	# 错误消息里应该提到时间和 occupy
	TestFramework.assert_true("0ms" in err)
	TestFramework.assert_true("200ms" in err)
	TestFramework.assert_true("500ms" in err)


func _test_violation_legal_gap() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 同 skill 间隔 500ms == occupy (timeline) → 边界合法 (严格小于才冲突)
	var track: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 500, "skill": HexBattleStrike.CONFIG_ID},
	]
	TestFramework.assert_equal("",
		SkillPreviewValidation.find_track_occupy_violation(track, "caster", resolver))
	# 间隔 1000ms > occupy → 合法 (即使 < cooldown 2000ms — UI 不管 cooldown)
	var track2: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 500, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 1000, "skill": HexBattleStrike.CONFIG_ID},
	]
	TestFramework.assert_equal("",
		SkillPreviewValidation.find_track_occupy_violation(track2, "caster", resolver))


func _test_violation_diff_skills() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 不同 skill = 不同 ability instance, LGF 原生支持同 actor 多 instance 并发 tick
	# (Ability._execution_instances 本身是 Array)。preview 替代 ATB 决策层, 不该把
	# "actor 一次一招"这种决策层串行约束塞进 UI; 用户可以合法预览同 actor 不同 skill
	# 同时段并发执行的效果 (e.g. "caster 在 t=0 同时甩 Strike + SwiftStrike")。
	var track: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 100, "skill": HexBattleSwiftStrike.CONFIG_ID},
		{"time_ms": 200, "skill": HexBattleStrike.CONFIG_ID},  # 跟 t=0 Strike 冲突 (200 < 2000)
	]
	# 这条 track 里 (0, 200) 同 skill 冲突, 不同 skill (0, 100) 不冲突。报第一个错误。
	var err := SkillPreviewValidation.find_track_occupy_violation(track, "caster", resolver)
	TestFramework.assert_true(err != "")
	TestFramework.assert_true("200ms" in err)
	# 纯不同 skill, 任意时间间隔都不冲突 (cooldown:<config_id> namespace 隔离)
	var track_pure_diff: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 100, "skill": HexBattleSwiftStrike.CONFIG_ID},
	]
	TestFramework.assert_equal("",
		SkillPreviewValidation.find_track_occupy_violation(track_pure_diff, "caster", resolver))
	# 同 skill 第二组: SwiftStrike 之间 100 vs 200 = 100 < occupy 3000, 期望报错
	var track_swift_overlap: Array = [
		{"time_ms": 100, "skill": HexBattleSwiftStrike.CONFIG_ID},
		{"time_ms": 200, "skill": HexBattleSwiftStrike.CONFIG_ID},
	]
	var err2 := SkillPreviewValidation.find_track_occupy_violation(track_swift_overlap, "caster", resolver)
	TestFramework.assert_true(err2 != "")


# ========== next_free_time_ms_in_track ==========

func _test_next_free_bump() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 已有 t=0 Strike, candidate Strike 想放 t=200 (在 occupy 500 内) → bump 到 t=500
	var track: Array = [{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID}]
	var bumped := SkillPreviewValidation.next_free_time_ms_in_track(
		track, HexBattleStrike.CONFIG_ID, resolver, 200, -1
	)
	TestFramework.assert_equal(500, bumped)
	# 已有 t=0 Strike, candidate Strike 想放 t=1000 (> occupy) → 直接返回 1000
	var bumped_legal := SkillPreviewValidation.next_free_time_ms_in_track(
		track, HexBattleStrike.CONFIG_ID, resolver, 1000, -1
	)
	TestFramework.assert_equal(1000, bumped_legal)
	# 已有 t=0 Strike, candidate SwiftStrike 想放 t=100 → 不同 skill 不冲突, 直接返回 100
	var bumped2 := SkillPreviewValidation.next_free_time_ms_in_track(
		track, HexBattleSwiftStrike.CONFIG_ID, resolver, 100, -1
	)
	TestFramework.assert_equal(100, bumped2)
	# skip_kf_idx: 改 t=0 keyframe 自身的 time, requested=300 → 不算自己冲突, 返回 300
	var bumped3 := SkillPreviewValidation.next_free_time_ms_in_track(
		track, HexBattleStrike.CONFIG_ID, resolver, 300, 0
	)
	TestFramework.assert_equal(300, bumped3)
