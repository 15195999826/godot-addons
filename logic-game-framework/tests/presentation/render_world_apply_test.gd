extends Node

## FrontendRenderWorld 记账半边（卡片 × 进度 → 账本）的合同钉子
##
## 钉住合同：
## - hp delta 瞬时累到 target_hp 并夹到 [0, max_hp]，visual_hp 不动、等 tick_hp_lerp 追赶；只标脏，flush 才广播
## - 死亡 sticky：target_hp 落到 ≤ 0 那一刻 actor_died 发一次（transition-only），之后回血 is_alive 不翻回、不再发
## - tick_hp_lerp 指数收敛，贴近（< 0.5）即 snap，收敛后不再标脏
## - buff / shield ADD 追加到尾（首次 ADD 顺序稳定），同 id ADD 原位覆盖；UPDATE 只改 primary / current 且
##   同值 noop 不标脏、未知 id 忽略；REMOVE 找到即删、找不到 noop；缺 summary 的 ADD / UPDATE 忽略
## - bump 中途按曲线叠 offset / squish（逻辑平面 Vector2），progress 1 snap 回零位 / ONE
## - facing 瞬时写入 facing_direction
## - death 立即 is_alive=false、hp 归零、death_progress 跟 progress，当场广播 actor_state_changed
## - move 中途只改插值位置（context 取整可见；get_actor_axial / get_actor_position 给浮点在飞坐标），
##   progress 1 才落 actor.position 并当场广播
## - 延迟中的卡片跳过；飘字 / 攻击特效 / 投射物按 action id 各建一次，progress 1 移除；
##   程序化特效到期由 cleanup 归零


const PROBE_TYPE := "probe"


func _init() -> void:
	TestFramework.register_test("RenderWorld hp delta 累到 target_hp 夹上限，死亡 sticky 且 actor_died 只发一次", _test_hp_delta_death_sticky)
	TestFramework.register_test("RenderWorld tick_hp_lerp 指数收敛、贴近 snap、收敛后不标脏", _test_hp_lerp_converges)
	TestFramework.register_test("RenderWorld buff ADD/UPDATE/REMOVE 顺序契约与 noop guard", _test_buff_state_contract)
	TestFramework.register_test("RenderWorld shield ADD/UPDATE/REMOVE 顺序契约与 noop guard（UPDATE 只改 current）", _test_shield_state_contract)
	TestFramework.register_test("RenderWorld bump 中途叠 offset/squish，完成 snap 回零", _test_bump_snaps_back)
	TestFramework.register_test("RenderWorld facing 瞬时写入", _test_facing_instant)
	TestFramework.register_test("RenderWorld death 当场归零并广播，actor_died 只发一次", _test_death_action)
	TestFramework.register_test("RenderWorld move 中途只改插值位置，完成才落 position", _test_move_interpolates_then_settles)
	TestFramework.register_test("RenderWorld 延迟中的卡片不应用", _test_skips_delaying)
	TestFramework.register_test("RenderWorld 飘字按 action id 只创建一次", _test_floating_text_once_per_action_id)
	TestFramework.register_test("RenderWorld 程序化特效到期由 cleanup 归零", _test_procedural_effects_cleanup)
	TestFramework.register_test("RenderWorld 攻击特效 / 投射物按 action id 建一次、每次 apply 更新、完成移除", _test_attack_vfx_and_projectile_lifecycle)


# ========== 搭台 ==========

## 最小录像：position_formats 声明 hex，map_config 留空（本文件不碰世界坐标）。
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


static func _actor(world: FrontendRenderWorld, actor_id: String) -> FrontendActorRenderState:
	return world.get_actors_snapshot().get(actor_id)


## 直接按指定进度应用一张卡片（绕过 scheduler 的时钟，精确控制 progress）。
static func _apply(world: FrontendRenderWorld, action: FrontendVisualAction, progress: float, id: String = "a") -> void:
	var active := FrontendActionScheduler.ActiveAction.new(id, action)
	active.progress = progress
	active.is_delaying = false
	var batch: Array[FrontendActionScheduler.ActiveAction] = [active]
	world.apply_actions(batch)


static func _buff(actor_id: String, op: FrontendApplyBuffStateAction.Op, buff_id: String, primary: float) -> FrontendApplyBuffStateAction:
	var summary := FrontendBuffSummary.new()
	summary.id = buff_id
	summary.config_id = "cfg_" + buff_id
	summary.primary = primary
	return FrontendApplyBuffStateAction.new(actor_id, op, buff_id, summary)


static func _shield(actor_id: String, op: FrontendApplyShieldStateAction.Op, shield_id: String, current: float, capacity: float) -> FrontendApplyShieldStateAction:
	var summary := FrontendShieldSummary.new()
	summary.id = shield_id
	summary.config_id = "cfg_" + shield_id
	summary.current = current
	summary.capacity = capacity
	return FrontendApplyShieldStateAction.new(actor_id, op, shield_id, summary)


static func _buff_ids(world: FrontendRenderWorld, actor_id: String) -> String:
	var ids: Array[String] = []
	for buff in _actor(world, actor_id).buffs:
		ids.append(buff.id)
	return ",".join(ids)


static func _shield_ids(world: FrontendRenderWorld, actor_id: String) -> String:
	var ids: Array[String] = []
	for shield in _actor(world, actor_id).shields:
		ids.append(shield.id)
	return ",".join(ids)


## 把 actor_state_changed 广播记成 id 列表；flush 后清空以便逐段断言。
static func _record_changes(world: FrontendRenderWorld) -> Array[String]:
	var changed: Array[String] = []
	world.actor_state_changed.connect(func(actor_id: String, _state: FrontendActorRenderState) -> void:
		changed.append(actor_id))
	return changed


static func _record_deaths(world: FrontendRenderWorld) -> Array[String]:
	var died: Array[String] = []
	world.actor_died.connect(func(actor_id: String) -> void: died.append(actor_id))
	return died


# ========== 用例 ==========

func _test_hp_delta_death_sticky() -> void:
	var world := _world([{"id": "u1", "hp": 30.0, "max_hp": 100.0}])
	var died := _record_deaths(world)
	var changed := _record_changes(world)

	_apply(world, FrontendApplyHPDeltaAction.new("u1", -10.0), 1.0)
	var u1 := _actor(world, "u1")
	TestFramework.assert_near(u1.target_hp, 20.0)
	TestFramework.assert_near(u1.visual_hp, 30.0, 0.0001, "visual_hp 不随 delta 立刻跳，等 tick_hp_lerp")
	TestFramework.assert_true(u1.is_alive)
	TestFramework.assert_equal(0, changed.size())
	world.flush_dirty_actors()
	TestFramework.assert_equal("u1", ",".join(changed))
	changed.clear()
	world.flush_dirty_actors()
	# flush 清脏标记，再 flush 不重复广播
	TestFramework.assert_equal(0, changed.size())

	# 治疗封顶 max_hp
	_apply(world, FrontendApplyHPDeltaAction.new("u1", 500.0), 1.0)
	TestFramework.assert_near(_actor(world, "u1").target_hp, 100.0)

	# 致死：actor_died 当场发一次，不等 visual_hp 追上
	_apply(world, FrontendApplyHPDeltaAction.new("u1", -150.0), 1.0)
	u1 = _actor(world, "u1")
	TestFramework.assert_near(u1.target_hp, 0.0)
	TestFramework.assert_false(u1.is_alive)
	TestFramework.assert_true(u1.visual_hp > 0.0, "致死那一刻 visual_hp 仍在追赶途中")
	TestFramework.assert_equal("u1", ",".join(died))

	# 死亡 sticky：再治疗 target_hp 回升但 is_alive 不翻回，也不再发 actor_died
	_apply(world, FrontendApplyHPDeltaAction.new("u1", 40.0), 1.0)
	u1 = _actor(world, "u1")
	TestFramework.assert_near(u1.target_hp, 40.0)
	TestFramework.assert_false(u1.is_alive, "死亡 sticky：dead→alive 不支持")
	_apply(world, FrontendApplyHPDeltaAction.new("u1", -100.0), 1.0)
	TestFramework.assert_equal(1, died.size())

	# 未知 actor：noop
	_apply(world, FrontendApplyHPDeltaAction.new("ghost", -1.0), 1.0)
	TestFramework.assert_equal(1, world.get_actors_snapshot().size())


func _test_hp_lerp_converges() -> void:
	var world := _world([{"id": "u1", "hp": 100.0, "max_hp": 100.0}])
	_apply(world, FrontendApplyHPDeltaAction.new("u1", -50.0), 1.0)
	world.flush_dirty_actors()
	var changed := _record_changes(world)

	# 默认 hp_lerp_rate = 8 /s，dt = 0.1 s：追赶 1 - e^-0.8
	world.tick_hp_lerp(100.0)
	var expected := 100.0 - 50.0 * (1.0 - exp(-0.8))
	TestFramework.assert_near(_actor(world, "u1").visual_hp, expected, 0.001)
	world.flush_dirty_actors()
	TestFramework.assert_equal("u1", ",".join(changed))
	changed.clear()

	for _i in range(50):
		world.tick_hp_lerp(100.0)
	TestFramework.assert_equal(50.0, _actor(world, "u1").visual_hp)
	world.flush_dirty_actors()
	changed.clear()

	# 已收敛：再 tick 不标脏
	world.tick_hp_lerp(100.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())


func _test_buff_state_contract() -> void:
	var world := _world([{"id": "u1"}])
	var changed := _record_changes(world)
	var ADD := FrontendApplyBuffStateAction.Op.ADD
	var UPDATE := FrontendApplyBuffStateAction.Op.UPDATE
	var REMOVE := FrontendApplyBuffStateAction.Op.REMOVE

	_apply(world, _buff("u1", ADD, "b1", 1.0), 1.0)
	_apply(world, _buff("u1", ADD, "b2", 2.0), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	world.flush_dirty_actors()
	# 同一 actor 多张卡片 flush 只广播一次
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# 同 id ADD：原位覆盖，顺序不变
	_apply(world, _buff("u1", ADD, "b1", 5.0), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	TestFramework.assert_near(_actor(world, "u1").buffs[0].primary, 5.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# UPDATE 同值：noop guard，不标脏
	_apply(world, _buff("u1", UPDATE, "b2", 2.0), 1.0)
	world.flush_dirty_actors()
	# primary 没变不标脏
	TestFramework.assert_equal(0, changed.size())

	# UPDATE 变值：只改 primary，标脏
	_apply(world, _buff("u1", UPDATE, "b2", 3.0), 1.0)
	TestFramework.assert_near(_actor(world, "u1").buffs[1].primary, 3.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# UPDATE 未知 id：忽略，不新增不标脏
	_apply(world, _buff("u1", UPDATE, "b9", 1.0), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# 缺 summary 的 ADD / UPDATE：忽略
	_apply(world, FrontendApplyBuffStateAction.new("u1", ADD, "b3", null), 1.0)
	_apply(world, FrontendApplyBuffStateAction.new("u1", UPDATE, "b1", null), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	TestFramework.assert_near(_actor(world, "u1").buffs[0].primary, 5.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# REMOVE 中间那条：其余顺序保持
	_apply(world, _buff("u1", ADD, "b3", 0.0), 1.0)
	_apply(world, FrontendApplyBuffStateAction.new("u1", REMOVE, "b2", null), 1.0)
	TestFramework.assert_equal("b1,b3", _buff_ids(world, "u1"))
	world.flush_dirty_actors()
	changed.clear()

	# REMOVE 未知：noop 不标脏
	_apply(world, FrontendApplyBuffStateAction.new("u1", REMOVE, "b2", null), 1.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# 未知 actor：noop
	_apply(world, _buff("ghost", ADD, "b1", 1.0), 1.0)
	TestFramework.assert_equal(1, world.get_actors_snapshot().size())


func _test_shield_state_contract() -> void:
	var world := _world([{"id": "u1"}])
	var changed := _record_changes(world)
	var ADD := FrontendApplyShieldStateAction.Op.ADD
	var UPDATE := FrontendApplyShieldStateAction.Op.UPDATE
	var REMOVE := FrontendApplyShieldStateAction.Op.REMOVE

	_apply(world, _shield("u1", ADD, "s1", 30.0, 30.0), 1.0)
	_apply(world, _shield("u1", ADD, "s2", 50.0, 50.0), 1.0)
	TestFramework.assert_equal("s1,s2", _shield_ids(world, "u1"))
	world.flush_dirty_actors()
	changed.clear()

	# 同 id ADD 原位覆盖
	_apply(world, _shield("u1", ADD, "s1", 10.0, 10.0), 1.0)
	TestFramework.assert_equal("s1,s2", _shield_ids(world, "u1"))
	TestFramework.assert_near(_actor(world, "u1").shields[0].capacity, 10.0)

	# UPDATE 同 current：noop guard
	world.flush_dirty_actors()
	changed.clear()
	_apply(world, _shield("u1", UPDATE, "s2", 50.0, 999.0), 1.0)
	world.flush_dirty_actors()
	# current 没变不标脏
	TestFramework.assert_equal(0, changed.size())
	TestFramework.assert_near(_actor(world, "u1").shields[1].capacity, 50.0, 0.0001, "UPDATE 不碰 capacity")

	# UPDATE 变 current：只改 current，capacity 不动
	_apply(world, _shield("u1", UPDATE, "s2", 20.0, 999.0), 1.0)
	TestFramework.assert_near(_actor(world, "u1").shields[1].current, 20.0)
	TestFramework.assert_near(_actor(world, "u1").shields[1].capacity, 50.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# UPDATE 未知 id / 缺 summary：忽略
	_apply(world, _shield("u1", UPDATE, "s9", 1.0, 1.0), 1.0)
	_apply(world, FrontendApplyShieldStateAction.new("u1", ADD, "s3", null), 1.0)
	TestFramework.assert_equal("s1,s2", _shield_ids(world, "u1"))
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# REMOVE：找到即删，找不到 noop
	_apply(world, FrontendApplyShieldStateAction.new("u1", REMOVE, "s1", null), 1.0)
	TestFramework.assert_equal("s2", _shield_ids(world, "u1"))
	world.flush_dirty_actors()
	changed.clear()
	_apply(world, FrontendApplyShieldStateAction.new("u1", REMOVE, "s1", null), 1.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())


func _test_bump_snaps_back() -> void:
	var world := _world([{"id": "u1"}])
	var bump := FrontendBumpAction.new("u1", Vector2(1.0, 0.0), 0.3, 280.0, true)

	_apply(world, bump, 0.4)
	var u1 := _actor(world, "u1")
	TestFramework.assert_true(u1.bump_offset.length() > 0.0, "中途有位移")
	TestFramework.assert_true(u1.bump_offset.is_equal_approx(bump.get_offset(0.4)))
	TestFramework.assert_true(u1.bump_squish.is_equal_approx(bump.get_squish(0.4)))
	TestFramework.assert_false(u1.bump_squish.is_equal_approx(Vector2.ONE), "撞击峰值段有挤压")

	_apply(world, bump, 1.0)
	u1 = _actor(world, "u1")
	TestFramework.assert_true(u1.bump_offset.is_equal_approx(Vector2.ZERO), "完成 snap 回零位")
	TestFramework.assert_true(u1.bump_squish.is_equal_approx(Vector2.ONE), "完成 squish 回 ONE")

	# 不挤压的 bump 只位移
	var flat := FrontendBumpAction.new("u1", Vector2(0.0, 1.0), 0.3, 280.0, false)
	_apply(world, flat, 0.4)
	u1 = _actor(world, "u1")
	TestFramework.assert_true(u1.bump_offset.length() > 0.0)
	TestFramework.assert_true(u1.bump_squish.is_equal_approx(Vector2.ONE))


func _test_facing_instant() -> void:
	var world := _world([{"id": "u1"}])
	var changed := _record_changes(world)
	TestFramework.assert_equal(0, _actor(world, "u1").facing_direction)
	_apply(world, FrontendApplyFacingStateAction.new("u1", 4), 1.0)
	TestFramework.assert_equal(4, _actor(world, "u1").facing_direction)
	# 只标脏
	TestFramework.assert_equal(0, changed.size())
	world.flush_dirty_actors()
	TestFramework.assert_equal("u1", ",".join(changed))
	_apply(world, FrontendApplyFacingStateAction.new("ghost", 2), 1.0)
	TestFramework.assert_equal(4, _actor(world, "u1").facing_direction)


func _test_death_action() -> void:
	var world := _world([{"id": "u1", "hp": 40.0}])
	var died := _record_deaths(world)
	var changed := _record_changes(world)
	var death := FrontendDeathAction.new("u1", 1000.0)

	_apply(world, death, 0.3)
	var u1 := _actor(world, "u1")
	TestFramework.assert_false(u1.is_alive)
	TestFramework.assert_near(u1.visual_hp, 0.0)
	TestFramework.assert_near(u1.target_hp, 0.0)
	TestFramework.assert_near(u1.death_progress, 0.3)
	TestFramework.assert_equal("u1", ",".join(died))
	# death 当场广播，不等 flush
	TestFramework.assert_equal("u1", ",".join(changed))

	_apply(world, death, 1.0)
	TestFramework.assert_near(_actor(world, "u1").death_progress, 1.0)
	# actor_died transition-only
	TestFramework.assert_equal(1, died.size())
	TestFramework.assert_equal(2, changed.size())


func _test_move_interpolates_then_settles() -> void:
	var world := _world([{"id": "u1", "q": 0, "r": 0}])
	var changed := _record_changes(world)
	var move := FrontendMoveAction.new("u1", HexCoord.new(0, 0), HexCoord.new(2, 0), 500.0, FrontendVisualAction.EasingType.LINEAR)

	_apply(world, move, 0.5)
	var hex := world.as_context().get_actor_hex_position("u1")
	TestFramework.assert_equal(1, hex.q)
	TestFramework.assert_equal(0, hex.r)
	# 在飞浮点坐标：账本与只读视图同一口径
	TestFramework.assert_true(world.get_actor_axial("u1").is_equal_approx(Vector2(1.0, 0.0)))
	TestFramework.assert_true(world.as_context().get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	# 中途 actor.position 不动
	TestFramework.assert_equal(0, _actor(world, "u1").position.q)
	# 中途不广播
	TestFramework.assert_equal(0, changed.size())

	_apply(world, move, 0.2)
	# 0.4 取整回 0，浮点照旧
	TestFramework.assert_equal(0, world.as_context().get_actor_hex_position("u1").q)
	TestFramework.assert_true(world.get_actor_axial("u1").is_equal_approx(Vector2(0.4, 0.0)))

	_apply(world, move, 1.0)
	TestFramework.assert_equal(2, _actor(world, "u1").position.q)
	TestFramework.assert_equal(2, world.as_context().get_actor_hex_position("u1").q)
	TestFramework.assert_true(world.get_actor_axial("u1").is_equal_approx(Vector2(2.0, 0.0)))
	# 完成当场广播
	TestFramework.assert_equal("u1", ",".join(changed))


func _test_skips_delaying() -> void:
	var world := _world([{"id": "u1"}])
	var active := FrontendActionScheduler.ActiveAction.new("d", FrontendApplyFacingStateAction.new("u1", 3))
	active.is_delaying = true
	active.progress = 0.0
	var batch: Array[FrontendActionScheduler.ActiveAction] = [active]
	world.apply_actions(batch)
	# 延迟中的卡片不应用
	TestFramework.assert_equal(0, _actor(world, "u1").facing_direction)


func _test_floating_text_once_per_action_id() -> void:
	var world := _world([{"id": "u1"}])
	var created: Array[String] = []
	world.floating_text_created.connect(func(data: FrontendRenderData.FloatingText) -> void: created.append(data.id))
	var text := FrontendFloatingTextAction.new("u1", "-5", Color.WHITE, Vector2.ZERO, FrontendFloatingTextAction.FloatingTextStyle.NORMAL, 1000.0)

	_apply(world, text, 0.1, "ft1")
	_apply(world, text, 0.5, "ft1")
	# 同一 action id 只创建一次
	TestFramework.assert_equal("ft1", ",".join(created))
	_apply(world, text, 0.1, "ft2")
	TestFramework.assert_equal("ft1,ft2", ",".join(created))


func _test_procedural_effects_cleanup() -> void:
	var world := _world([{"id": "u1"}])
	var flash := FrontendProceduralVFXAction.new(FrontendProceduralVFXAction.EffectType.HIT_FLASH, 300.0, "u1")
	_apply(world, flash, 0.5, "fx1")
	TestFramework.assert_near(_actor(world, "u1").flash_progress, 1.0, 0.0001, "闪白强度中点最亮")
	world.cleanup(world.get_world_time())
	TestFramework.assert_near(_actor(world, "u1").flash_progress, 1.0, 0.0001, "未到期不清")
	world.advance_time(300)
	world.cleanup(world.get_world_time())
	TestFramework.assert_near(_actor(world, "u1").flash_progress, 0.0, 0.0001, "到期归零")

	var shake := FrontendProceduralVFXAction.new(FrontendProceduralVFXAction.EffectType.SHAKE, 200.0, "", 5.0)
	_apply(world, shake, 0.25, "fx2")
	TestFramework.assert_true(world.get_screen_shake_offset().is_equal_approx(shake.get_shake_offset(0.25)))
	TestFramework.assert_true(world.get_screen_shake_offset().length() > 0.0)
	world.cleanup(world.get_world_time())
	TestFramework.assert_true(world.get_screen_shake_offset().length() > 0.0, "未到期震屏保持")
	world.advance_time(200)
	world.cleanup(world.get_world_time())
	TestFramework.assert_true(world.get_screen_shake_offset().is_equal_approx(Vector2.ZERO), "到期震屏归零")

	var tint := FrontendProceduralVFXAction.new(FrontendProceduralVFXAction.EffectType.COLOR_TINT, 400.0, "u1", 1.0, Color.RED)
	_apply(world, tint, 0.5, "fx3")
	TestFramework.assert_true(_actor(world, "u1").tint_color.is_equal_approx(Color.RED))
	_apply(world, tint, 1.0, "fx3")
	TestFramework.assert_true(_actor(world, "u1").tint_color.is_equal_approx(Color.WHITE), "progress 1 染色回白")


func _test_attack_vfx_and_projectile_lifecycle() -> void:
	var world := _world([{"id": "u1"}, {"id": "u2", "q": 1}])
	var vfx_log: Array[String] = []
	world.attack_vfx_created.connect(func(data: FrontendRenderData.AttackVfx) -> void: vfx_log.append("create:" + data.id))
	world.attack_vfx_updated.connect(func(vfx_id: String, progress: float, _scale: float, _alpha: float) -> void:
		vfx_log.append("update:%s@%.1f" % [vfx_id, progress]))
	world.attack_vfx_removed.connect(func(vfx_id: String) -> void: vfx_log.append("remove:" + vfx_id))
	var vfx := FrontendAttackVFXAction.new("u1", "u2", Vector2.ZERO, Vector2(1.0, 0.0), 300.0)
	_apply(world, vfx, 0.0, "v1")
	_apply(world, vfx, 0.5, "v1")
	_apply(world, vfx, 1.0, "v1")
	TestFramework.assert_equal("create:v1,update:v1@0.0,update:v1@0.5,update:v1@1.0,remove:v1", ",".join(vfx_log))

	var proj_log: Array[String] = []
	world.projectile_created.connect(func(data: FrontendRenderData.Projectile) -> void: proj_log.append("create:" + data.id))
	# lambda 按值捕获局部变量，位置用数组收
	var positions: Array[Vector2] = []
	world.projectile_updated.connect(func(projectile_id: String, pos: Vector2) -> void:
		proj_log.append("update:" + projectile_id)
		positions.append(pos))
	world.projectile_removed.connect(func(projectile_id: String) -> void: proj_log.append("remove:" + projectile_id))
	var projectile := FrontendProjectileAction.new("p_logic", "u1", Vector2.ZERO, Vector2(2.0, 0.0), 400.0, "u2")
	_apply(world, projectile, 0.0, "p1")
	_apply(world, projectile, 0.5, "p1")
	TestFramework.assert_true(positions[1].is_equal_approx(Vector2(1.0, 0.0)), "更新信号带逻辑平面插值位置")
	_apply(world, projectile, 1.0, "p1")
	TestFramework.assert_equal("create:p1,update:p1,update:p1,update:p1,remove:p1", ",".join(proj_log))
