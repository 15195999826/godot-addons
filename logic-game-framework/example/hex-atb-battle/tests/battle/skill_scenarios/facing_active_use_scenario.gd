## Active-use facing contract: targeted active skills turn caster toward target.
class_name FacingActiveUseScenario
extends SkillScenario


func get_name() -> String:
	return "§0.3 Facing active use: Strike turns caster toward target"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 5, "cols": 8},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "atk": 50, "hp": 1000, "max_hp": 1000},
		"enemies": [
			{"class": "WARRIOR", "pos": [0, 1], "hp": 200, "max_hp": 200},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleStrike.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


func get_max_ticks() -> int:
	return 20


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var facing_events: Array[Dictionary] = []
	for event_dict in ctx.events_of_kind("actor_facing_changed"):
		if str(event_dict.get("actor_id", "")) == ctx.caster_id:
			facing_events.append(event_dict)

	ctx.assert_eq(facing_events.size(), 1,
		"Strike active use emits one caster actor_facing_changed event")
	if facing_events.is_empty():
		return

	var event_dict := facing_events[0]
	ctx.assert_eq(int(event_dict.get("old_direction", -1)), HexFacing.DIR_EAST,
		"caster starts EAST")
	ctx.assert_eq(int(event_dict.get("new_direction", -1)), HexFacing.DIR_SOUTHEAST,
		"caster turns toward enemy at (0,1)")
	ctx.assert_eq(str(event_dict.get("reason", "")), HexFacing.REASON_ACTIVE_USE,
		"facing reason = active_use")
	ctx.assert_eq(ctx.actor_final_facing(ctx.caster_id), HexFacing.DIR_SOUTHEAST,
		"final caster facing stays target-facing")
