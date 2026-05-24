## Cleanse self-target: self + ally contract must allow caster cleansing themselves.
class_name CleanseSelfScenario
extends SkillScenario


func get_name() -> String:
	return "Cleanse self: caster can cleanse own negative buff"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 30},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10}],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "enemy_0",
			"skill": HexBattlePoison.ABILITY,
			"target": "caster",
			"time_ms": 0,
		},
		{
			"caster": "caster",
			"skill": HexBattleCleanse.ABILITY,
			"target": "caster",
			"time_ms": 600,
		},
	]


func get_max_ticks() -> int:
	return 40


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var poison_grant: Dictionary = {}
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		if str(e.get("actorId", "")) != ctx.caster_id:
			continue
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		if str(ability_data.get("configId", "")) == HexBattlePoisonBuff.CONFIG_ID:
			poison_grant = e
			break
	ctx.assert_true(not poison_grant.is_empty(), "Poison buff granted on caster")
	if poison_grant.is_empty():
		return

	var poison_inst := str((poison_grant.get("ability", {}) as Dictionary).get("id", ""))
	var remove_frame := -1
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("abilityInstanceId", "")) == poison_inst:
			remove_frame = int(e.get("replay_frame", -1))
			break

	ctx.assert_true(remove_frame > 0, "Self Cleanse removes Poison buff")
	ctx.assert_true(remove_frame < 25,
		"Self Cleanse removes Poison before natural DOT expiry (frame %d)" % remove_frame)
