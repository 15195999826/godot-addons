## End-to-end smoke: Surge buff (GRANTED_SELF + on_timeline_start)
##
## 走完整 Director → Visualizer → RenderWorld → UnitView 链路,
## 在每帧推进后断言 UnitView._buff_label.text 序列。
##
## 此 smoke 现在手工构造 PlaybackData, 不依赖 headless scenario harness, 才能
## 复现 BattleRecorder 把 pending(AbilityGranted)放在 collector(StacksChanged)
## 之后的真实顺序问题。
##
## 修复前(pending 在 collector 后):frontend 看到 StacksChanged 早于 AbilityGranted
## → UPDATE 静默失败 → ADD primary=3 → 显示 U3 → 下一帧 U1 → 消失(漏 U2)。
##
## 修复后(pending 在 collector 前,见 battle_recorder.gd):AbilityGranted 先到 →
## ADD primary=3 → UPDATE primary=2 → 显示 U3 一闪即变 U2(同帧合并到最终 primary=2,
## 实际 unit_view 渲染只看到 U2) → U1 → 消失。
extends Node


## smoke 实际只需要 ~0.5s 跑完所有 label transitions (见 _label_history 序列: ""→U2→U1→""
## 在 t=0.42 完成). 之前 30s 与 launcher default_timeout_ms 撞车导致 parallel run 下
## TIMEOUT. 降到 5s 留充足余量但不再撞 launcher 上限.
const TIMEOUT_SEC := 5.0


var _director: FrontendBattleDirector
var _unit_view: FrontendUnitView
var _label_history: Array[String] = []
var _last_label: String = "<init>"
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	print("=== Smoke: Surge UnitView (grant+tick same frame) ===")
	Log.set_level(Log.LogLevel.WARNING)

	HexBattleAllSkills.register_all_timelines()

	# 构造最小 PlaybackData:1 actor(team A),frame 0 同帧 grant Surge + first tick
	# (3→2),frame 20 tick(2→1),frame 40 tick(1→0)+remove。
	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	record.meta.total_frames = 50
	record.meta.tick_interval = 100
	var snap := PlaybackData.WorldSnapshot.new()
	snap.map_config = {"radius": 3, "orientation": "flat", "hex_size": 1.0, "grid_type": "hex"}
	snap.position_formats = {"Character": "hex"}
	record.world_snapshot = snap

	var actor_init := PlaybackData.ActorInitData.new()
	actor_init.id = "hero_1"
	actor_init.type = "Character"
	actor_init.display_name = "Hero"
	actor_init.team = 0
	actor_init.position = [0, 0, 0]
	actor_init.attributes = {"hp": 100.0, "maxHp": 100.0}
	snap.actors = [actor_init]

	# BattleDirector 从 _current_frame=0 推到 next_frame=1 才查事件,
	# 所以 frame 0 永远不被处理。事件从 frame 1 开始。
	var f1 := PlaybackData.FrameData.new()
	f1.frame = 1
	f1.events = [
		_grant_event("hero_1", "surge_inst_1", HexBattleSurgeBuff.CONFIG_ID, 3),
		_stacks_event("hero_1", "surge_inst_1", HexBattleSurgeBuff.CONFIG_ID, 3, 2),
	]
	var f21 := PlaybackData.FrameData.new()
	f21.frame = 21
	f21.events = [
		_stacks_event("hero_1", "surge_inst_1", HexBattleSurgeBuff.CONFIG_ID, 2, 1),
	]
	var f41 := PlaybackData.FrameData.new()
	f41.frame = 41
	f41.events = [
		_stacks_event("hero_1", "surge_inst_1", HexBattleSurgeBuff.CONFIG_ID, 1, 0),
		{
			"kind": GameEvent.ABILITY_REMOVED_EVENT,
			"actorId": "hero_1",
			"abilityInstanceId": "surge_inst_1",
		},
	]
	record.timeline = [f1, f21, f41]

	# 起 Director + UnitView,wire actor_state_changed → unit_view.update_state
	_director = FrontendBattleDirector.new()
	_director.name = "BattleDirector"
	add_child(_director)
	_director.load_playback(record)

	_unit_view = FrontendUnitView.new()
	_unit_view.name = "HeroView"
	add_child(_unit_view)
	# UnitView 需要先 _ready 才有 _buff_label
	await get_tree().process_frame
	_unit_view.initialize("hero_1", "Hero", 0, 100.0, 100.0)

	_director.actor_state_changed.connect(_on_actor_state_changed)
	_director.set_speed(10.0)  # 加速,5 frame/s real time
	_director.play()
	print("Step: playing replay (50 frames @ 10x)...")


func _process(delta: float) -> void:
	if _finished:
		return

	# 抓 buff label 文本变化序列
	var current_text := ""
	if _unit_view != null and is_instance_valid(_unit_view):
		var buff_view := _unit_view.get_buff_row_view()
		if buff_view != null and is_instance_valid(buff_view):
			current_text = buff_view.get_label_text()
	if current_text != _last_label:
		_last_label = current_text
		_label_history.append(current_text)
		print("  [t=%.2f] _buff_label.text = '%s'" % [_elapsed, current_text])

	_elapsed += delta
	if _elapsed >= TIMEOUT_SEC:
		_assert_and_finish()


func _on_actor_state_changed(actor_id: String, state: FrontendActorRenderState) -> void:
	if actor_id == "hero_1":
		_unit_view.update_state(state)


func _on_playback_ended() -> void:
	_assert_and_finish()


func _assert_and_finish() -> void:
	if _finished:
		return
	# 期望 label 序列(去 init "<init>"):U3 → U2 → U1 → ""(消失)
	# 容忍空 label 多次(初始 + 最终消失)。关键检查:U3 后必须有 U2,不能直接 U1。
	var u_seq: Array[String] = []
	for s in _label_history:
		if s.begins_with("U"):
			u_seq.append(s)
	print("---")
	print("Full label history: %s" % str(_label_history))
	print("U-sequence:         %s" % str(u_seq))

	# 同帧 ADD(3) + UPDATE(3→2) 应合并为 U2,**不应**看到 U3 闪烁。
	# 后续帧 UPDATE → U1 → REMOVE → ""。
	# 期望 u_seq = ["U2", "U1"]。
	if u_seq != ["U2", "U1"]:
		_fail("expected [U2, U1] (same-frame ADD+UPDATE merges to UPDATE), got %s" % str(u_seq))
		return
	# 起止应是 ""(buff 未挂)和 ""(buff 移除后)。
	if _label_history.front() != "" or _label_history.back() != "":
		_fail("label history should start/end with '': %s" % str(_label_history))
		return
	_pass()


func _grant_event(actor_id: String, instance_id: String, config_id: String, stacks: int) -> Dictionary:
	return {
		"kind": GameEvent.ABILITY_GRANTED_EVENT,
		"actorId": actor_id,
		"ability": {
			"id": instance_id,
			"instanceId": instance_id,
			"configId": config_id,
			"displayName": "Surge",
			"stacks": stacks,
		},
	}


func _stacks_event(actor_id: String, instance_id: String, config_id: String, old_s: int, new_s: int) -> Dictionary:
	return {
		"kind": GameEvent.ABILITY_STACKS_CHANGED_EVENT,
		"actorId": actor_id,
		"abilityInstanceId": instance_id,
		"abilityConfigId": config_id,
		"oldStacks": old_s,
		"newStacks": new_s,
	}


func _pass() -> void:
	_finished = true
	print("SMOKE_TEST_RESULT: PASS - same-frame ADD+UPDATE merges to U2 → U1 → '' as expected")
	GameWorld.destroy()
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_finished = true
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)
