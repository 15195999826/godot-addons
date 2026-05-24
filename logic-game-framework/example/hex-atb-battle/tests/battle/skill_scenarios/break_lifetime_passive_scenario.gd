## Break semantics: actor lifetime passives are not disabled by passive_break.
class_name BreakLifetimePassiveScenario
extends SkillScenario


const TOTEM_LIFETIME_MS := 1000.0
const BREAK_DURATION_MS := 3000.0


func get_name() -> String:
	return "Break lifetime semantics: TotemLifetime keeps expiring while broken"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 30},
		"enemies": [
			{
				"class": "TOTEM",
				"pos": [1, 0],
				"hp": 60,
				"atk": 30,
				"passives": [
					HexBattleTotemAttack.ABILITY,
					HexBattleTotemLifetime.create_config(TOTEM_LIFETIME_MS),
				],
			},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "caster",
			"skill": HexBattleBreak.create_config(BREAK_DURATION_MS),
			"target": "enemy_0",
			"time_ms": 0,
		},
	]


func get_max_ticks() -> int:
	return 25


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var totem_id := ctx.enemy_id(0)
	ctx.assert_actor_ability_absent(
		totem_id,
		HexBattleTotemLifetime.CONFIG_ID,
		"TotemLifetime should expire while Break is still active",
	)
	var destroyed := false
	for e in ctx.events_of_kind(GameEvent.ACTOR_DESTROYED_EVENT):
		if str(e.get("actorId", "")) == totem_id:
			destroyed = true
			break
	ctx.assert_true(destroyed, "Totem actor removed by lifetime despite active Break")
	ctx.assert_eq(ctx.grid_occupant_id(1, 0), "",
		"Totem grid occupant cleared after lifetime removal")
