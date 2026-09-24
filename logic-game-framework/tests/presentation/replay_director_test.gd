extends Node

## ReplayDirector（录像回放表演实例）的帧时钟合同钉子
##
## 钉住合同：
## - load_playback：帧表按 timeline 建、总帧数取 meta.total_frames、tick_ms 取 meta.tick_interval（≤ 0 退回 100）、
##   账本重建到开战台面、帧归 0 并发一次 frame_changed(0, total)；未播放、未结束；反复 load = 换片（在飞卡片清空）
## - step(delta_ms)：攒 delta，每满一帧推进一帧并把那帧事件喂 pump；帧 0 的事件不处理（从帧 1 起）；
##   不满一帧只推动画不推帧；一次 step 跨多帧时按帧序全部处理、卡片在同一趟里以整段 delta 推进
## - 录像帧播完不立即结束：步进器排空那一趟才发 playback_ended（is_ended 同口径）；结束后 step 不再推帧
## - reset：停播（playback_state_changed false）、清步进器、账本回开战台面、帧归 0；幂等；重放结果一致
## - play / pause / toggle：翻转 + playback_state_changed；已结束时 play 自动 reset，toggle 无动作；step 不看播放态


class ProbeMoveTranslator extends Translator:
	const KIND := "probe_move"

	func _init() -> void:
		translator_name = "ProbeMoveTranslator"

	func can_handle(event: Dictionary) -> bool:
		return get_event_kind(event) == KIND

	func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]:
		var actor_id := get_string_field(event, "actor_id")
		var to: Array = event.get("to", [0, 0])
		var card := VisualMoveAction.new(
			actor_id, query.get_actor_position(actor_id), Vector2(float(to[0]), float(to[1])),
			get_float_field(event, "duration", 200.0), VisualAction.EasingType.LINEAR)
		return [card]


const TOTAL_FRAMES := 4


func _init() -> void:
	TestFramework.register_test("ReplayDirector load 归零、step 逐帧喂事件、帧 0 不处理、排空后 playback_ended", _test_load_and_step)
	TestFramework.register_test("ReplayDirector 不满一帧不推帧，一次 step 跨多帧按帧序处理", _test_partial_and_multi_frame_steps)
	TestFramework.register_test("ReplayDirector reset 回开战台面且幂等，重放结果一致", _test_reset_idempotent_and_replay_same)
	TestFramework.register_test("ReplayDirector play / pause / toggle 翻转，已结束时 play 自动 reset、toggle 无动作", _test_play_pause_toggle)
	TestFramework.register_test("ReplayDirector tick_ms 取录像 tick_interval（≤ 0 退回 100），reload 换片", _test_tick_interval_and_reload)


static func _director() -> ReplayDirector:
	return ReplayDirector.new(TranslatorRegistry.new().register(ProbeMoveTranslator.new()))


static func _init_data(id: String, q: int, r: int, hp: float, max_hp: float) -> PlaybackData.ActorInitData:
	var init := PlaybackData.ActorInitData.new()
	init.id = id
	init.type = "probe"
	init.display_name = id
	init.position = [q, r, 0]
	init.attributes = {"hp": hp, "max_hp": max_hp}
	return init


static func _frame(frame: int, events: Array[Dictionary]) -> PlaybackData.FrameData:
	var data := PlaybackData.FrameData.new()
	data.frame = frame
	data.events = events
	return data


static func _record(actors: Array[PlaybackData.ActorInitData], frames: Array[PlaybackData.FrameData],
		total_frames: int, tick_interval: int = 100) -> PlaybackData.BattleRecord:
	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	record.meta.total_frames = total_frames
	record.meta.tick_interval = tick_interval
	record.world_snapshot = PlaybackData.WorldSnapshot.new()
	record.world_snapshot.position_formats = {"probe": "hex"}
	record.world_snapshot.actors = actors
	record.timeline = frames
	return record


static func _spawn_event(id: String, q: int, r: int) -> Dictionary:
	return {
		"kind": GameEvent.ACTOR_SPAWNED_EVENT, "actor_id": id,
		"actor": {"id": id, "type": "probe", "position": [q, r, 0], "attributes": {"hp": 10.0, "max_hp": 10.0}},
	}


static func _move_event(actor_id: String, q: int, r: int, duration: float) -> Dictionary:
	return {"kind": ProbeMoveTranslator.KIND, "actor_id": actor_id, "to": [q, r], "duration": duration}


## u1 在 (0,0)；帧 0 有一条不该被处理的 move；帧 2 spawn t1；帧 3 u1 → (1,0) 150ms；总 4 帧 @ 100ms
static func _fixture() -> PlaybackData.BattleRecord:
	var actors: Array[PlaybackData.ActorInitData] = [_init_data("u1", 0, 0, 100.0, 100.0)]
	var frames: Array[PlaybackData.FrameData] = [
		_frame(0, [_move_event("u1", 9, 9, 100.0)]),
		_frame(2, [_spawn_event("t1", 3, 3)]),
		_frame(3, [_move_event("u1", 1, 0, 150.0)]),
	]
	return _record(actors, frames, TOTAL_FRAMES)


static func _record_frames(director: ReplayDirector) -> Array[String]:
	var frames: Array[String] = []
	director.frame_changed.connect(func(current: int, total: int) -> void: frames.append("%d/%d" % [current, total]))
	return frames


static func _record_ended(director: ReplayDirector) -> Array[int]:
	var ended: Array[int] = []
	director.playback_ended.connect(func() -> void: ended.append(1))
	return ended


static func _record_states(director: ReplayDirector) -> Array[bool]:
	var states: Array[bool] = []
	director.playback_state_changed.connect(func(playing: bool) -> void: states.append(playing))
	return states


static func _record_spawns(director: ReplayDirector) -> Array[String]:
	var spawned: Array[String] = []
	director.actor_spawned.connect(func(actor_id: String, _state: ActorVisualState) -> void: spawned.append(actor_id))
	return spawned


static func _bools(states: Array[bool]) -> String:
	var parts: Array[String] = []
	for playing in states:
		parts.append(str(playing))
	return ",".join(parts)


static func _settled(director: ReplayDirector, actor_id: String) -> Vector2:
	var state: ActorVisualState = director.get_actors_snapshot().get(actor_id)
	return state.position


func _test_load_and_step() -> void:
	var director := _director()
	var frames := _record_frames(director)
	var ended := _record_ended(director)
	var spawned := _record_spawns(director)

	director.load_playback(_fixture())
	TestFramework.assert_equal("0/4", ",".join(frames))
	TestFramework.assert_equal(0, director.get_current_frame())
	TestFramework.assert_equal(TOTAL_FRAMES, director.get_total_frames())
	TestFramework.assert_false(director.is_playing())
	TestFramework.assert_false(director.is_ended())
	TestFramework.assert_equal(1, director.get_actors_snapshot().size())

	# 帧 0 的事件不处理：台面来自 world_snapshot
	director.step(100.0)
	TestFramework.assert_equal(1, director.get_current_frame())
	TestFramework.assert_equal(0, director.get_action_count())
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2.ZERO))

	director.step(100.0)
	TestFramework.assert_equal(2, director.get_current_frame())
	TestFramework.assert_equal("t1", ",".join(spawned))
	TestFramework.assert_true(director.get_actor_position("t1").is_equal_approx(Vector2(3.0, 3.0)))

	director.step(100.0)
	TestFramework.assert_equal(3, director.get_current_frame())
	TestFramework.assert_equal(1, director.get_action_count())
	TestFramework.assert_near(director.get_actor_position("u1").x, 100.0 / 150.0, 0.001)
	TestFramework.assert_false(director.is_ended())
	TestFramework.assert_equal(0, ended.size())

	# 最后一帧：卡片走完（elapsed 200 ≥ 150）、步进器排空 → 同趟结束
	director.step(100.0)
	TestFramework.assert_equal(TOTAL_FRAMES, director.get_current_frame())
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	TestFramework.assert_true(_settled(director, "u1").is_equal_approx(Vector2(1.0, 0.0)))
	TestFramework.assert_equal(0, director.get_action_count())
	TestFramework.assert_true(director.is_ended())
	TestFramework.assert_equal(1, ended.size())
	TestFramework.assert_equal("0/4,1/4,2/4,3/4,4/4", ",".join(frames))

	# 结束后 step 不再推帧
	director.step(100.0)
	TestFramework.assert_equal(TOTAL_FRAMES, director.get_current_frame())
	TestFramework.assert_equal(5, frames.size())
	director.free()


func _test_partial_and_multi_frame_steps() -> void:
	var director := _director()
	var spawned := _record_spawns(director)
	director.load_playback(_fixture())

	director.step(50.0)
	TestFramework.assert_true(0 == director.get_current_frame(), "不满一帧不推帧")
	director.step(50.0)
	TestFramework.assert_equal(1, director.get_current_frame())

	# 一次 step 跨两帧：帧 2 的 spawn 与帧 3 的 move 按帧序处理，卡片在同趟里以整段 delta 推进
	director.step(250.0)
	TestFramework.assert_equal(3, director.get_current_frame())
	TestFramework.assert_equal("t1", ",".join(spawned))
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)), "250ms ≥ 150ms 一趟走完")
	TestFramework.assert_equal(0, director.get_action_count())
	TestFramework.assert_false(director.is_ended(), "还差一帧")

	# 余 50ms 攒着：再来 50ms 满一帧 → 帧 4 → 结束
	director.step(50.0)
	TestFramework.assert_equal(TOTAL_FRAMES, director.get_current_frame())
	TestFramework.assert_true(director.is_ended())
	director.free()


func _test_reset_idempotent_and_replay_same() -> void:
	var director := _director()
	var states := _record_states(director)
	var frames := _record_frames(director)
	director.load_playback(_fixture())
	for _i in range(3):
		director.step(100.0)
	TestFramework.assert_true(1 == director.get_action_count(), "在飞")
	TestFramework.assert_equal(2, director.get_actors_snapshot().size())

	for attempt in range(2):
		director.reset()
		TestFramework.assert_true(0 == director.get_current_frame(), "reset 第 %d 次帧归 0" % attempt)
		TestFramework.assert_true(0 == director.get_action_count(), "reset 清步进器")
		TestFramework.assert_false(director.is_ended())
		TestFramework.assert_false(director.is_playing())
		TestFramework.assert_false(states.back())
		TestFramework.assert_equal("0/4", frames.back())
		var snapshot := director.get_actors_snapshot()
		TestFramework.assert_true(1 == snapshot.size(), "中途 spawn 的不在台面上")
		var u1: ActorVisualState = snapshot["u1"]
		TestFramework.assert_true(u1.position.is_equal_approx(Vector2.ZERO))
		TestFramework.assert_near(u1.target_hp, 100.0)
		TestFramework.assert_true(u1.is_alive)
		TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2.ZERO), "在飞插值一并归位")

	# 重放到结束，与首次一致；结束后 reset 再放一遍仍一致
	for attempt in range(2):
		for _i in range(TOTAL_FRAMES):
			director.step(100.0)
		TestFramework.assert_true(director.is_ended(), "第 %d 次重放结束" % attempt)
		TestFramework.assert_equal(2, director.get_actors_snapshot().size())
		TestFramework.assert_true(_settled(director, "u1").is_equal_approx(Vector2(1.0, 0.0)))
		TestFramework.assert_true(_settled(director, "t1").is_equal_approx(Vector2(3.0, 3.0)))
		director.reset()
	director.free()


func _test_play_pause_toggle() -> void:
	var director := _director()
	var states := _record_states(director)
	director.load_playback(_fixture())

	director.play()
	TestFramework.assert_true(director.is_playing())
	director.pause()
	TestFramework.assert_false(director.is_playing())
	director.toggle()
	TestFramework.assert_true(director.is_playing())
	director.toggle()
	TestFramework.assert_false(director.is_playing())
	TestFramework.assert_equal("true,false,true,false", _bools(states))
	director.set_speed(2.5)
	TestFramework.assert_near(director.get_speed(), 2.5)

	# step 不看播放态：暂停中也精确推进到结束，结束时报一次停播
	states.clear()
	for _i in range(TOTAL_FRAMES):
		director.step(100.0)
	TestFramework.assert_true(director.is_ended())
	TestFramework.assert_false(director.is_playing())
	TestFramework.assert_equal("false", _bools(states))

	# 结束态 toggle 无动作
	states.clear()
	director.toggle()
	TestFramework.assert_equal(0, states.size())
	TestFramework.assert_false(director.is_playing())

	# 结束态 play 自动 reset 再播
	director.play()
	TestFramework.assert_true(director.is_playing())
	TestFramework.assert_equal(0, director.get_current_frame())
	TestFramework.assert_false(director.is_ended())
	TestFramework.assert_equal("false,true", _bools(states))
	director.free()


func _test_tick_interval_and_reload() -> void:
	var director := _director()
	var spawned := _record_spawns(director)
	var actors: Array[PlaybackData.ActorInitData] = [_init_data("u1", 0, 0, 100.0, 100.0)]
	var frames: Array[PlaybackData.FrameData] = [_frame(1, [_spawn_event("t1", 3, 3)])]

	# tick_interval 50：每 50ms 一帧
	director.load_playback(_record(actors, frames, 2, 50))
	director.step(50.0)
	TestFramework.assert_equal(1, director.get_current_frame())
	TestFramework.assert_equal("t1", ",".join(spawned))
	director.step(50.0)
	TestFramework.assert_equal(2, director.get_current_frame())
	TestFramework.assert_true(director.is_ended())

	# reload 换片：帧归 0、账本按新录像重建（t1 不在）、在飞卡片清空
	var moving: Array[PlaybackData.FrameData] = [_frame(1, [_move_event("u1", 4, 0, 400.0)])]
	director.load_playback(_record(actors, moving, 3))
	director.step(100.0)
	TestFramework.assert_equal(1, director.get_action_count())
	var none: Array[PlaybackData.FrameData] = []
	director.load_playback(_record(actors, none, 2, 0))
	TestFramework.assert_equal(0, director.get_current_frame())
	TestFramework.assert_equal(0, director.get_action_count())
	TestFramework.assert_equal(1, director.get_actors_snapshot().size())
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2.ZERO))
	TestFramework.assert_false(director.is_ended())

	# tick_interval 0 退回 100ms
	director.step(50.0)
	TestFramework.assert_equal(0, director.get_current_frame())
	director.step(50.0)
	TestFramework.assert_equal(1, director.get_current_frame())
	director.free()
