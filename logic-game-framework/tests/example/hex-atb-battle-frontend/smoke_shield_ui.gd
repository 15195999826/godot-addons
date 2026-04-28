## Smoke test: ShieldBarVisualizer + RenderWorld.actor.shields 数据契约
##
## 白盒测试,不走完整 main.tscn 流程。直接构造 ReplayData + 手动喂事件给
## VisualizerRegistry,断言 actor.shields 的最终状态。
##
## 覆盖事件类型:
##   1. AbilityGranted (ward, current=30, capacity=30) → ADD,shields[0].current=30
##   2. AbilityGranted (第二个 ward 独立实例, current=20) → ADD,shields.size=2
##   3. DamageEvent (consumption_records 第二盾吸 5,remaining=15) → UPDATE
##   4. AbilityRemoved (第一个 ward) → REMOVE,只剩第二盾
##   5. AbilityRemoved (第二个 ward) → REMOVE,shields 空
##
## 退出码: 0 PASS / 1 FAIL,标记: "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


func _ready() -> void:
	print("=== Smoke Test: Shield UI Data Contract ===")
	Log.set_level(Log.LogLevel.WARNING)

	# Step 1: 构造最小 BattleRecord
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

	# Event 1: AbilityGranted (ward inst 1, capacity=30, current=30)
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
				"data": {"current": 30.0, "capacity": 30.0, "priority": 0},
			}],
		},
	})
	var actor: FrontendActorRenderState = render_world.get_actors_snapshot()["hero_1"]
	if actor.shields.size() != 1:
		_fail("after ward1 grant: shields.size=%d (expected 1)" % actor.shields.size())
		return
	if actor.shields[0].id != "ward_inst_1":
		_fail("after ward1 grant: id=%s (expected ward_inst_1)" % actor.shields[0].id)
		return
	if not is_equal_approx(actor.shields[0].current, 30.0):
		_fail("after ward1 grant: current=%f (expected 30)" % actor.shields[0].current)
		return
	if not is_equal_approx(actor.shields[0].capacity, 30.0):
		_fail("after ward1 grant: capacity=%f (expected 30)" % actor.shields[0].capacity)
		return
	print("  + Step 1 OK: AbilityGranted ward_inst_1 → shields[0]={current=30,capacity=30}")

	# Event 2: AbilityGranted (ward inst 2 独立实例, current=20)
	_apply_event(registry, ctx, render_world, {
		"kind": GameEvent.ABILITY_GRANTED_EVENT,
		"actorId": "hero_1",
		"ability": {
			"id": "ward_inst_2",
			"instanceId": "ward_inst_2",
			"configId": "buff_ward",
			"displayName": "护盾术",
			"stacks": 1,
			"components": [{
				"type": "ShieldComponent",
				"data": {"current": 20.0, "capacity": 20.0, "priority": 0},
			}],
		},
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if actor.shields.size() != 2:
		_fail("after ward2 grant: shields.size=%d (expected 2)" % actor.shields.size())
		return
	if actor.shields[1].id != "ward_inst_2":
		_fail("after ward2 grant: id[1]=%s (expected ward_inst_2)" % actor.shields[1].id)
		return
	if not is_equal_approx(actor.shields[1].current, 20.0):
		_fail("after ward2 grant: current=%f (expected 20)" % actor.shields[1].current)
		return
	print("  + Step 2 OK: 第二个 ward 独立实例 → shields.size=2")

	# Event 3: DamageEvent — ward_inst_2 吸收 5, remaining=15
	_apply_event(registry, ctx, render_world, {
		"kind": "damage",
		"target_actor_id": "hero_1",
		"damage": 5.0,
		"damage_type": "physical",
		"is_critical": false,
		"is_reflected": false,
		"shield_absorbed": 5.0,
		"actual_life_damage": 0.0,
		"consumption_records": [{
			"shield_ability_id": "ward_inst_2",
			"shield_config_id": "buff_ward",
			"owner_actor_id": "hero_1",
			"capacity": 20.0,
			"remaining": 15.0,
			"absorbed": 5.0,
			"broken": false,
			"damage_type": "physical",
			"priority": 0,
		}],
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if not is_equal_approx(actor.shields[1].current, 15.0):
		_fail("after damage absorb: ward_inst_2.current=%f (expected 15)" % actor.shields[1].current)
		return
	# ward_inst_1 不该被影响
	if not is_equal_approx(actor.shields[0].current, 30.0):
		_fail("after damage absorb: ward_inst_1.current=%f (expected 30, untouched)" % actor.shields[0].current)
		return
	print("  + Step 3 OK: DamageEvent ward_inst_2 吸收 → current 20→15, ward_inst_1 不变")

	# Event 4: AbilityRemoved (ward_inst_1)
	_apply_event(registry, ctx, render_world, {
		"kind": GameEvent.ABILITY_REMOVED_EVENT,
		"actorId": "hero_1",
		"abilityInstanceId": "ward_inst_1",
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if actor.shields.size() != 1:
		_fail("after ward1 remove: shields.size=%d (expected 1)" % actor.shields.size())
		return
	if actor.shields[0].id != "ward_inst_2":
		_fail("after ward1 remove: remaining id=%s (expected ward_inst_2)" % actor.shields[0].id)
		return
	print("  + Step 4 OK: AbilityRemoved ward_inst_1 → shields={ward_inst_2}")

	# Event 5: AbilityRemoved (ward_inst_2)
	_apply_event(registry, ctx, render_world, {
		"kind": GameEvent.ABILITY_REMOVED_EVENT,
		"actorId": "hero_1",
		"abilityInstanceId": "ward_inst_2",
	})
	actor = render_world.get_actors_snapshot()["hero_1"]
	if actor.shields.size() != 0:
		_fail("after ward2 remove: shields.size=%d (expected 0)" % actor.shields.size())
		return
	print("  + Step 5 OK: AbilityRemoved ward_inst_2 → shields 空")

	_pass()


## 把单个 event 喂给 registry,翻译出 actions,逐一 apply 到 render_world。
## 不走 ActionScheduler(shield state action duration=0,直接应用)。
## 同时调 buff state(buff_visualizer 也产出 action,要一起 apply 保证 dirty/snapshot 一致)。
func _apply_event(
	registry: FrontendVisualizerRegistry,
	ctx: FrontendVisualizerContext,
	render_world: FrontendRenderWorld,
	event: Dictionary
) -> void:
	var actions := registry.translate(event, ctx)
	for action in actions:
		if action is FrontendApplyShieldStateAction:
			render_world._apply_apply_shield_state_action(action)
		elif action is FrontendApplyBuffStateAction:
			render_world._apply_apply_buff_state_action(action)


func _pass() -> void:
	print("SMOKE_TEST_RESULT: PASS - shield UI data contract verified across 5 event paths")
	GameWorld.destroy()
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)
