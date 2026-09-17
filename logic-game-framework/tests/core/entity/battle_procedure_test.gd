extends Node

## BattleProcedure 录像收尾 / 开录 / 中途移除 actor 的合同单测
##
## 1. finish() 清 in_combat 产生的 TagChanged 录进本场最后一帧（该帧已有 FrameData 就并进去，没有就补一条同帧号的）
## 2. 常驻世界连打两场：上一场收尾的事件与两场之间推进 collector 的事件都不进下一场录像
## 3. 战斗中途 remove_actor：订阅当场释放（之后该 actor 的变化不再进录像），ActorDestroyed 恰好一条
## 4. finish() / abort() 都断开 procedure 在 world 上的两条 signal 连接

const TAG_IN_COMBAT := "in_combat"
const KIND_PROBE := "battle_procedure_probe"
const KIND_STRAY := "battle_procedure_stray"


## 带 ability_set 的最小战斗 actor：loose tag 的变化经 BattleActor 默认录像订阅进 collector。
class ProbeActor:
	extends BattleActor

	var ability_set: AbilitySet

	func _init() -> void:
		type = "battle_procedure_probe"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set


## in_combat 走 loose tag 的 procedure（hex / inkmon 同形）；tick_once 用基类的「只录帧」。
class TagProcedure:
	extends BattleProcedure

	func _mark_in_combat(actor_id: String, active: bool) -> void:
		var actor := _get_actor(actor_id) as ProbeActor
		if actor == null:
			return
		if active:
			actor.ability_set.add_loose_tag(TAG_IN_COMBAT)
		else:
			actor.ability_set.remove_loose_tag(TAG_IN_COMBAT)


class TagWorld:
	extends WorldGameplayInstance

	func _create_battle_procedure(participants: Array[Actor]) -> BattleProcedure:
		return TagProcedure.new(self, participants)


func _init() -> void:
	TestFramework.register_test("BattleProcedure.finish records the in_combat clear into the last recorded frame", _test_finish_merges_into_last_frame)
	TestFramework.register_test("BattleProcedure.finish appends a frame when the last tick recorded nothing", _test_finish_appends_frame_when_last_tick_was_empty)
	TestFramework.register_test("BattleProcedure: a second battle in the same world records nothing from before it started", _test_second_battle_starts_clean)
	TestFramework.register_test("BattleProcedure: remove_actor mid-battle releases the subscription and records actor_destroyed once", _test_remove_actor_mid_battle_unsubscribes)
	TestFramework.register_test("BattleProcedure: finish and abort disconnect from the world signals", _test_finish_and_abort_disconnect)


# ========== 用例 ==========

func _test_finish_merges_into_last_frame() -> void:
	var world := _make_world("bp_merge")
	var actors := _add_actors(world, 2)
	var procedure := world.start_battle(_as_participants(actors))
	world.event_collector.push({"kind": KIND_PROBE})
	procedure.tick_once()
	var record := procedure.finish()

	var frames := _frames_of(record)
	TestFramework.assert_equal(1, frames.size())
	var events := _events_of(frames[0])
	TestFramework.assert_equal(1, int(frames[0].get("frame", -1)))
	TestFramework.assert_equal(3, events.size())
	TestFramework.assert_equal(KIND_PROBE, _kind_at(events, 0))
	TestFramework.assert_equal(2, _in_combat_clears(events).size())
	TestFramework.assert_equal(1, int((record.get("meta", {}) as Dictionary).get("total_frames", -1)))
	TestFramework.assert_equal(0, world.event_collector.get_count())
	GameWorld.destroy_instance(world.id)


func _test_finish_appends_frame_when_last_tick_was_empty() -> void:
	var world := _make_world("bp_append")
	var actors := _add_actors(world, 2)
	var procedure := world.start_battle(_as_participants(actors))
	world.event_collector.push({"kind": KIND_PROBE})
	procedure.tick_once()
	procedure.tick_once()
	var record := procedure.finish()

	var frames := _frames_of(record)
	TestFramework.assert_equal(2, frames.size())
	if frames.size() == 2:
		TestFramework.assert_equal(1, _events_of(frames[0]).size())
		TestFramework.assert_equal(2, int(frames[1].get("frame", -1)))
		TestFramework.assert_equal(2, _in_combat_clears(_events_of(frames[1])).size())
	TestFramework.assert_equal(2, int((record.get("meta", {}) as Dictionary).get("total_frames", -1)))
	GameWorld.destroy_instance(world.id)


func _test_second_battle_starts_clean() -> void:
	var world := _make_world("bp_two_battles")
	var actors := _add_actors(world, 2)
	var first := world.start_battle(_as_participants(actors))
	world.event_collector.push({"kind": KIND_PROBE})
	first.tick_once()
	first.finish()
	# 两场之间推进 world collector 的事件（常驻世界在战斗外照样跑 action）
	world.event_collector.push({"kind": KIND_STRAY})

	var second := world.start_battle(_as_participants(actors))
	world.event_collector.push({"kind": KIND_PROBE})
	second.tick_once()
	var record := second.finish()

	var frames := _frames_of(record)
	TestFramework.assert_equal(1, frames.size())
	var events := _events_of(frames[0])
	TestFramework.assert_equal(KIND_PROBE, _kind_at(events, 0))
	var stray := 0
	for event in events:
		if str(event.get("kind", "")) == KIND_STRAY:
			stray += 1
	TestFramework.assert_equal(0, stray)
	# 只有本场自己收尾的两条 in_combat 清除，上一场的不在
	TestFramework.assert_equal(2, _in_combat_clears(events).size())
	TestFramework.assert_equal(3, events.size())
	GameWorld.destroy_instance(world.id)


func _test_remove_actor_mid_battle_unsubscribes() -> void:
	var world := _make_world("bp_remove")
	var actors := _add_actors(world, 3)
	var leaver := actors[2]
	var leaver_id := leaver.get_id()
	var procedure := world.start_battle(_as_participants([actors[0], actors[1]]))
	var recorder := procedure.get_recorder()
	TestFramework.assert_true(recorder.actor_subscriptions.has(leaver_id), "registry 常客开战即被订阅")

	world.remove_actor(leaver_id)
	TestFramework.assert_false(recorder.actor_subscriptions.has(leaver_id), "remove_actor 之后订阅应当场释放")
	# 离场之后的变化不再进录像
	leaver.ability_set.add_loose_tag("after_leaving")
	procedure.tick_once()
	var record := procedure.finish()

	var destroyed := 0
	var late_changes := 0
	for frame in _frames_of(record):
		for event in _events_of(frame):
			if str(event.get("actor_id", "")) != leaver_id:
				continue
			if str(event.get("kind", "")) == GameEvent.ACTOR_DESTROYED_EVENT:
				destroyed += 1
			elif str(event.get("kind", "")) == GameEvent.TAG_CHANGED_EVENT:
				late_changes += 1
	TestFramework.assert_equal(1, destroyed)
	TestFramework.assert_equal(0, late_changes)
	GameWorld.destroy_instance(world.id)


func _test_finish_and_abort_disconnect() -> void:
	var world := _make_world("bp_disconnect")
	var actors := _add_actors(world, 2)
	var finished := world.start_battle(_as_participants(actors))
	TestFramework.assert_equal(1, world.actor_added.get_connections().size())
	TestFramework.assert_equal(1, world.actor_removed.get_connections().size())
	finished.finish()
	TestFramework.assert_equal(0, world.actor_added.get_connections().size())
	TestFramework.assert_equal(0, world.actor_removed.get_connections().size())

	var aborted := world.start_battle(_as_participants(actors))
	TestFramework.assert_equal(1, world.actor_removed.get_connections().size())
	aborted.abort()
	TestFramework.assert_equal(0, world.actor_added.get_connections().size())
	TestFramework.assert_equal(0, world.actor_removed.get_connections().size())
	GameWorld.destroy_instance(world.id)


# ========== 夹具 ==========

static func _make_world(id_value: String) -> TagWorld:
	GameWorld.shutdown()
	var world := GameWorld.create_instance(TagWorld.new(id_value)) as TagWorld
	world.start()
	return world


static func _add_actors(world: TagWorld, count: int) -> Array[ProbeActor]:
	var actors: Array[ProbeActor] = []
	for _i in count:
		actors.append(world.add_actor(ProbeActor.new()) as ProbeActor)
	return actors


static func _as_participants(actors: Array) -> Array[Actor]:
	var participants: Array[Actor] = []
	for actor: Actor in actors:
		participants.append(actor)
	return participants


static func _frames_of(record: Dictionary) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	frames.assign(record.get("timeline", []))
	return frames


static func _events_of(frame: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.assign(frame.get("events", []))
	return events


static func _kind_at(events: Array[Dictionary], index: int) -> String:
	if index >= events.size():
		return ""
	return str(events[index].get("kind", ""))


## in_combat 1 → 0 的 tag_changed（procedure 收尾清 tag 产生的那种）。
static func _in_combat_clears(events: Array[Dictionary]) -> Array[Dictionary]:
	var clears: Array[Dictionary] = []
	for event in events:
		if str(event.get("kind", "")) != GameEvent.TAG_CHANGED_EVENT:
			continue
		if str(event.get("tag", "")) == TAG_IN_COMBAT and int(event.get("new_count", -1)) == 0:
			clears.append(event)
	return clears
