## Phase G · Piercing Line - 沿方向命中多目标
##
## V1 契约:
## - 沿 caster→target 方向遍历 LINE_LENGTH=3 格
## - 命中所有沿线敌方 alive CharacterActor
##
## 时序:
##   t=0     caster [0,0] cast PiercingLine target enemy_0 [1,0]
##           方向 = [+1,0] (东)
##           沿线 3 格: [1,0] (enemy_0) / [2,0] (enemy_1) / [3,0] (enemy_2)
##           → 3 个 damage event 各 atk 50 PHYSICAL
class_name PiercingLineScenario
extends SkillScenario


const CASTER_ATK := 50.0


func get_name() -> String:
	return "Piercing Line: hit all enemies along caster→target direction (length 3)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 4},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": CASTER_ATK},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 2000, "atk": 10},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 2000, "atk": 10},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "caster",
			"skill": HexBattlePiercingLine.ABILITY,
			"target": "enemy_0",
			"time_ms": 0,
		},
	]


func get_max_ticks() -> int:
	return 20


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 期望 3 个 enemy 都受 damage
	var damages: Array = []
	for enemy_idx in range(3):
		var enemy_damages := ctx.filter_damage_events({
			"source_actor_id": ctx.caster_id,
			"target_actor_id": ctx.enemy_id(enemy_idx),
		})
		var main: Array = []
		for e in enemy_damages:
			if (e.get("damage", 0.0) as float) >= 40.0:
				main.append(e)
		damages.append(main)
		ctx.assert_eq(main.size(), 1,
			"Expect 1 main damage on enemy_%d (got %d)" % [enemy_idx, main.size()])
		if main.size() == 1:
			ctx.assert_float_eq(main[0].get("damage", 0.0) as float, CASTER_ATK,
				"enemy_%d damage = caster atk" % enemy_idx)
