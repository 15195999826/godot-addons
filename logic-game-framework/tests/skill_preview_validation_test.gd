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
	# Strike: timeline=500ms, cooldown=2000ms → max=2000
	TestFramework.assert_equal(2000, SkillPreviewValidation.ability_occupy_ms(HexBattleStrike.ABILITY))
	# SwiftStrike: timeline=400ms, cooldown=3000ms → max=3000
	TestFramework.assert_equal(3000, SkillPreviewValidation.ability_occupy_ms(HexBattleSwiftStrike.ABILITY))


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
	# 同 skill 间隔 1000ms < occupy 2000ms → 必有错误
	var track: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 1000, "skill": HexBattleStrike.CONFIG_ID},
	]
	var err := SkillPreviewValidation.find_track_occupy_violation(track, "caster", resolver)
	TestFramework.assert_true(err != "")
	# 错误消息里应该提到时间和 occupy
	TestFramework.assert_true("0ms" in err)
	TestFramework.assert_true("1000ms" in err)
	TestFramework.assert_true("2000ms" in err)


func _test_violation_legal_gap() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 同 skill 间隔 2000ms == occupy → 边界合法 (严格小于才冲突)
	var track: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 2000, "skill": HexBattleStrike.CONFIG_ID},
	]
	TestFramework.assert_equal("",
		SkillPreviewValidation.find_track_occupy_violation(track, "caster", resolver))
	# 间隔 2100ms > occupy → 合法
	var track2: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 2100, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 4200, "skill": HexBattleStrike.CONFIG_ID},
	]
	TestFramework.assert_equal("",
		SkillPreviewValidation.find_track_occupy_violation(track2, "caster", resolver))


func _test_violation_diff_skills() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 不同 skill 即使 time 重合也不冲突 (cooldown tag namespace 隔离)
	var track: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 100, "skill": HexBattleSwiftStrike.CONFIG_ID},
		{"time_ms": 200, "skill": HexBattleStrike.CONFIG_ID},  # 跟 t=0 Strike 冲突 (200 < 2000)
	]
	# 这条 track 里 (0, 200) 同 skill 冲突, 不同 skill (0, 100) 不冲突。报第一个错误。
	var err := SkillPreviewValidation.find_track_occupy_violation(track, "caster", resolver)
	TestFramework.assert_true(err != "")
	TestFramework.assert_true("200ms" in err)
	# 移除冲突项, 只剩不同 skill, 应该无错误
	var track_clean: Array = [
		{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID},
		{"time_ms": 100, "skill": HexBattleSwiftStrike.CONFIG_ID},
		{"time_ms": 200, "skill": HexBattleSwiftStrike.CONFIG_ID},  # SwiftStrike occupy=3000, 100 vs 200 = 100 < 3000 冲突
	]
	# 这里 SwiftStrike 之间 100 vs 200 也冲突 (100 < 3000), 期望报错
	var err2 := SkillPreviewValidation.find_track_occupy_violation(track_clean, "caster", resolver)
	TestFramework.assert_true(err2 != "")


# ========== next_free_time_ms_in_track ==========

func _test_next_free_bump() -> void:
	_ensure_timelines_registered()
	var resolver := _strike_resolver()
	# 已有 t=0 Strike, candidate Strike 想放 t=1000 → 应被 bump 到 t=2000 (occupy 边界)
	var track: Array = [{"time_ms": 0, "skill": HexBattleStrike.CONFIG_ID}]
	var bumped := SkillPreviewValidation.next_free_time_ms_in_track(
		track, HexBattleStrike.CONFIG_ID, resolver, 1000, -1
	)
	TestFramework.assert_equal(2000, bumped)
	# 已有 t=0 Strike, candidate SwiftStrike 想放 t=100 → 不同 skill 不冲突, 直接返回 100
	var bumped2 := SkillPreviewValidation.next_free_time_ms_in_track(
		track, HexBattleSwiftStrike.CONFIG_ID, resolver, 100, -1
	)
	TestFramework.assert_equal(100, bumped2)
	# skip_kf_idx: 改 t=0 keyframe 自身的 time, requested=500 → 不算自己冲突, 返回 500
	var bumped3 := SkillPreviewValidation.next_free_time_ms_in_track(
		track, HexBattleStrike.CONFIG_ID, resolver, 500, 0
	)
	TestFramework.assert_equal(500, bumped3)
