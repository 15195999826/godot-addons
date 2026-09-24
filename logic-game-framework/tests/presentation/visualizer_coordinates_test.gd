extends Node

## hex 翻译员的坐标口径钉子（PL1 坐标对齐）：卡片只带逻辑平面 axial，欧氏量留给 view 投影后算
##
## 钉住合同：
## - projectile_launched：起止位置优先取账本（含在飞插值），账本没有的 actor 读事件字段的前两分量
##   （hex 逻辑层给的是 Vector3(q, r, 0)）；duration = 逻辑平面距离 / speed，不足 300 ms 夹到 300
## - push_blocked：bump.direction = 停住格 → 撞向格的 axial 一步（不归一化），max_offset = 0.30（格距比例）；
##   同格 noop
## - stage_cue cone：cells 去重、grid cone 只出区域外沿且端点是三格中心质心、angle cone 不出外沿、
##   逻辑层 edge_segments 原样透传成 guide_segments（零长度丢弃）
## - stage_cue 控制飘字：position = 目标 actor 的 axial


const PROBE_TYPE := "probe"


func _init() -> void:
	TestFramework.register_test("翻译员坐标口径 投射物：账本 axial 优先、事件前两分量兜底、时长 = 逻辑距离 / 速度夹 300", _test_projectile)
	TestFramework.register_test("翻译员坐标口径 bump：方向 = axial 一步不归一化、幅度 = 格距比例", _test_push_blocked)
	TestFramework.register_test("翻译员坐标口径 cone：格子去重、外沿端点 = 三格质心、引导线原样透传", _test_cone_overlay)
	TestFramework.register_test("翻译员坐标口径 飘字：位置 = 目标 axial", _test_control_floating_text)


# ========== 搭台 ==========

static func _record(actors: Array) -> PlaybackData.BattleRecord:
	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	record.world_snapshot = PlaybackData.WorldSnapshot.new()
	record.world_snapshot.position_formats = {PROBE_TYPE: "hex"}
	for spec_variant in actors:
		var spec: Dictionary = spec_variant
		var init := PlaybackData.ActorInitData.new()
		init.id = spec["id"]
		init.type = PROBE_TYPE
		init.display_name = spec.get("name", spec["id"])
		init.team = spec.get("team", 0)
		init.position = [spec.get("q", 0), spec.get("r", 0), 0]
		init.attributes = {"hp": spec.get("hp", 100.0), "max_hp": spec.get("max_hp", 100.0)}
		record.world_snapshot.actors.append(init)
	return record


static func _world(actors: Array) -> FrontendRenderWorld:
	var world := FrontendRenderWorld.new()
	world.initialize_from_replay(_record(actors))
	return world


# ========== 用例 ==========

func _test_projectile() -> void:
	var world := _world([{"id": "u1", "q": 0, "r": 0}, {"id": "u2", "q": 3, "r": -1}])
	var visualizer := FrontendProjectileVisualizer.new()
	var event := ProjectileEvents.create_projectile_launched_event("p1", "u1", Vector3(0, 0, 0), "arrow", 5.0, "u2", Vector3(3, -1, 0))
	var actions := visualizer.translate(event, world.as_context())
	TestFramework.assert_equal(1, actions.size())
	var card := actions[0] as FrontendProjectileAction
	TestFramework.assert_true(card.start_position.is_equal_approx(Vector2(0.0, 0.0)))
	TestFramework.assert_true(card.target_position.is_equal_approx(Vector2(3.0, -1.0)))
	# 逻辑平面距离 sqrt(10)，5 单位每秒
	TestFramework.assert_near(card.duration, sqrt(10.0) / 5.0 * 1000.0, 0.01)
	TestFramework.assert_equal(FrontendProjectileAction.ProjectileType.ARROW, card.projectile_type)

	# 快弹夹到 300 ms 下限
	var fast := ProjectileEvents.create_projectile_launched_event("p2", "u1", Vector3(0, 0, 0), "fireball", 200.0, "u2", Vector3(3, -1, 0))
	var fast_card := visualizer.translate(fast, world.as_context())[0] as FrontendProjectileAction
	TestFramework.assert_near(fast_card.duration, 300.0)
	TestFramework.assert_equal(FrontendProjectileAction.ProjectileType.FIREBALL, fast_card.projectile_type)

	# 账本没有的 actor：读事件字段前两分量（逻辑层给的 Vector3(q, r, 0)）
	var ghost := ProjectileEvents.create_projectile_launched_event("p3", "nobody", Vector3(1, 1, 0), "arrow", 5.0, "ghost", Vector3(2, 2, 0))
	var ghost_card := visualizer.translate(ghost, world.as_context())[0] as FrontendProjectileAction
	TestFramework.assert_true(ghost_card.start_position.is_equal_approx(Vector2(1.0, 1.0)))
	TestFramework.assert_true(ghost_card.target_position.is_equal_approx(Vector2(2.0, 2.0)))

	# 在飞中的发射者：起点取插值 axial（浮点）
	var move := FrontendMoveAction.new("u1", HexCoord.new(0, 0), HexCoord.new(2, 0), 500.0, FrontendVisualAction.EasingType.LINEAR)
	var active := FrontendActionScheduler.ActiveAction.new("m", move)
	active.progress = 0.5
	active.is_delaying = false
	var batch: Array[FrontendActionScheduler.ActiveAction] = [active]
	world.apply_actions(batch)
	var flying := visualizer.translate(event, world.as_context())[0] as FrontendProjectileAction
	TestFramework.assert_true(flying.start_position.is_equal_approx(Vector2(1.0, 0.0)))


func _test_push_blocked() -> void:
	var visualizer := FrontendPushBlockedVisualizer.new()
	var context := _world([{"id": "u1"}]).as_context()
	var event := BattleEvents.PushBlockedEvent.create("u1", {"q": 0, "r": 0}, {"q": 1, "r": -1}, "edge", "", "u2").to_dict()
	var actions := visualizer.translate(event, context)
	TestFramework.assert_equal(1, actions.size())
	var bump := actions[0] as FrontendBumpAction
	TestFramework.assert_true(bump.direction.is_equal_approx(Vector2(1.0, -1.0)), "axial 一步不归一化")
	TestFramework.assert_near(bump.max_offset, 0.30)
	TestFramework.assert_true(bump.squish_enabled)
	# t = 0.30 冲到峰值：偏移 = 一步 × 0.30；完成回零
	TestFramework.assert_true(bump.get_offset(0.30).is_equal_approx(Vector2(0.30, -0.30)))
	TestFramework.assert_true(bump.get_offset(1.0).is_equal_approx(Vector2.ZERO))
	TestFramework.assert_true(bump.get_squish(1.0).is_equal_approx(Vector2.ONE))

	# 同格：noop
	var same := BattleEvents.PushBlockedEvent.create("u1", {"q": 0, "r": 0}, {"q": 0, "r": 0}, "edge", "", "u2").to_dict()
	TestFramework.assert_equal(0, visualizer.translate(same, context).size())


func _test_cone_overlay() -> void:
	var visualizer := FrontendStageCueVisualizer.new()
	var context := _world([{"id": "u1"}]).as_context()
	var targets: Array[String] = []

	var grid_params := {"checked_coords": [{"q": 0, "r": 0}, {"q": 1, "r": 0}, {"q": 0, "r": 0}]}
	var grid_event := GameEvent.StageCue.create("u1", targets, HexBattleCues.GRID_CONE_CAST, grid_params).to_dict()
	var actions := visualizer.translate(grid_event, context)
	TestFramework.assert_equal(1, actions.size())
	var overlay := actions[0] as FrontendConeDebugOverlayAction
	# 去重
	TestFramework.assert_equal(2, overlay.cells.size())
	TestFramework.assert_true(overlay.cells[0].is_equal_approx(Vector2(0.0, 0.0)))
	TestFramework.assert_true(overlay.cells[1].is_equal_approx(Vector2(1.0, 0.0)))
	# 两格 12 条边，共用的那条各自跳过 → 外沿 10 条
	TestFramework.assert_equal(10, overlay.boundary_segments.size())
	# (0,0) 的 side 0 邻格 (1,0) 在区域内跳过；side 1 邻格 (1,-1) 在外 →
	# 端点 = 与 (1,0) / (0,-1) 各自共用的角点 = 三格中心质心
	var first := overlay.boundary_segments[0]
	TestFramework.assert_true(first[0].is_equal_approx(Vector2(2.0 / 3.0, -1.0 / 3.0)))
	TestFramework.assert_true(first[1].is_equal_approx(Vector2(1.0 / 3.0, -2.0 / 3.0)))
	TestFramework.assert_equal(0, overlay.guide_segments.size())
	TestFramework.assert_true(overlay.fill_color.is_equal_approx(FrontendStageCueVisualizer.CONE_DEBUG_FILL_COLOR_GRID))

	var angle_params := {
		"checked_coords": [{"q": 1, "r": 0}],
		"edge_segments": [
			{"start": {"x": 0.0, "y": 0.0}, "end": {"x": 3.0, "y": 4.0}},
			{"start": {"x": 1.0, "y": 1.0}, "end": {"x": 1.0, "y": 1.0}},
		],
	}
	var angle_event := GameEvent.StageCue.create("u1", targets, HexBattleCues.ANGLE_CONE_CAST, angle_params).to_dict()
	var angle_overlay := visualizer.translate(angle_event, context)[0] as FrontendConeDebugOverlayAction
	TestFramework.assert_equal(1, angle_overlay.cells.size())
	TestFramework.assert_true(angle_overlay.boundary_segments.is_empty(), "angle cone 不出格子外沿")
	TestFramework.assert_true(angle_overlay.guide_segments.size() == 1, "零长度引导线丢弃")
	TestFramework.assert_true(angle_overlay.guide_segments[0][0].is_equal_approx(Vector2(0.0, 0.0)))
	TestFramework.assert_true(angle_overlay.guide_segments[0][1].is_equal_approx(Vector2(3.0, 4.0)))
	TestFramework.assert_true(angle_overlay.fill_color.is_equal_approx(FrontendStageCueVisualizer.CONE_DEBUG_FILL_COLOR_ANGLE))


func _test_control_floating_text() -> void:
	var visualizer := FrontendStageCueVisualizer.new()
	var context := _world([{"id": "u1"}, {"id": "u2", "q": 2, "r": -1}]).as_context()
	var targets: Array[String] = ["u2"]
	var event := GameEvent.StageCue.create("u1", targets, HexBattleCues.CONTROL_STUNNED).to_dict()
	var actions := visualizer.translate(event, context)
	TestFramework.assert_equal(1, actions.size())
	var text := actions[0] as FrontendFloatingTextAction
	TestFramework.assert_true(text.position.is_equal_approx(Vector2(2.0, -1.0)))
	TestFramework.assert_equal("u2", text.actor_id)
