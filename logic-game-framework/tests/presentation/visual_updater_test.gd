extends Node

## VisualUpdater 记账半边（卡片 × 进度 → 账本）的合同钉子
##
## 钉住合同：
## - hp delta 瞬时累到 target_hp 并夹到 [0, max_hp]，visual_hp 不动、等 tick_time 追赶；只标脏，flush 才广播
## - 死亡 sticky：target_hp 落到 ≤ 0 那一刻 actor_died 发一次（transition-only），之后回血 is_alive 不翻回、不再发
## - tick_time 的 hp lerp 指数收敛，贴近（< 0.5）即 snap，收敛后不再标脏
## - buff / shield ADD 追加到尾（首次 ADD 顺序稳定），同 id ADD 原位覆盖；UPDATE 只改 primary / current 且
##   同值 noop 不标脏、未知 id 忽略；REMOVE 找到即删、找不到 noop；缺 summary 的 ADD / UPDATE 忽略
## - bump 中途按曲线叠 offset / squish（逻辑平面 Vector2），progress 1 snap 回零位 / ONE
## - facing 瞬时写入 facing_direction
## - death 立即 is_alive=false、hp 归零、death_progress 跟 progress，当场广播 actor_state_changed
## - move 中途只改插值位置（get_actor_position 给浮点在飞坐标），progress 1 才落 actor.position 并当场广播
## - 延迟中的卡片跳过；飘字 / 攻击特效 / 投射物按卡片 id 各入账一次；攻击特效 / 投射物每次 apply 发
##   effect_updated、progress 1 发 effect_removed；飘字到期由账本静默忘记（不发 removed）
## - 程序化特效到期由 tick_time 归零
## - 扩展缝：register_handler 登记的私有 kind 走项目自己的记账函数；未登记的 kind 是断言错误


const PROBE_TYPE := "probe"


## 项目私有卡片范例：自定义 kind + 自带记账函数
class ProbeAction extends VisualAction:
	const KIND: StringName = &"probe"
	var applied: int = 0

	func _init(p_actor_id: String, p_duration: float) -> void:
		super._init(KIND, p_duration, 0.0)
		actor_id = p_actor_id

	static func apply(state: VisualState, action: VisualAction, _progress: float, action_id: String) -> void:
		var probe := action as ProbeAction
		probe.applied += 1
		if state.has_effect(KIND, action_id):
			return
		var payload := VisualEffectPayload.Effect.new()
		payload.id = action_id
		payload.duration = probe.duration
		state.spawn_effect(KIND, payload)


func _init() -> void:
	TestFramework.register_test("VisualUpdater hp delta 累到 target_hp 夹上限，死亡 sticky 且 actor_died 只发一次", _test_hp_delta_death_sticky)
	TestFramework.register_test("VisualUpdater tick_time hp lerp 指数收敛、贴近 snap、收敛后不标脏", _test_hp_lerp_converges)
	TestFramework.register_test("VisualUpdater buff ADD/UPDATE/REMOVE 顺序契约与 noop guard", _test_buff_state_contract)
	TestFramework.register_test("VisualUpdater shield ADD/UPDATE/REMOVE 顺序契约与 noop guard（UPDATE 只改 current）", _test_shield_state_contract)
	TestFramework.register_test("VisualUpdater bump 中途叠 offset/squish，完成 snap 回零", _test_bump_snaps_back)
	TestFramework.register_test("VisualUpdater facing 瞬时写入", _test_facing_instant)
	TestFramework.register_test("VisualUpdater death 当场归零并广播，actor_died 只发一次", _test_death_action)
	TestFramework.register_test("VisualUpdater move 中途只改插值位置，完成才落 position", _test_move_interpolates_then_settles)
	TestFramework.register_test("VisualUpdater 延迟中的卡片不应用", _test_skips_delaying)
	TestFramework.register_test("VisualUpdater 飘字按卡片 id 只入账一次，到期静默忘记不发 removed", _test_floating_text_once_then_expires)
	TestFramework.register_test("VisualUpdater 程序化特效到期由 tick_time 归零", _test_procedural_effects_cleanup)
	TestFramework.register_test("VisualUpdater 攻击特效 / 投射物按卡片 id 建一次、每次 apply 更新、完成移除", _test_attack_vfx_and_projectile_lifecycle)
	TestFramework.register_test("VisualUpdater register_handler 私有 kind 走项目自己的记账函数", _test_private_kind_handler)


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


static func _world(actors: Array) -> VisualState:
	var world := VisualState.new()
	world.initialize_from_replay(_record(actors))
	return world


static func _actor(world: VisualState, actor_id: String) -> ActorVisualState:
	return world.get_actors_snapshot().get(actor_id)


## 直接按指定进度应用一张卡片（绕过步进器的时钟，精确控制 progress）。
static func _apply(world: VisualState, updater: VisualUpdater, action: VisualAction, progress: float, id: String = "a") -> void:
	var active := ActionStepper.ActiveAction.new(id, action)
	active.progress = progress
	active.is_delaying = false
	var batch: Array[ActionStepper.ActiveAction] = [active]
	updater.apply_actions(world, batch)


static func _buff(actor_id: String, op: VisualBuffStateAction.Op, buff_id: String, primary: float) -> VisualBuffStateAction:
	var summary := BuffSummary.new()
	summary.id = buff_id
	summary.config_id = "cfg_" + buff_id
	summary.primary = primary
	return VisualBuffStateAction.new(actor_id, op, buff_id, summary)


static func _shield(actor_id: String, op: VisualShieldStateAction.Op, shield_id: String, current: float, capacity: float) -> VisualShieldStateAction:
	var summary := ShieldSummary.new()
	summary.id = shield_id
	summary.config_id = "cfg_" + shield_id
	summary.current = current
	summary.capacity = capacity
	return VisualShieldStateAction.new(actor_id, op, shield_id, summary)


static func _buff_ids(world: VisualState, actor_id: String) -> String:
	var ids: Array[String] = []
	for buff in _actor(world, actor_id).buffs:
		ids.append(buff.id)
	return ",".join(ids)


static func _shield_ids(world: VisualState, actor_id: String) -> String:
	var ids: Array[String] = []
	for shield in _actor(world, actor_id).shields:
		ids.append(shield.id)
	return ",".join(ids)


## 把 actor_state_changed 广播记成 id 列表；flush 后清空以便逐段断言。
static func _record_changes(world: VisualState) -> Array[String]:
	var changed: Array[String] = []
	world.actor_state_changed.connect(func(actor_id: String, _state: ActorVisualState) -> void:
		changed.append(actor_id))
	return changed


static func _record_deaths(world: VisualState) -> Array[String]:
	var died: Array[String] = []
	world.actor_died.connect(func(actor_id: String) -> void: died.append(actor_id))
	return died


## 把一次性效果信号记成 "create:<kind>:<id>" / "update:<kind>:<id>@<progress>" / "remove:<kind>:<id>"
static func _record_effects(world: VisualState) -> Array[String]:
	var log: Array[String] = []
	world.effect_spawned.connect(func(kind: StringName, payload: VisualEffectPayload.Effect) -> void:
		log.append("create:%s:%s" % [kind, payload.id]))
	world.effect_updated.connect(func(kind: StringName, effect_id: String, progress: float, _payload: VisualEffectPayload.Effect) -> void:
		log.append("update:%s:%s@%.1f" % [kind, effect_id, progress]))
	world.effect_removed.connect(func(kind: StringName, effect_id: String) -> void:
		log.append("remove:%s:%s" % [kind, effect_id]))
	return log


# ========== 用例 ==========

func _test_hp_delta_death_sticky() -> void:
	var world := _world([{"id": "u1", "hp": 30.0, "max_hp": 100.0}])
	var updater := VisualUpdater.new()
	var died := _record_deaths(world)
	var changed := _record_changes(world)

	_apply(world, updater, VisualHpDeltaAction.new("u1", -10.0), 1.0)
	var u1 := _actor(world, "u1")
	TestFramework.assert_near(u1.target_hp, 20.0)
	TestFramework.assert_near(u1.visual_hp, 30.0, 0.0001, "visual_hp 不随 delta 立刻跳，等 tick_time")
	TestFramework.assert_true(u1.is_alive)
	TestFramework.assert_equal(0, changed.size())
	world.flush_dirty_actors()
	TestFramework.assert_equal("u1", ",".join(changed))
	changed.clear()
	world.flush_dirty_actors()
	# flush 清脏标记，再 flush 不重复广播
	TestFramework.assert_equal(0, changed.size())

	# 治疗封顶 max_hp
	_apply(world, updater, VisualHpDeltaAction.new("u1", 500.0), 1.0)
	TestFramework.assert_near(_actor(world, "u1").target_hp, 100.0)

	# 致死：actor_died 当场发一次，不等 visual_hp 追上
	_apply(world, updater, VisualHpDeltaAction.new("u1", -150.0), 1.0)
	u1 = _actor(world, "u1")
	TestFramework.assert_near(u1.target_hp, 0.0)
	TestFramework.assert_false(u1.is_alive)
	TestFramework.assert_true(u1.visual_hp > 0.0, "致死那一刻 visual_hp 仍在追赶途中")
	TestFramework.assert_equal("u1", ",".join(died))

	# 死亡 sticky：再治疗 target_hp 回升但 is_alive 不翻回，也不再发 actor_died
	_apply(world, updater, VisualHpDeltaAction.new("u1", 40.0), 1.0)
	u1 = _actor(world, "u1")
	TestFramework.assert_near(u1.target_hp, 40.0)
	TestFramework.assert_false(u1.is_alive, "死亡 sticky：dead→alive 不支持")
	_apply(world, updater, VisualHpDeltaAction.new("u1", -100.0), 1.0)
	TestFramework.assert_equal(1, died.size())

	# 未知 actor：noop
	_apply(world, updater, VisualHpDeltaAction.new("ghost", -1.0), 1.0)
	TestFramework.assert_equal(1, world.get_actors_snapshot().size())


func _test_hp_lerp_converges() -> void:
	var world := _world([{"id": "u1", "hp": 100.0, "max_hp": 100.0}])
	var updater := VisualUpdater.new()
	_apply(world, updater, VisualHpDeltaAction.new("u1", -50.0), 1.0)
	world.flush_dirty_actors()
	var changed := _record_changes(world)

	# 默认 hp_lerp_rate = 8 /s，dt = 0.1 s：追赶 1 - e^-0.8
	updater.tick_time(world, 100.0)
	var expected := 100.0 - 50.0 * (1.0 - exp(-0.8))
	TestFramework.assert_near(_actor(world, "u1").visual_hp, expected, 0.001)
	world.flush_dirty_actors()
	TestFramework.assert_equal("u1", ",".join(changed))
	changed.clear()

	for _i in range(50):
		updater.tick_time(world, 100.0)
	TestFramework.assert_equal(50.0, _actor(world, "u1").visual_hp)
	world.flush_dirty_actors()
	changed.clear()

	# 已收敛：再 tick 不标脏
	updater.tick_time(world, 100.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())


func _test_buff_state_contract() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	var changed := _record_changes(world)
	var ADD := VisualBuffStateAction.Op.ADD
	var UPDATE := VisualBuffStateAction.Op.UPDATE
	var REMOVE := VisualBuffStateAction.Op.REMOVE

	_apply(world, updater, _buff("u1", ADD, "b1", 1.0), 1.0)
	_apply(world, updater, _buff("u1", ADD, "b2", 2.0), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	world.flush_dirty_actors()
	# 同一 actor 多张卡片 flush 只广播一次
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# 同 id ADD：原位覆盖，顺序不变
	_apply(world, updater, _buff("u1", ADD, "b1", 5.0), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	TestFramework.assert_near(_actor(world, "u1").buffs[0].primary, 5.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# UPDATE 同值：noop guard，不标脏
	_apply(world, updater, _buff("u1", UPDATE, "b2", 2.0), 1.0)
	world.flush_dirty_actors()
	# primary 没变不标脏
	TestFramework.assert_equal(0, changed.size())

	# UPDATE 变值：只改 primary，标脏
	_apply(world, updater, _buff("u1", UPDATE, "b2", 3.0), 1.0)
	TestFramework.assert_near(_actor(world, "u1").buffs[1].primary, 3.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# UPDATE 未知 id：忽略，不新增不标脏
	_apply(world, updater, _buff("u1", UPDATE, "b9", 1.0), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# 缺 summary 的 ADD / UPDATE：忽略
	_apply(world, updater, VisualBuffStateAction.new("u1", ADD, "b3", null), 1.0)
	_apply(world, updater, VisualBuffStateAction.new("u1", UPDATE, "b1", null), 1.0)
	TestFramework.assert_equal("b1,b2", _buff_ids(world, "u1"))
	TestFramework.assert_near(_actor(world, "u1").buffs[0].primary, 5.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# REMOVE 中间那条：其余顺序保持
	_apply(world, updater, _buff("u1", ADD, "b3", 0.0), 1.0)
	_apply(world, updater, VisualBuffStateAction.new("u1", REMOVE, "b2", null), 1.0)
	TestFramework.assert_equal("b1,b3", _buff_ids(world, "u1"))
	world.flush_dirty_actors()
	changed.clear()

	# REMOVE 未知：noop 不标脏
	_apply(world, updater, VisualBuffStateAction.new("u1", REMOVE, "b2", null), 1.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# 未知 actor：noop
	_apply(world, updater, _buff("ghost", ADD, "b1", 1.0), 1.0)
	TestFramework.assert_equal(1, world.get_actors_snapshot().size())


func _test_shield_state_contract() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	var changed := _record_changes(world)
	var ADD := VisualShieldStateAction.Op.ADD
	var UPDATE := VisualShieldStateAction.Op.UPDATE
	var REMOVE := VisualShieldStateAction.Op.REMOVE

	_apply(world, updater, _shield("u1", ADD, "s1", 30.0, 30.0), 1.0)
	_apply(world, updater, _shield("u1", ADD, "s2", 50.0, 50.0), 1.0)
	TestFramework.assert_equal("s1,s2", _shield_ids(world, "u1"))
	world.flush_dirty_actors()
	changed.clear()

	# 同 id ADD 原位覆盖
	_apply(world, updater, _shield("u1", ADD, "s1", 10.0, 10.0), 1.0)
	TestFramework.assert_equal("s1,s2", _shield_ids(world, "u1"))
	TestFramework.assert_near(_actor(world, "u1").shields[0].capacity, 10.0)

	# UPDATE 同 current：noop guard
	world.flush_dirty_actors()
	changed.clear()
	_apply(world, updater, _shield("u1", UPDATE, "s2", 50.0, 999.0), 1.0)
	world.flush_dirty_actors()
	# current 没变不标脏
	TestFramework.assert_equal(0, changed.size())
	TestFramework.assert_near(_actor(world, "u1").shields[1].capacity, 50.0, 0.0001, "UPDATE 不碰 capacity")

	# UPDATE 变 current：只改 current，capacity 不动
	_apply(world, updater, _shield("u1", UPDATE, "s2", 20.0, 999.0), 1.0)
	TestFramework.assert_near(_actor(world, "u1").shields[1].current, 20.0)
	TestFramework.assert_near(_actor(world, "u1").shields[1].capacity, 50.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(1, changed.size())
	changed.clear()

	# UPDATE 未知 id / 缺 summary：忽略
	_apply(world, updater, _shield("u1", UPDATE, "s9", 1.0, 1.0), 1.0)
	_apply(world, updater, VisualShieldStateAction.new("u1", ADD, "s3", null), 1.0)
	TestFramework.assert_equal("s1,s2", _shield_ids(world, "u1"))
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# REMOVE：找到即删，找不到 noop
	_apply(world, updater, VisualShieldStateAction.new("u1", REMOVE, "s1", null), 1.0)
	TestFramework.assert_equal("s2", _shield_ids(world, "u1"))
	world.flush_dirty_actors()
	changed.clear()
	_apply(world, updater, VisualShieldStateAction.new("u1", REMOVE, "s1", null), 1.0)
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())


func _test_bump_snaps_back() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	var bump := VisualBumpAction.new("u1", Vector2(1.0, 0.0), 0.3, 280.0, true)

	_apply(world, updater, bump, 0.4)
	var u1 := _actor(world, "u1")
	TestFramework.assert_true(u1.bump_offset.length() > 0.0, "中途有位移")
	TestFramework.assert_true(u1.bump_offset.is_equal_approx(bump.get_offset(0.4)))
	TestFramework.assert_true(u1.bump_squish.is_equal_approx(bump.get_squish(0.4)))
	TestFramework.assert_false(u1.bump_squish.is_equal_approx(Vector2.ONE), "撞击峰值段有挤压")

	_apply(world, updater, bump, 1.0)
	u1 = _actor(world, "u1")
	TestFramework.assert_true(u1.bump_offset.is_equal_approx(Vector2.ZERO), "完成 snap 回零位")
	TestFramework.assert_true(u1.bump_squish.is_equal_approx(Vector2.ONE), "完成 squish 回 ONE")

	# 不挤压的 bump 只位移
	var flat := VisualBumpAction.new("u1", Vector2(0.0, 1.0), 0.3, 280.0, false)
	_apply(world, updater, flat, 0.4)
	u1 = _actor(world, "u1")
	TestFramework.assert_true(u1.bump_offset.length() > 0.0)
	TestFramework.assert_true(u1.bump_squish.is_equal_approx(Vector2.ONE))


func _test_facing_instant() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	var changed := _record_changes(world)
	TestFramework.assert_equal(0, _actor(world, "u1").facing_direction)
	_apply(world, updater, VisualFacingStateAction.new("u1", 4), 1.0)
	TestFramework.assert_equal(4, _actor(world, "u1").facing_direction)
	# 只标脏
	TestFramework.assert_equal(0, changed.size())
	world.flush_dirty_actors()
	TestFramework.assert_equal("u1", ",".join(changed))
	_apply(world, updater, VisualFacingStateAction.new("ghost", 2), 1.0)
	TestFramework.assert_equal(4, _actor(world, "u1").facing_direction)


func _test_death_action() -> void:
	var world := _world([{"id": "u1", "hp": 40.0}])
	var updater := VisualUpdater.new()
	var died := _record_deaths(world)
	var changed := _record_changes(world)
	var death := VisualDeathAction.new("u1", 1000.0)

	_apply(world, updater, death, 0.3)
	var u1 := _actor(world, "u1")
	TestFramework.assert_false(u1.is_alive)
	TestFramework.assert_near(u1.visual_hp, 0.0)
	TestFramework.assert_near(u1.target_hp, 0.0)
	TestFramework.assert_near(u1.death_progress, 0.3)
	TestFramework.assert_equal("u1", ",".join(died))
	# death 当场广播，不等 flush
	TestFramework.assert_equal("u1", ",".join(changed))

	_apply(world, updater, death, 1.0)
	TestFramework.assert_near(_actor(world, "u1").death_progress, 1.0)
	# actor_died transition-only
	TestFramework.assert_equal(1, died.size())
	TestFramework.assert_equal(2, changed.size())


func _test_move_interpolates_then_settles() -> void:
	var world := _world([{"id": "u1", "q": 0, "r": 0}])
	var updater := VisualUpdater.new()
	var changed := _record_changes(world)
	var move := VisualMoveAction.new("u1", Vector2(0.0, 0.0), Vector2(2.0, 0.0), 500.0, VisualAction.EasingType.LINEAR)

	_apply(world, updater, move, 0.5)
	# 在飞浮点坐标：账本与只读视图同一口径
	TestFramework.assert_true(world.get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	TestFramework.assert_true(world.as_query().get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	# 中途 actor.position 不动
	TestFramework.assert_true(_actor(world, "u1").position.is_equal_approx(Vector2.ZERO))
	# 中途不广播
	TestFramework.assert_equal(0, changed.size())

	_apply(world, updater, move, 0.2)
	TestFramework.assert_true(world.get_actor_position("u1").is_equal_approx(Vector2(0.4, 0.0)))

	_apply(world, updater, move, 1.0)
	TestFramework.assert_true(_actor(world, "u1").position.is_equal_approx(Vector2(2.0, 0.0)))
	TestFramework.assert_true(world.get_actor_position("u1").is_equal_approx(Vector2(2.0, 0.0)))
	# 完成当场广播
	TestFramework.assert_equal("u1", ",".join(changed))


func _test_skips_delaying() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	var active := ActionStepper.ActiveAction.new("d", VisualFacingStateAction.new("u1", 3))
	active.is_delaying = true
	active.progress = 0.0
	var batch: Array[ActionStepper.ActiveAction] = [active]
	updater.apply_actions(world, batch)
	# 延迟中的卡片不应用
	TestFramework.assert_equal(0, _actor(world, "u1").facing_direction)


func _test_floating_text_once_then_expires() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	var log := _record_effects(world)
	var text := VisualFloatingTextAction.new("u1", "-5", Color.WHITE, Vector2.ZERO, VisualFloatingTextAction.FloatingTextStyle.NORMAL, 1000.0)

	_apply(world, updater, text, 0.1, "ft1")
	_apply(world, updater, text, 0.5, "ft1")
	# 同一卡片 id 只入账一次；飘字不发 update
	TestFramework.assert_equal("create:floating_text:ft1", ",".join(log))
	_apply(world, updater, text, 0.1, "ft2")
	TestFramework.assert_equal("create:floating_text:ft1,create:floating_text:ft2", ",".join(log))
	TestFramework.assert_true(world.has_effect(VisualAction.KIND_FLOATING_TEXT, "ft1"))

	# 寿命 1000 ms：999 ms 还在账上，1000 ms 静默忘记（不发 effect_removed）
	world.advance_time(999)
	updater.tick_time(world, 999.0)
	TestFramework.assert_true(world.has_effect(VisualAction.KIND_FLOATING_TEXT, "ft1"), "未到期不忘")
	world.advance_time(1)
	updater.tick_time(world, 1.0)
	TestFramework.assert_false(world.has_effect(VisualAction.KIND_FLOATING_TEXT, "ft1"), "到期忘记")
	TestFramework.assert_false(world.has_effect(VisualAction.KIND_FLOATING_TEXT, "ft2"))
	TestFramework.assert_true(log.size() == 2, "到期忘记不发 removed")
	# 忘记之后同 id 再来会重新入账（步进器 id 不复用，这里只钉账本语义）
	_apply(world, updater, text, 0.1, "ft1")
	TestFramework.assert_equal(3, log.size())


func _test_procedural_effects_cleanup() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	var flash := VisualProceduralVfxAction.new(VisualProceduralVfxAction.EffectType.HIT_FLASH, 300.0, "u1")
	_apply(world, updater, flash, 0.5, "fx1")
	TestFramework.assert_near(_actor(world, "u1").flash_progress, 1.0, 0.0001, "闪白强度中点最亮")
	updater.tick_time(world, 0.0)
	TestFramework.assert_near(_actor(world, "u1").flash_progress, 1.0, 0.0001, "未到期不清")
	world.advance_time(300)
	updater.tick_time(world, 300.0)
	TestFramework.assert_near(_actor(world, "u1").flash_progress, 0.0, 0.0001, "到期归零")

	var shake := VisualProceduralVfxAction.new(VisualProceduralVfxAction.EffectType.SHAKE, 200.0, "", 5.0)
	_apply(world, updater, shake, 0.25, "fx2")
	TestFramework.assert_true(world.get_screen_shake_offset().is_equal_approx(shake.get_shake_offset(0.25)))
	TestFramework.assert_true(world.get_screen_shake_offset().length() > 0.0)
	updater.tick_time(world, 0.0)
	TestFramework.assert_true(world.get_screen_shake_offset().length() > 0.0, "未到期震屏保持")
	world.advance_time(200)
	updater.tick_time(world, 200.0)
	TestFramework.assert_true(world.get_screen_shake_offset().is_equal_approx(Vector2.ZERO), "到期震屏归零")

	var tint := VisualProceduralVfxAction.new(VisualProceduralVfxAction.EffectType.COLOR_TINT, 400.0, "u1", 1.0, Color.RED)
	_apply(world, updater, tint, 0.5, "fx3")
	TestFramework.assert_true(_actor(world, "u1").tint_color.is_equal_approx(Color.RED))
	_apply(world, updater, tint, 1.0, "fx3")
	TestFramework.assert_true(_actor(world, "u1").tint_color.is_equal_approx(Color.WHITE), "progress 1 染色回白")


func _test_attack_vfx_and_projectile_lifecycle() -> void:
	var world := _world([{"id": "u1"}, {"id": "u2", "q": 1}])
	var updater := VisualUpdater.new()
	var log := _record_effects(world)
	var scales: Array[float] = []
	var positions: Array[Vector2] = []
	world.effect_updated.connect(func(kind: StringName, _effect_id: String, _progress: float, payload: VisualEffectPayload.Effect) -> void:
		if kind == VisualAction.KIND_ATTACK_VFX:
			scales.append((payload as VisualEffectPayload.AttackVfx).scale_factor)
		elif kind == VisualAction.KIND_PROJECTILE:
			positions.append((payload as VisualEffectPayload.Projectile).position))

	var vfx := VisualAttackVfxAction.new("u1", "u2", Vector2.ZERO, Vector2(1.0, 0.0), 300.0)
	_apply(world, updater, vfx, 0.0, "v1")
	_apply(world, updater, vfx, 0.5, "v1")
	_apply(world, updater, vfx, 1.0, "v1")
	TestFramework.assert_equal(
		"create:attack_vfx:v1,update:attack_vfx:v1@0.0,update:attack_vfx:v1@0.5,update:attack_vfx:v1@1.0,remove:attack_vfx:v1",
		",".join(log)
	)
	# payload 随进度带当前缩放（0 → 峰值 → 0）
	TestFramework.assert_near(scales[0], vfx.get_vfx_scale(0.0))
	TestFramework.assert_near(scales[1], vfx.get_vfx_scale(0.5))
	TestFramework.assert_false(world.has_effect(VisualAction.KIND_ATTACK_VFX, "v1"), "完成即出账")
	log.clear()

	var projectile := VisualProjectileAction.new("p_logic", "u1", Vector2.ZERO, Vector2(2.0, 0.0), 400.0, "u2")
	_apply(world, updater, projectile, 0.0, "p1")
	_apply(world, updater, projectile, 0.5, "p1")
	TestFramework.assert_true(positions[1].is_equal_approx(Vector2(1.0, 0.0)), "更新信号带逻辑平面插值位置")
	_apply(world, updater, projectile, 1.0, "p1")
	TestFramework.assert_equal(
		"create:projectile:p1,update:projectile:p1@0.0,update:projectile:p1@0.5,update:projectile:p1@1.0,remove:projectile:p1",
		",".join(log)
	)


func _test_private_kind_handler() -> void:
	var world := _world([{"id": "u1"}])
	var updater := VisualUpdater.new()
	TestFramework.assert_true(updater.has_handler(VisualAction.KIND_MOVE), "内置 11 种默认登记")
	TestFramework.assert_false(updater.has_handler(ProbeAction.KIND))
	updater.register_handler(ProbeAction.KIND, ProbeAction.apply)
	TestFramework.assert_true(updater.has_handler(ProbeAction.KIND))

	var log := _record_effects(world)
	var probe := ProbeAction.new("u1", 500.0)
	_apply(world, updater, probe, 0.2, "pr1")
	_apply(world, updater, probe, 0.9, "pr1")
	TestFramework.assert_true(probe.applied == 2, "私有 handler 每次 apply 都被调")
	TestFramework.assert_equal("create:probe:pr1", ",".join(log))
	TestFramework.assert_true(world.has_effect(ProbeAction.KIND, "pr1"))
	# 私有种类与内置种类同一套到期规则
	world.advance_time(500)
	updater.tick_time(world, 500.0)
	TestFramework.assert_false(world.has_effect(ProbeAction.KIND, "pr1"))
