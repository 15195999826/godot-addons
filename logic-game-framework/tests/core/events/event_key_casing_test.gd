extends Node

## 事件 dict key 与 kind 字面量只有一种拼写：snake_case（跨层契约，JS 解析器 / 录像 / 表演层都按它读）。
## 对 GameEvent 每个内嵌类、ProjectileEvents 每个工厂、PlaybackData 每个内部类用哑参构造，
## to_dict() 的全部 key（递归一层）与 kind 值都要匹配 ^[a-z0-9_]+$；kind 常量与
## RawAttributeSet 的监听 dict 同样受约束。

const SNAKE_CASE_PATTERN := "^[a-z0-9_]+$"


func _init() -> void:
	TestFramework.register_test("GameEvent to_dict keys and kinds are snake_case", _test_game_event_dicts)
	TestFramework.register_test("Event kind constants are snake_case", _test_kind_constants)
	TestFramework.register_test("ProjectileEvents factory dict keys and kinds are snake_case", _test_projectile_event_dicts)
	TestFramework.register_test("PlaybackData to_dict keys are snake_case", _test_playback_dicts)
	TestFramework.register_test("RawAttributeSet change listener dict keys are snake_case", _test_attribute_listener_dict)


func _test_game_event_dicts() -> void:
	var components: Array[String] = ["component_a"]
	var target_ids: Array[String] = ["actor_2", "actor_3"]
	var dicts: Array[Dictionary] = [
		GameEvent.ActorSpawned.create("actor_1", {"id": "actor_1"}).to_dict(),
		GameEvent.ActorDestroyed.create("actor_1", "reason").to_dict(),
		GameEvent.AttributeChanged.create("actor_1", "hp", 1.0, 2.0, {"id": "source"}).to_dict(),
		GameEvent.AbilityGranted.create("actor_1", {"id": "ability_1"}).to_dict(),
		GameEvent.AbilityRemoved.create("actor_1", "ability_1").to_dict(),
		GameEvent.AbilityStacksChanged.create("actor_1", "ability_1", "config_1", 1, 2).to_dict(),
		GameEvent.AbilityTriggered.create("actor_1", "ability_1", "config_1", "damage", components).to_dict(),
		GameEvent.ExecutionActivated.create("actor_1", "ability_1", "config_1", "execution_1", "timeline_1").to_dict(),
		GameEvent.TagChanged.create("actor_1", "stunned", 0, 1).to_dict(),
		GameEvent.StageCue.create("actor_1", target_ids, "cue_1", {"radius": 2}).to_dict(),
		GameEvent.ProjectileHit.create("projectile_1", "actor_1", "actor_2", Vector3.ONE, 1.0, 2.0, "config_1").to_dict(),
		GameEvent.AbilityActivate.create("ability_1", "actor_1", 100.0, "actor_2", {"q": 0, "r": 0}).to_dict(),
		GameEvent.AbilityActivateFailed.create("ability_1", "config_1", "actor_1", "actor_2", "reason", "cost").to_dict(),
	]
	TestFramework.assert_equal(13, dicts.size())
	for d in dicts:
		_assert_snake_case_dict(d, str(d.get("kind", "?")))


func _test_kind_constants() -> void:
	var kinds: Array[String] = [
		GameEvent.ABILITY_ACTIVATE_EVENT, GameEvent.ABILITY_ACTIVATE_FAILED_EVENT,
		GameEvent.ACTOR_SPAWNED_EVENT, GameEvent.ACTOR_DESTROYED_EVENT,
		GameEvent.ATTRIBUTE_CHANGED_EVENT, GameEvent.ABILITY_GRANTED_EVENT,
		GameEvent.ABILITY_REMOVED_EVENT, GameEvent.ABILITY_TRIGGERED_EVENT,
		GameEvent.ABILITY_STACKS_CHANGED_EVENT, GameEvent.EXECUTION_ACTIVATED_EVENT,
		GameEvent.TAG_CHANGED_EVENT, GameEvent.STAGE_CUE_EVENT, GameEvent.PROJECTILE_HIT_EVENT,
		ProjectileEvents.PROJECTILE_LAUNCHED_EVENT, ProjectileEvents.PROJECTILE_HIT_EVENT,
		ProjectileEvents.PROJECTILE_MISS_EVENT, ProjectileEvents.PROJECTILE_DESPAWN_EVENT,
		ProjectileEvents.PROJECTILE_PIERCE_EVENT,
	]
	var regex := _snake_case_regex()
	for kind in kinds:
		TestFramework.assert_true(regex.search(kind) != null, "kind constant not snake_case: %s" % kind)


func _test_projectile_event_dicts() -> void:
	var dicts: Array[Dictionary] = [
		ProjectileEvents.create_projectile_launched_event("projectile_1", "actor_1", Vector3.ONE, "arrow", 5.0, "actor_2", Vector3.ONE),
		ProjectileEvents.create_projectile_hit_event("projectile_1", "actor_1", "actor_2", Vector3.ONE, 1.0, 2.0, "config_1", {"damage": 3.0}),
		ProjectileEvents.create_projectile_miss_event("projectile_1", "actor_1", "out_of_range", Vector3.ONE, 1.0, "actor_2", "config_1"),
		ProjectileEvents.create_projectile_despawn_event("projectile_1", "actor_1", "expired"),
		ProjectileEvents.create_projectile_pierce_event("projectile_1", "actor_1", "actor_2", Vector3.ONE, 1, 3.0, "config_1"),
	]
	TestFramework.assert_equal(5, dicts.size())
	for d in dicts:
		_assert_snake_case_dict(d, str(d.get("kind", "?")))


func _test_playback_dicts() -> void:
	var record := PlaybackData.BattleRecord.new()
	record.meta = PlaybackData.BattleMeta.new()
	record.world_snapshot = PlaybackData.WorldSnapshot.new()
	record.world_snapshot.actors.append(PlaybackData.ActorInitData.new())
	record.timeline.append(PlaybackData.FrameData.new())
	var record_dict := record.to_dict()
	_assert_snake_case_dict(record_dict, "BattleRecord")
	_assert_snake_case_dict(record.world_snapshot.actors[0].to_dict(), "ActorInitData")
	_assert_snake_case_dict(record.timeline[0].to_dict(), "FrameData")
	TestFramework.assert_true(record_dict.has("meta") and record_dict.has("world_snapshot") and record_dict.has("timeline"))


func _test_attribute_listener_dict() -> void:
	var attribute_set := RawAttributeSet.new()
	attribute_set.define_attribute("hp", 10.0, 0.0, 100.0)
	var captured: Array[Dictionary] = []
	attribute_set.add_change_listener(func(event: Dictionary) -> void: captured.append(event))
	attribute_set.set_base("hp", 20.0)
	TestFramework.assert_equal(1, captured.size())
	_assert_snake_case_dict(captured[0], "RawAttributeSet listener")


## key 递归一层（嵌套 dict 的 key 也查），kind 值同查。
func _assert_snake_case_dict(d: Dictionary, label: String) -> void:
	var regex := _snake_case_regex()
	TestFramework.assert_false(d.is_empty(), "%s: empty dict" % label)
	for key in d.keys():
		var key_text := str(key)
		TestFramework.assert_true(regex.search(key_text) != null, "%s: key not snake_case: %s" % [label, key_text])
		if d[key] is Dictionary:
			for nested_key in (d[key] as Dictionary).keys():
				TestFramework.assert_true(regex.search(str(nested_key)) != null,
					"%s.%s: nested key not snake_case: %s" % [label, key_text, str(nested_key)])
	if d.has("kind"):
		var kind := str(d["kind"])
		TestFramework.assert_true(regex.search(kind) != null, "%s: kind not snake_case: %s" % [label, kind])


static func _snake_case_regex() -> RegEx:
	var regex := RegEx.new()
	regex.compile(SNAKE_CASE_PATTERN)
	return regex
