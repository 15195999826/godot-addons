extends Node

## FrontendRenderWorld 账本半边（录像台面重建 + 事件直改 + 只读视图）的合同钉子
##
## 钉住合同：
## - initialize_from_replay 按 world_snapshot 建每个 actor（hex 位置 / hp / max_hp / facing / 队伍），
##   空 id 跳过，建完对每个 actor 广播一次 actor_state_changed；get_actors_snapshot 是深拷贝
## - actor_spawned 事件直改：新 actor 入账并广播 actor_spawned + actor_state_changed；同 id 重复 spawn 忽略；
##   actor 缺 id 用事件的 actor_id；空 actor dict 忽略
## - actor_destroyed 事件直改：is_alive=false、hp 归零、actor_died 只发一次；未知 actor 忽略
## - attribute_changed(max_hp) 事件直改：max_hp 夹到 ≥ 0，visual / target 夹到新上限，上限回升不回血，
##   只标脏；别的属性不管；不判死
## - reset_to 回到录像台面：中途 spawn 的没了、hp / 位置 / 存活恢复、世界时间归零、死亡转换可再发
## - as_context 只读视图：hp / max_hp / 存活 / 队伍 / 名字 / 全部 id / 取整 hex 位置；未知 actor 走默认值


const PROBE_TYPE := "probe"


func _init() -> void:
	TestFramework.register_test("RenderWorld initialize_from_replay 建台面、跳空 id、每人广播一次、快照深拷贝", _test_initialize_from_replay)
	TestFramework.register_test("RenderWorld actor_spawned 事件直改入账并广播，重复 spawn 忽略", _test_spawn_event)
	TestFramework.register_test("RenderWorld actor_destroyed 事件直改归零，actor_died 只发一次", _test_destroy_event)
	TestFramework.register_test("RenderWorld attribute_changed(max_hp) 夹上限、回升不回血、不判死", _test_max_hp_change_clamps)
	TestFramework.register_test("RenderWorld reset_to 回到录像台面", _test_reset_to_restores)
	TestFramework.register_test("RenderWorld as_context 只读视图与未知 actor 默认值", _test_context_queries)


static func _init_data(id: String, q: int, r: int, hp: float, max_hp: float, extra: Dictionary = {}) -> PlaybackData.ActorInitData:
	var init := PlaybackData.ActorInitData.new()
	init.id = id
	init.type = PROBE_TYPE
	init.config_id = extra.get("config_id", "")
	init.display_name = extra.get("name", id)
	init.team = extra.get("team", 0)
	init.position = [q, r, 0]
	init.attributes = {"hp": hp, "max_hp": max_hp}
	if extra.has("facing"):
		init.attributes["facing_direction"] = extra["facing"]
	return init


static func _record(actors: Array[PlaybackData.ActorInitData]) -> PlaybackData.BattleRecord:
	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	record.world_snapshot = PlaybackData.WorldSnapshot.new()
	record.world_snapshot.position_formats = {PROBE_TYPE: "hex"}
	record.world_snapshot.actors = actors
	return record


static func _actor(world: FrontendRenderWorld, actor_id: String) -> FrontendActorRenderState:
	return world.get_actors_snapshot().get(actor_id)


static func _record_changes(world: FrontendRenderWorld) -> Array[String]:
	var changed: Array[String] = []
	world.actor_state_changed.connect(func(actor_id: String, _state: FrontendActorRenderState) -> void:
		changed.append(actor_id))
	return changed


static func _record_deaths(world: FrontendRenderWorld) -> Array[String]:
	var died: Array[String] = []
	world.actor_died.connect(func(actor_id: String) -> void: died.append(actor_id))
	return died


static func _spawn_event(actor_id: String, actor: Dictionary) -> Dictionary:
	return {"kind": GameEvent.ACTOR_SPAWNED_EVENT, "actor_id": actor_id, "actor": actor}


static func _max_hp_event(actor_id: String, new_value: float, attribute: String = "max_hp") -> Dictionary:
	return GameEvent.AttributeChanged.create(actor_id, attribute, 0.0, new_value).to_dict()


func _test_initialize_from_replay() -> void:
	var world := FrontendRenderWorld.new()
	var changed := _record_changes(world)
	var actors: Array[PlaybackData.ActorInitData] = [
		_init_data("u1", 2, -1, 40.0, 100.0, {"facing": 3, "team": 0, "name": "左一", "config_id": "warrior"}),
		_init_data("", 0, 0, 1.0, 1.0),
		_init_data("u2", -3, 4, 80.0, 80.0, {"team": 1}),
	]
	world.initialize_from_replay(_record(actors))

	TestFramework.assert_equal("u1,u2", ",".join(changed))
	var snapshot := world.get_actors_snapshot()
	TestFramework.assert_equal(2, snapshot.size())
	var u1: FrontendActorRenderState = snapshot["u1"]
	TestFramework.assert_equal(2, u1.position.q)
	TestFramework.assert_equal(-1, u1.position.r)
	TestFramework.assert_near(u1.visual_hp, 40.0)
	TestFramework.assert_near(u1.target_hp, 40.0)
	TestFramework.assert_near(u1.max_hp, 100.0)
	TestFramework.assert_true(u1.is_alive)
	TestFramework.assert_equal(3, u1.facing_direction)
	TestFramework.assert_equal("左一", u1.display_name)
	TestFramework.assert_equal("warrior", u1.config_id)
	TestFramework.assert_equal(PROBE_TYPE, u1.type)
	TestFramework.assert_equal(0, u1.buffs.size())
	TestFramework.assert_equal(0, u1.shields.size())
	var u2: FrontendActorRenderState = snapshot["u2"]
	TestFramework.assert_equal(1, u2.team)
	# 没有 facing 属性默认 0
	TestFramework.assert_equal(0, u2.facing_direction)
	TestFramework.assert_equal(0, world.get_world_time())

	# 快照是深拷贝：改拷贝不影响账本
	u1.target_hp = 1.0
	u1.position = HexCoord.new(9, 9)
	TestFramework.assert_near(_actor(world, "u1").target_hp, 40.0)
	TestFramework.assert_equal(2, _actor(world, "u1").position.q)


func _test_spawn_event() -> void:
	var world := FrontendRenderWorld.new()
	var actors: Array[PlaybackData.ActorInitData] = [_init_data("u1", 0, 0, 100.0, 100.0)]
	world.initialize_from_replay(_record(actors))
	var spawned: Array[String] = []
	world.actor_spawned.connect(func(actor_id: String, _state: FrontendActorRenderState) -> void: spawned.append(actor_id))
	var changed := _record_changes(world)

	var totem := {
		"id": "t1", "type": PROBE_TYPE, "config_id": "totem", "display_name": "图腾", "team": 1,
		"position": [3, 4, 0], "attributes": {"hp": 20.0, "max_hp": 20.0},
	}
	world.apply_event_side_effects(_spawn_event("t1", totem))
	TestFramework.assert_equal("t1", ",".join(spawned))
	TestFramework.assert_equal("t1", ",".join(changed))
	var t1 := _actor(world, "t1")
	TestFramework.assert_equal(3, t1.position.q)
	TestFramework.assert_equal(4, t1.position.r)
	TestFramework.assert_near(t1.visual_hp, 20.0)
	TestFramework.assert_near(t1.max_hp, 20.0)
	TestFramework.assert_true(t1.is_alive)
	TestFramework.assert_equal(1, t1.team)
	TestFramework.assert_equal("totem", t1.config_id)
	TestFramework.assert_equal(2, world.as_context().get_all_actor_ids().size())

	# 同 id 重复 spawn：忽略，不再广播
	world.apply_event_side_effects(_spawn_event("t1", totem))
	TestFramework.assert_equal(1, spawned.size())
	TestFramework.assert_equal(1, changed.size())

	# actor dict 缺 id：用事件的 actor_id；缺属性走默认 100
	world.apply_event_side_effects(_spawn_event("t2", {"type": PROBE_TYPE, "position": [0, 0, 0], "attributes": {}}))
	TestFramework.assert_equal("t1,t2", ",".join(spawned))
	TestFramework.assert_near(_actor(world, "t2").visual_hp, 100.0)

	# 空 actor dict / 缺 actor：忽略
	world.apply_event_side_effects(_spawn_event("t3", {}))
	world.apply_event_side_effects({"kind": GameEvent.ACTOR_SPAWNED_EVENT, "actor_id": "t4"})
	TestFramework.assert_equal(2, spawned.size())
	TestFramework.assert_equal(3, world.get_actors_snapshot().size())


func _test_destroy_event() -> void:
	var world := FrontendRenderWorld.new()
	var actors: Array[PlaybackData.ActorInitData] = [_init_data("u1", 0, 0, 50.0, 100.0)]
	world.initialize_from_replay(_record(actors))
	var died := _record_deaths(world)
	var changed := _record_changes(world)

	world.apply_event_side_effects({"kind": GameEvent.ACTOR_DESTROYED_EVENT, "actor_id": "u1"})
	var u1 := _actor(world, "u1")
	TestFramework.assert_false(u1.is_alive)
	TestFramework.assert_near(u1.visual_hp, 0.0)
	TestFramework.assert_near(u1.target_hp, 0.0)
	TestFramework.assert_equal("u1", ",".join(died))
	# destroy 当场广播，不等 flush
	TestFramework.assert_equal("u1", ",".join(changed))
	TestFramework.assert_true(world.get_actors_snapshot().has("u1"), "销毁只改状态，账本仍留这条")

	world.apply_event_side_effects({"kind": GameEvent.ACTOR_DESTROYED_EVENT, "actor_id": "u1"})
	# actor_died transition-only
	TestFramework.assert_equal(1, died.size())

	world.apply_event_side_effects({"kind": GameEvent.ACTOR_DESTROYED_EVENT, "actor_id": "ghost"})
	world.apply_event_side_effects({"kind": GameEvent.ACTOR_DESTROYED_EVENT})
	TestFramework.assert_equal(1, died.size())
	TestFramework.assert_equal(2, changed.size())


func _test_max_hp_change_clamps() -> void:
	var world := FrontendRenderWorld.new()
	var actors: Array[PlaybackData.ActorInitData] = [_init_data("u1", 0, 0, 100.0, 100.0)]
	world.initialize_from_replay(_record(actors))
	var changed := _record_changes(world)
	var died := _record_deaths(world)

	world.apply_event_side_effects(_max_hp_event("u1", 60.0))
	var u1 := _actor(world, "u1")
	TestFramework.assert_near(u1.max_hp, 60.0)
	TestFramework.assert_near(u1.visual_hp, 60.0, 0.0001, "visual 夹到新上限")
	TestFramework.assert_near(u1.target_hp, 60.0, 0.0001, "target 夹到新上限")
	# 只标脏
	TestFramework.assert_equal(0, changed.size())
	world.flush_dirty_actors()
	TestFramework.assert_equal("u1", ",".join(changed))
	changed.clear()

	# 上限回升不回血
	world.apply_event_side_effects(_max_hp_event("u1", 120.0))
	u1 = _actor(world, "u1")
	TestFramework.assert_near(u1.max_hp, 120.0)
	TestFramework.assert_near(u1.visual_hp, 60.0)
	TestFramework.assert_near(u1.target_hp, 60.0)

	# 别的属性不管
	world.apply_event_side_effects(_max_hp_event("u1", 5.0, "atk"))
	TestFramework.assert_near(_actor(world, "u1").max_hp, 120.0)
	world.flush_dirty_actors()
	changed.clear()
	world.apply_event_side_effects(_max_hp_event("u1", 5.0, "atk"))
	world.flush_dirty_actors()
	TestFramework.assert_equal(0, changed.size())

	# 负上限夹到 0，hp 跟着归零；上限直改不判死（死活只由 hp delta / death / destroy 决定）
	world.apply_event_side_effects(_max_hp_event("u1", -5.0))
	u1 = _actor(world, "u1")
	TestFramework.assert_near(u1.max_hp, 0.0)
	TestFramework.assert_near(u1.target_hp, 0.0)
	TestFramework.assert_true(u1.is_alive)
	TestFramework.assert_equal(0, died.size())

	# 未知 actor：忽略
	world.apply_event_side_effects(_max_hp_event("ghost", 10.0))
	TestFramework.assert_equal(1, world.get_actors_snapshot().size())


func _test_reset_to_restores() -> void:
	var world := FrontendRenderWorld.new()
	var actors: Array[PlaybackData.ActorInitData] = [_init_data("u1", 1, 1, 100.0, 100.0)]
	var record := _record(actors)
	world.initialize_from_replay(record)
	var died := _record_deaths(world)

	# 打乱：扣血致死、spawn 新人、推进时间、改位置
	var kill := FrontendActionScheduler.ActiveAction.new("k", FrontendApplyHPDeltaAction.new("u1", -100.0))
	kill.progress = 1.0
	kill.is_delaying = false
	var batch: Array[FrontendActionScheduler.ActiveAction] = [kill]
	world.apply_actions(batch)
	world.apply_event_side_effects(_spawn_event("t1", {"type": PROBE_TYPE, "position": [0, 0, 0], "attributes": {}}))
	world.advance_time(1234)
	world.set_actor_position("u1", HexCoord.new(5, 5))
	TestFramework.assert_equal("u1", ",".join(died))
	TestFramework.assert_equal(2, world.get_actors_snapshot().size())

	var changed := _record_changes(world)
	world.reset_to(record)
	# 重建后每个 actor 广播一次
	TestFramework.assert_equal("u1", ",".join(changed))
	var snapshot := world.get_actors_snapshot()
	# 中途 spawn 的不在台面上
	TestFramework.assert_equal(1, snapshot.size())
	var u1: FrontendActorRenderState = snapshot["u1"]
	TestFramework.assert_true(u1.is_alive)
	TestFramework.assert_near(u1.visual_hp, 100.0)
	TestFramework.assert_near(u1.target_hp, 100.0)
	TestFramework.assert_equal(1, u1.position.q)
	TestFramework.assert_equal(1, u1.position.r)
	# 插值位置一并重置
	TestFramework.assert_equal(1, world.as_context().get_actor_hex_position("u1").q)
	TestFramework.assert_equal(0, world.get_world_time())

	# 重置后死亡转换可再发一次
	world.apply_actions(batch)
	TestFramework.assert_equal("u1,u1", ",".join(died))


func _test_context_queries() -> void:
	var world := FrontendRenderWorld.new()
	var actors: Array[PlaybackData.ActorInitData] = [
		_init_data("u1", 2, -1, 40.0, 100.0, {"team": 1, "name": "右一"}),
		_init_data("u2", 0, 0, 0.0, 50.0),
	]
	world.initialize_from_replay(_record(actors))
	var context := world.as_context()

	TestFramework.assert_near(context.get_actor_hp("u1"), 40.0)
	TestFramework.assert_near(context.get_actor_max_hp("u1"), 100.0)
	TestFramework.assert_true(context.is_actor_alive("u1"))
	TestFramework.assert_true(context.is_actor_alive("u2"), "开局 hp 0 也按存活入账，死活由事件决定")
	TestFramework.assert_equal(1, context.get_actor_team("u1"))
	TestFramework.assert_equal("右一", context.get_actor_display_name("u1"))
	TestFramework.assert_equal("u1,u2", ",".join(context.get_all_actor_ids()))
	var hex := context.get_actor_hex_position("u1")
	TestFramework.assert_equal(2, hex.q)
	TestFramework.assert_equal(-1, hex.r)
	TestFramework.assert_true(context.get_animation_config() != null)

	# 未知 actor 默认值
	TestFramework.assert_near(context.get_actor_hp("ghost"), 0.0)
	TestFramework.assert_near(context.get_actor_max_hp("ghost"), 100.0)
	TestFramework.assert_false(context.is_actor_alive("ghost"))
	TestFramework.assert_equal(0, context.get_actor_team("ghost"))
	TestFramework.assert_equal("", context.get_actor_display_name("ghost"))
	var ghost_hex := context.get_actor_hex_position("ghost")
	TestFramework.assert_equal(0, ghost_hex.q)
	TestFramework.assert_equal(0, ghost_hex.r)

	# 视图跟着账本走：直改后同一个 context 读到新值
	world.set_actor_hp("u1", 7.0)
	TestFramework.assert_near(context.get_actor_hp("u1"), 7.0)
