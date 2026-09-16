extends Node

## ProjectileSystem 事件派发合同（stdlib）：
## 1. HIT / MISS / PIERCE 在产出点推所属 instance 的 event_collector 后当场 process_post_event——与 Action 内伤害同语义：
##    订阅者的反应落在该事件与 despawn 之间、同一 tick 内，不等任何人回扫 collector
## 2. handler 跑的时候弹体仍在注册表；auto_remove 到本 tick 末才 remove
## 3. despawn 只录不派发
## 4. system 未注册进 instance 时静默短路：弹体状态照常推进，不派发、不推录像、不报错

const ECHO_KIND := "projectile_probe_echo"


## 带 AbilitySet 的最小 actor；position 可写，供距离碰撞检测。
class ProbeActor:
	extends BattleActor

	var ability_set: AbilitySet
	var probe_position: Vector3 = Vector3.ZERO

	func _init() -> void:
		type = "projectile_probe"
		ability_set = AbilitySet.create("")

	func get_ability_set() -> AbilitySet:
		return ability_set

	func _get_position() -> Vector3:
		return probe_position


## post 触发时往同一个 collector 推一条回声，记下弹体此刻是否仍在注册表。
class EchoAction:
	extends Action.BaseAction

	func _init() -> void:
		super._init(TargetSelector.new())

	func execute(ctx: ExecutionContext) -> ActionResult:
		var source := ctx.get_original_event()
		var projectile_id := str(source.get("projectile_id", ""))
		ctx.event_collector.push({
			"kind": ECHO_KIND,
			"echo_of": str(source.get("kind", "")),
			"projectile_id": projectile_id,
			"projectile_registered": ctx.instance != null and ctx.instance.get_actor(projectile_id) != null,
		})
		return ActionResult.create_success_result([])


func _init() -> void:
	TestFramework.register_test("ProjectileSystem: hit dispatches at emission, before despawn, with the projectile still registered", _test_hit_dispatch)
	TestFramework.register_test("ProjectileSystem: miss (timeout) dispatches at emission the same way", _test_miss_dispatch)
	TestFramework.register_test("ProjectileSystem: pierce dispatches per target, the final hit dispatches then despawns", _test_pierce_dispatch)
	TestFramework.register_test("ProjectileSystem: unregistered system short-circuits without dispatching", _test_unregistered_short_circuit)


func _test_hit_dispatch() -> void:
	var instance := _create_instance("projectile_system_hit")
	var shooter := _spawn_shooter(instance, [ProjectileEvents.PROJECTILE_HIT_EVENT])
	var target := instance.add_actor(ProbeActor.new()) as ProbeActor
	instance.add_system(ProjectileSystem.new(DistanceCollisionDetector.new(1.0), true))
	var projectile := _launch(instance, shooter, {}, target.get_id())

	instance.base_tick(100.0)

	var events := instance.event_collector.collect()
	TestFramework.assert_equal(
		[ProjectileEvents.PROJECTILE_HIT_EVENT, ECHO_KIND, ProjectileEvents.PROJECTILE_DESPAWN_EVENT], _kinds(events))
	var echo := _event_at(events, 1)
	TestFramework.assert_equal(projectile.id, str(echo.get("projectile_id", "")))
	TestFramework.assert_true(bool(echo.get("projectile_registered", false)), "handler runs while the projectile is still registered")
	TestFramework.assert_true(instance.get_actor(projectile.id) == null, "auto_remove drops the projectile at the end of the tick")
	GameWorld.destroy_instance(instance.id)


func _test_miss_dispatch() -> void:
	var instance := _create_instance("projectile_system_miss")
	var shooter := _spawn_shooter(instance, [ProjectileEvents.PROJECTILE_MISS_EVENT])
	instance.add_system(ProjectileSystem.new(DistanceCollisionDetector.new(1.0), true))
	var projectile := _launch(instance, shooter, {ProjectileActor.CFG_MAX_LIFETIME: 50.0})

	instance.base_tick(100.0)

	var events := instance.event_collector.collect()
	TestFramework.assert_equal(
		[ProjectileEvents.PROJECTILE_MISS_EVENT, ECHO_KIND, ProjectileEvents.PROJECTILE_DESPAWN_EVENT], _kinds(events))
	TestFramework.assert_equal("timeout", str(_event_at(events, 0).get("reason", "")))
	TestFramework.assert_true(bool(_event_at(events, 1).get("projectile_registered", false)), "handler runs while the projectile is still registered")
	TestFramework.assert_true(instance.get_actor(projectile.id) == null, "auto_remove drops the projectile at the end of the tick")
	GameWorld.destroy_instance(instance.id)


func _test_pierce_dispatch() -> void:
	var instance := _create_instance("projectile_system_pierce")
	var shooter := _spawn_shooter(instance, [ProjectileEvents.PROJECTILE_PIERCE_EVENT, ProjectileEvents.PROJECTILE_HIT_EVENT])
	var first := instance.add_actor(ProbeActor.new()) as ProbeActor
	var second := instance.add_actor(ProbeActor.new()) as ProbeActor
	instance.add_system(ProjectileSystem.new(DistanceCollisionDetector.new(1.0), true))
	var projectile := _launch(instance, shooter, {ProjectileActor.CFG_PIERCING: true, ProjectileActor.CFG_MAX_PIERCE_COUNT: 2})

	instance.base_tick(100.0)
	var after_first := instance.event_collector.collect()
	TestFramework.assert_equal([ProjectileEvents.PROJECTILE_PIERCE_EVENT, ECHO_KIND], _kinds(after_first))
	TestFramework.assert_equal(first.get_id(), str(_event_at(after_first, 0).get("target_actor_id", "")))
	TestFramework.assert_true(bool(_event_at(after_first, 1).get("projectile_registered", false)), "pierce handler sees the projectile registered")
	TestFramework.assert_true(projectile.is_flying(), "a pierced projectile keeps flying")

	instance.base_tick(100.0)
	var events := instance.event_collector.collect()
	TestFramework.assert_equal([
		ProjectileEvents.PROJECTILE_PIERCE_EVENT, ECHO_KIND,
		ProjectileEvents.PROJECTILE_HIT_EVENT, ECHO_KIND,
		ProjectileEvents.PROJECTILE_DESPAWN_EVENT,
	], _kinds(events))
	TestFramework.assert_equal(second.get_id(), str(_event_at(events, 2).get("target_actor_id", "")))
	TestFramework.assert_equal(ProjectileEvents.PROJECTILE_PIERCE_EVENT, str(_event_at(events, 1).get("echo_of", "")))
	TestFramework.assert_equal(ProjectileEvents.PROJECTILE_HIT_EVENT, str(_event_at(events, 3).get("echo_of", "")))
	TestFramework.assert_true(bool(_event_at(events, 3).get("projectile_registered", false)), "final hit handler sees the projectile registered")
	TestFramework.assert_true(instance.get_actor(projectile.id) == null, "auto_remove drops the projectile after the final hit")
	GameWorld.destroy_instance(instance.id)


func _test_unregistered_short_circuit() -> void:
	var system := ProjectileSystem.new(DistanceCollisionDetector.new(1.0), true)
	var projectile := ProjectileActor.new()
	projectile.launch({"start_position": Vector3.ZERO})

	system.force_hit(projectile, "nobody", Vector3.ZERO)

	TestFramework.assert_equal(ProjectileActor.STATE_HIT, projectile.get_projectile_state())
	TestFramework.assert_equal(1, system.get_pending_removal_ids().size())


# ========== 夹具 ==========

static func _create_instance(instance_id: String) -> GameplayInstance:
	GameWorld.shutdown()
	var instance := GameWorld.create_instance(GameplayInstance.new(instance_id))
	instance.start()
	return instance


## 射手：监听给定 kind 的投射物事件，触发时推回声。
static func _spawn_shooter(instance: GameplayInstance, kinds: Array[String]) -> ProbeActor:
	var shooter := instance.add_actor(ProbeActor.new()) as ProbeActor
	var builder := AbilityConfig.builder().config_id("projectile_probe_listener")
	for kind in kinds:
		builder.component_config(NoInstanceConfig.builder().trigger(TriggerConfig.new(kind)).action(EchoAction.new()).build())
	shooter.ability_set.grant_ability(Ability.new(builder.build(), shooter.get_id()))
	return shooter


## 原地发射（起点 = 目标点 = 原点）：目标站在原点即命中，无目标则到期 miss。
static func _launch(instance: GameplayInstance, shooter: ProbeActor, config: Dictionary, target_id: String = "") -> ProjectileActor:
	var projectile := instance.add_actor(ProjectileActor.new(config)) as ProjectileActor
	projectile.launch({
		"source_actor_id": shooter.get_id(),
		"target_actor_id": target_id,
		"start_position": Vector3.ZERO,
		"target_position": Vector3.ZERO,
	})
	return projectile


static func _kinds(events: Array[Dictionary]) -> Array[String]:
	var kinds: Array[String] = []
	for event in events:
		kinds.append(str(event.get("kind", "")))
	return kinds


static func _event_at(events: Array[Dictionary], index: int) -> Dictionary:
	if index < 0 or index >= events.size():
		return {}
	return events[index]
