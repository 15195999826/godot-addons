## Shadow Step fallback-side scenario (Phase 02)
##
## enemy_0[4,2] WEST 背侧 EAST [5,2] 放 stone_wall; caster 必须落到 [5,1] (背左) 或 [5,3] (背右)。
##
## flat hex DIRECTIONS 顺序: [E=(1,0), NE=(1,-1), NW=(0,-1), W=(-1,0), SW=(-1,1), SE=(0,1)]
## enemy_0 朝 WEST(3), opposite=EAST(0), priority=
##   [E(0)=正背, NE(1)=背左, NW(2)=背右更远 → 但 [4,2]+NW=[4,1] / [4,2]+NE=[5,1]]
## 实际上 phase 文档说优先 "背 → 背左 → 背右 → 侧后左 → 侧后右 → 正面"; backleft = behind_dir-1 = -1 mod 6 = 5 = SE.
## 我的实现: priority [dir, dir-1, dir+1, dir-2, dir+2, dir+3].
## behind_dir=0 (E) → [0, 5, 1, 4, 2, 3] = [E, SE, NE, SW, NW, W].
## E([5,2]) 阻挡 → SE([4,3]) 应当为落点 (距 enemy_0 1 格).
class_name ShadowStepFallbackScenario
extends SkillScenario


func get_name() -> String:
	return "ShadowStep fallback-side: 背侧 [5,2] 阻挡 → 落 SE([4,3])"


func get_scene_config() -> Dictionary:
	# radius=5 grid; enemy_0[4,0] 朝 WEST → 背侧 E=[5,0] 阻挡 → fallback SE=[4,1].
	return {
		"map": {"radius": 5},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "atk": 50, "hp": 1000, "max_hp": 1000},
		"enemies": [
			{"class": "WARRIOR", "pos": [4, 0], "hp": 1000, "max_hp": 1000},
		],
		# stone wall 阻挡 enemy_0 背侧 [5,0]
		"environment": [
			{"type": "stone_wall", "pos": [5, 0]},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleShadowStep.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


func get_max_ticks() -> int:
	return 60


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var displaceds: Array[Dictionary] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "actor_displaced" \
				and str(e.get("displacement_kind", "")) == HexBattleShadowStep.DISPLACEMENT_KIND_TELEPORT \
				and str(e.get("source_actor_id", "")) == ctx.caster_id:
			displaceds.append(e)
	ctx.assert_eq(displaceds.size(), 1,
		"应有 1 个 teleport displacement (背侧被阻挡时 fallback 到 SE)")

	if displaceds.size() >= 1:
		var to_hex: Dictionary = displaceds[0].get("to_hex", {}) as Dictionary
		# behind_dir=E(0), priority [E, SE, NE, SW, NW, W]; E([5,0]) 被 wall 阻挡 → SE
		# SE 偏移 DIRECTIONS[5]=(0,1); enemy_0[4,0] + (0,1) = [4,1]
		ctx.assert_eq(int(to_hex.get("q", -1)), 4,
			"落点 q = 4 (SE fallback)")
		ctx.assert_eq(int(to_hex.get("r", -1)), 1,
			"落点 r = 1 (SE fallback)")

	# 仍造伤
	var damages := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
	ctx.assert_eq(damages.size(), 1,
		"fallback 仍触发 atk×1.5 damage")
