## 集成 smoke:同帧 ADD + UPDATE + REMOVE 经过完整 ActionScheduler → RenderWorld 链路。
## 复现"3 → 1 → 消失"bug —— 验证同帧多事件是否正确合并。
extends Node


func _ready() -> void:
	print("=== Smoke: Buff pipeline (scheduler + render world) ===")
	Log.set_level(Log.LogLevel.WARNING)

	var record := ReplayData.BattleRecord.new()
	record.meta = ReplayData.BattleMeta.new()
	record.map_config = {"radius": 3, "orientation": "flat", "hex_size": 1.0, "grid_type": "hex"}
	record.configs = {"positionFormats": {"Character": "hex"}}
	var actor_init := ReplayData.ActorInitData.new()
	actor_init.id = "hero_1"
	actor_init.type = "Character"
	actor_init.team = 0
	actor_init.position = [0, 0, 0]
	actor_init.attributes = {"hp": 100.0, "maxHp": 100.0}
	record.initial_actors = [actor_init]

	var rw := FrontendRenderWorld.new()
	rw.initialize_from_replay(record)
	var scheduler := FrontendActionScheduler.new()
	var registry := FrontendDefaultRegistry.create()

	# ===== Frame 1: 模拟 grant 同帧多事件:AbilityGranted(3) + damage + StacksChanged(3→2) =====
	var f1_events: Array[Dictionary] = [
		{
			"kind": GameEvent.ABILITY_GRANTED_EVENT,
			"actorId": "hero_1",
			"ability": {
				"id": "poison_inst_1",
				"instanceId": "poison_inst_1",
				"configId": "buff_poison",
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
			"actorId": "hero_1",
			"abilityInstanceId": "poison_inst_1",
			"abilityConfigId": "buff_poison",
			"oldStacks": 3,
			"newStacks": 2,
		},
	]
	_run_frame(scheduler, registry, rw, f1_events, "F1 grant+tick1")

	var actor: FrontendActorRenderState = rw.get_actors_snapshot()["hero_1"]
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
			"actorId": "hero_1",
			"abilityInstanceId": "poison_inst_1",
			"abilityConfigId": "buff_poison",
			"oldStacks": 2,
			"newStacks": 1,
		},
	]
	_run_frame(scheduler, registry, rw, f2_events, "F2 tick2")
	actor = rw.get_actors_snapshot()["hero_1"]
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
			"actorId": "hero_1",
			"abilityInstanceId": "poison_inst_1",
			"abilityConfigId": "buff_poison",
			"oldStacks": 1,
			"newStacks": 0,
		},
		{
			"kind": GameEvent.ABILITY_REMOVED_EVENT,
			"actorId": "hero_1",
			"abilityInstanceId": "poison_inst_1",
		},
	]
	_run_frame(scheduler, registry, rw, f3_events, "F3 tick3+remove")
	actor = rw.get_actors_snapshot()["hero_1"]
	print("  F3 result: buffs.size=%d" % actor.buffs.size())
	if actor.buffs.size() != 0:
		_fail("F3: expected buffs.size=0 after remove, got %d" % actor.buffs.size())
		return

	print("SMOKE_TEST_RESULT: PASS - same-frame ADD+UPDATE merges correctly (3→2 / 2→1 / 1→0/remove)")
	GameWorld.destroy()
	get_tree().quit(0)


func _run_frame(
	scheduler: FrontendActionScheduler,
	registry: FrontendVisualizerRegistry,
	rw: FrontendRenderWorld,
	events: Array[Dictionary],
	tag: String
) -> void:
	var ctx := rw.as_context()
	for event in events:
		var actions := registry.translate(event, ctx)
		print("  [%s] event %s → %d actions" % [tag, event["kind"], actions.size()])
		scheduler.enqueue(actions)
	# 模拟 BattleDirector._tick 后半段
	var result := scheduler.tick(100.0)  # 100ms = LOGIC_TICK_MS
	rw.apply_actions(result.active_actions)
	rw.apply_actions(result.completed_this_tick)
	rw.cleanup(rw.get_world_time())
	rw.flush_dirty_actors()


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)
