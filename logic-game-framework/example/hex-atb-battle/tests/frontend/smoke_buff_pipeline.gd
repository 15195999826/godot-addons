## 集成 smoke:同帧 ADD + UPDATE + REMOVE 走完整的 VisualDirector.pump(翻译 → 步进 → 记账)链路。
## 复现"3 → 1 → 消失"bug —— 验证同帧多事件是否正确合并。
## 台面经 ReplayDirector.load_playback 重建(零帧录像),之后每趟直接喂 pump;账本只走 Director 的公开读法。
extends Node


## 每趟 pump 推进的表演时间(毫秒)= 录像 tick_interval
const STEP_MS := 100.0


func _ready() -> void:
	print("=== Smoke: Buff pipeline (Director.pump) ===")
	Log.set_level(Log.LogLevel.WARNING)

	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	var snap := PlaybackData.WorldSnapshot.new()
	snap.map_config = {"radius": 3, "orientation": "flat", "hex_size": 1.0, "grid_type": "hex"}
	snap.position_formats = {"Character": "hex"}
	record.world_snapshot = snap
	var actor_init := PlaybackData.ActorInitData.new()
	actor_init.id = "hero_1"
	actor_init.type = "Character"
	actor_init.team = 0
	actor_init.position = [0, 0, 0]
	actor_init.attributes = {"hp": 100.0, "max_hp": 100.0}
	snap.actors = [actor_init]

	var director := ReplayDirector.new(FrontendDefaultRegistry.create())
	add_child(director)
	director.load_playback(record)

	# ===== Frame 1: 模拟 grant 同帧多事件:AbilityGranted(3) + damage + StacksChanged(3→2) =====
	var f1_events: Array[Dictionary] = [
		{
			"kind": GameEvent.ABILITY_GRANTED_EVENT,
			"actor_id": "hero_1",
			"ability": {
				"id": "poison_inst_1",
				"config_id": "buff_poison",
				"stacks": 3,
			},
		},
		{
			"kind": "damage",
			"target_actor_id": "hero_1",
			"damage": 3.0,
			"damage_type": "pure",
			"actual_life_damage": 3.0,
			"shield_absorbed": 0.0,
			"consumption_records": [],
		},
		{
			"kind": GameEvent.ABILITY_STACKS_CHANGED_EVENT,
			"actor_id": "hero_1",
			"ability_instance_id": "poison_inst_1",
			"ability_config_id": "buff_poison",
			"old_stacks": 3,
			"new_stacks": 2,
		},
	]
	_run_frame(director, f1_events, "F1 grant+tick1")

	var actor: ActorVisualState = director.get_actors_snapshot()["hero_1"]
	print("  F1 result: buffs.size=%d, buffs[0].primary=%s" % [
		actor.buffs.size(),
		"N/A" if actor.buffs.is_empty() else str(actor.buffs[0].primary),
	])
	if actor.buffs.size() != 1 or not is_equal_approx(actor.buffs[0].primary, 2.0):
		_fail("F1: expected primary=2 (ADD 3 then UPDATE→2), got %s" % str(actor.buffs))
		return

	# ===== Frame 2: tick2 → damage(2) + StacksChanged(2→1) =====
	var f2_events: Array[Dictionary] = [
		{
			"kind": "damage",
			"target_actor_id": "hero_1",
			"damage": 2.0,
			"damage_type": "pure",
			"actual_life_damage": 2.0,
			"shield_absorbed": 0.0,
			"consumption_records": [],
		},
		{
			"kind": GameEvent.ABILITY_STACKS_CHANGED_EVENT,
			"actor_id": "hero_1",
			"ability_instance_id": "poison_inst_1",
			"ability_config_id": "buff_poison",
			"old_stacks": 2,
			"new_stacks": 1,
		},
	]
	_run_frame(director, f2_events, "F2 tick2")
	actor = director.get_actors_snapshot()["hero_1"]
	print("  F2 result: buffs[0].primary=%s" % str(actor.buffs[0].primary))
	if not is_equal_approx(actor.buffs[0].primary, 1.0):
		_fail("F2: expected primary=1, got %s" % str(actor.buffs[0].primary))
		return

	# ===== Frame 3: tick3 → damage(1) + StacksChanged(1→0) + AbilityRemoved =====
	var f3_events: Array[Dictionary] = [
		{
			"kind": "damage",
			"target_actor_id": "hero_1",
			"damage": 1.0,
			"damage_type": "pure",
			"actual_life_damage": 1.0,
			"shield_absorbed": 0.0,
			"consumption_records": [],
		},
		{
			"kind": GameEvent.ABILITY_STACKS_CHANGED_EVENT,
			"actor_id": "hero_1",
			"ability_instance_id": "poison_inst_1",
			"ability_config_id": "buff_poison",
			"old_stacks": 1,
			"new_stacks": 0,
		},
		{
			"kind": GameEvent.ABILITY_REMOVED_EVENT,
			"actor_id": "hero_1",
			"ability_instance_id": "poison_inst_1",
		},
	]
	_run_frame(director, f3_events, "F3 tick3+remove")
	actor = director.get_actors_snapshot()["hero_1"]
	print("  F3 result: buffs.size=%d" % actor.buffs.size())
	if actor.buffs.size() != 0:
		_fail("F3: expected buffs.size=0 after remove, got %d" % actor.buffs.size())
		return

	print("SMOKE_TEST_RESULT: PASS - same-frame ADD+UPDATE merges correctly (3→2 / 2→1 / 1→0/remove)")
	GameWorld.shutdown()
	get_tree().quit(0)


## 一趟 = 一个逻辑帧的事件 + STEP_MS 表演时间,与 ReplayDirector 帧时钟喂 pump 的口径相同
func _run_frame(director: VisualDirector, events: Array[Dictionary], tag: String) -> void:
	director.pump(STEP_MS, events)
	print("  [%s] pumped %d events" % [tag, events.size()])


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.shutdown()
	get_tree().quit(1)
