## Smoke test: BuffVisualizer + RenderWorld.actor.buffs 数据契约
##
## 白盒测试,不走完整 main.tscn 流程。直接构造 ReplayData + 手动喂事件给
## VisualizerRegistry,断言 actor.buffs 的最终状态。
##
## 覆盖事件类型:
##   1. AbilityGranted (poison) → ADD,buffs[0].primary == 3
##   2. AbilityStacksChanged (3→2) → UPDATE,buffs[0].primary == 2
##   3. AbilityGranted (ward) → ADD,buffs[1].primary == 30 (capacity 当 current)
##   4. DamageEvent (consumption_records ward 吸收 10) → UPDATE,buffs[1].primary == 20
##   5. AbilityRemoved (poison) → REMOVE,buffs.size() == 1
##
## 退出码: 0 PASS / 1 FAIL,标记: "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


func _ready() -> void:
	print("=== Smoke Test: Buff UI Data Contract ===")
	Log.set_level(Log.LogLevel.WARNING)

	# Step 1: 构造最小 BattleRecord (一个 actor,空 timeline)
	var record := ReplayData.BattleRecord.new()
	record.meta = ReplayData.BattleMeta.new()
	record.meta.total_frames = 0
	record.map_config = {"radius": 3, "orientation": "flat", "hex_size": 1.0, "grid_type": "hex"}
	record.configs = {"positionFormats": {"Character": "hex"}}
	var actor_init := ReplayData.ActorInitData.new()
	actor_init.id = "hero_1"
	actor_init.type = "Character"
	actor_init.display_name = "Hero"
	actor_init.team = 0
	actor_init.position = [0, 0, 0]
	actor_init.attributes = {"hp": 100.0, "maxHp": 100.0}
	record.initial_actors = [actor_init]

	# Step 2: 初始化 RenderWorld + Visualizer Registry
	var render_world := FrontendRenderWorld.new()
	render_world.initialize_from_replay(record)
	var registry := FrontendDefaultRegistry.create()
	var ctx := render_world.as_context()

	# Step 3: 喂事件并应用
	# Event 1: AbilityGranted (poison, stacks=3)
	_apply_event(registry, ctx, render_world, {
		"kind": GameEvent.ABILITY_GRANTED_EVENT,
		"actorId": "hero_1",
		"ability": {
			"id": "poison_inst_1",
			"instanceId": "poison_inst_1",
			"configId": "buff_poison",
			"displayName": "中毒",
			"stacks": 3,
		},
	})
	render_world.flush_dirty_actors()
	var actor: FrontendActorRenderState = render_world.get_actors_snapshot()["hero_1"]
	if actor.buffs.size() != 1:
		_fail("after poison grant: buffs.size = %d (expected 1)" % actor.buffs.size())
		return
	if actor.buffs[0].id != "poison_inst_1" or actor.buffs[0].config_id != "buff_poison":
		_fail("after poison grant: id/config_id mismatch")
		return
	if not is_equal_approx(actor.buffs[0].primary, 3.0):
		_fail("after poison grant: primary=%f (expected 3)" % actor.buffs[0].primary)
		return
	print("  + Step 1 OK: AbilityGranted poison → buffs[0].primary=3")

	# Event 2: AbilityStacksChanged (3 → 2)
	_apply_event(registry, ctx, render_world, {
		"kind": GameEvent.ABILITY_STACKS_CHANGED_EVENT,
		"actorId": "hero_1",
		"abilityInstanceId": "poison_inst_1",
		"abilityConfigId": "buff_poison",
		"oldStacks": 3,
		"newStacks": 2,
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if not is_equal_approx(actor.buffs[0].primary, 2.0):
		_fail("after stacks 3→2: primary=%f (expected 2)" % actor.buffs[0].primary)
		return
	print("  + Step 2 OK: AbilityStacksChanged 3→2 → buffs[0].primary=2")

	# Event 3: AbilityGranted (ward, capacity=30)
	_apply_event(registry, ctx, render_world, {
		"kind": GameEvent.ABILITY_GRANTED_EVENT,
		"actorId": "hero_1",
		"ability": {
			"id": "ward_inst_1",
			"instanceId": "ward_inst_1",
			"configId": "buff_ward",
			"displayName": "护盾术",
			"stacks": 1,
			"components": [{
				"type": "ShieldComponent",
				"data": {"current": 30.0, "capacity": 30.0},
			}],
		},
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if actor.buffs.size() != 2:
		_fail("after ward grant: buffs.size=%d (expected 2)" % actor.buffs.size())
		return
	if actor.buffs[1].id != "ward_inst_1":
		_fail("after ward grant: buffs[1].id=%s (expected ward_inst_1)" % actor.buffs[1].id)
		return
	if not is_equal_approx(actor.buffs[1].primary, 30.0):
		_fail("after ward grant: primary=%f (expected 30)" % actor.buffs[1].primary)
		return
	print("  + Step 3 OK: AbilityGranted ward → buffs[1].primary=30")

	# Event 4: DamageEvent (ward 吸收 10,remaining=20)
	_apply_event(registry, ctx, render_world, {
		"kind": "damage",
		"target_actor_id": "hero_1",
		"damage": 10.0,
		"damage_type": "physical",
		"is_critical": false,
		"is_reflected": false,
		"shield_absorbed": 10.0,
		"actual_life_damage": 0.0,
		"consumption_records": [{
			"shield_ability_id": "ward_inst_1",
			"shield_config_id": "buff_ward",
			"owner_actor_id": "hero_1",
			"capacity": 30.0,
			"remaining": 20.0,
			"absorbed": 10.0,
			"broken": false,
			"damage_type": "physical",
			"priority": 0,
		}],
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if not is_equal_approx(actor.buffs[1].primary, 20.0):
		_fail("after ward absorb 10: primary=%f (expected 20)" % actor.buffs[1].primary)
		return
	print("  + Step 4 OK: DamageEvent ward absorbed → buffs[1].primary=20")

	# Event 5: AbilityRemoved (poison)
	_apply_event(registry, ctx, render_world, {
		"kind": GameEvent.ABILITY_REMOVED_EVENT,
		"actorId": "hero_1",
		"abilityInstanceId": "poison_inst_1",
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if actor.buffs.size() != 1:
		_fail("after poison remove: buffs.size=%d (expected 1)" % actor.buffs.size())
		return
	if actor.buffs[0].id != "ward_inst_1":
		_fail("after poison remove: remaining buff id=%s (expected ward_inst_1)" % actor.buffs[0].id)
		return
	print("  + Step 5 OK: AbilityRemoved poison → buffs={ward_inst_1}")

	_pass()


## 把单个 event 喂给 registry,翻译出 actions,逐一 apply 到 render_world。
## 不走 ActionScheduler(buff state action duration=0,直接应用)。
func _apply_event(
	registry: FrontendVisualizerRegistry,
	ctx: FrontendVisualizerContext,
	render_world: FrontendRenderWorld,
	event: Dictionary
) -> void:
	var actions := registry.translate(event, ctx)
	# 包装成 ActiveAction 让 _apply_action 接受
	for action in actions:
		if action is FrontendApplyBuffStateAction:
			# 直接调内部 apply(_apply_action 是 private, 但 ApplyBuffStateAction
			# 是 duration=0 的瞬时动作,我们绕过 scheduler 直接应用)
			render_world._apply_apply_buff_state_action(action)


func _pass() -> void:
	print("SMOKE_TEST_RESULT: PASS - buff UI data contract verified across 5 event paths")
	GameWorld.destroy()
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)
