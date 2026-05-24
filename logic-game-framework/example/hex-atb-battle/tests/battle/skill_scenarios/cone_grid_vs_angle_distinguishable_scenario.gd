## Phase D · 同站位下, skill_grid_cone 与 skill_angle_cone 命中集合可区分
##
## V1 契约:
## - 同站位: 1 grid cast + 1 angle cast (按时间错开避免叠加)
## - grid 命中集合 ⊇ angle 命中集合 (grid 比 angle 宽)
## - 至少 1 个目标 grid 内 / angle 外, 证明 sector 比 45° 锥更宽
class_name ConeGridVsAngleDistinguishableScenario
extends SkillScenario


const CASTER_ATK := 40.0


func get_name() -> String:
	return "Cone: grid hit set strictly contains angle hit set (grid wider than 45° cone)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 5},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": CASTER_ATK},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 0},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 2000, "atk": 0},
			{"class": "WARRIOR", "pos": [1, -1], "hp": 2000, "atk": 0},
		],
	}


func get_actions() -> Array[Dictionary]:
	# 1 grid cast at t=0, 1 angle cast at t=10000 (after grid cooldown 8000ms)
	return [
		{
			"caster": "caster",
			"skill": HexBattleGridCone.ABILITY,
			"target_coord": {"q": 3, "r": 0},
			"time_ms": 0,
		},
		{
			"caster": "caster",
			"skill": HexBattleAngleCone.ABILITY,
			"target_coord": {"q": 3, "r": 0},
			"time_ms": 10000,
		},
	]


func get_max_ticks() -> int:
	return 120  # ~12 秒, 足够两次 cast 完成


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# Collect distinct hit targets per cone type, by ability source_ability_config_id via attack_landed
	# 但 attack_landed 不由 cone 触发 (只 Strike 走). 这里靠 timeline 顺序: 前半段 damage = grid, 后半段 = angle.
	# 简单做法: 用 replay_frame 分割.
	var all_hits := ctx.filter_damage_events({
		"source_actor_id": ctx.caster_id,
		"damage_type": "physical",
	})
	# grid HIT 在 ~frame 3 (cast t=0 + HIT 300ms = 3 frame),
	# angle HIT 在 ~frame 103 (cast t=10000 + HIT 300ms = 103 frame).
	# 取 frame < 50 = grid 段, frame > 50 = angle 段.
	var grid_targets: Array[String] = []
	var angle_targets: Array[String] = []
	for h in all_hits:
		var tid := str(h.get("target_actor_id", ""))
		var frame := int(h.get("replay_frame", 0))
		if frame < 50:
			if tid not in grid_targets:
				grid_targets.append(tid)
		else:
			if tid not in angle_targets:
				angle_targets.append(tid)

	ctx.assert_true(grid_targets.size() > 0,
		"grid cone hit at least 1 enemy (got %d)" % grid_targets.size())
	ctx.assert_true(angle_targets.size() > 0,
		"angle cone hit at least 1 enemy (got %d)" % angle_targets.size())

	# 核心断言: grid 集合 ⊇ angle 集合 + 严格大 (至少 1 个 grid 命中 angle 不命中)
	for tid in angle_targets:
		ctx.assert_true(tid in grid_targets,
			"every angle-hit target should also be hit by grid (target %s missing in grid)" % tid)
	ctx.assert_true(grid_targets.size() > angle_targets.size(),
		"grid hit set strictly contains angle hit set (grid=%d, angle=%d)" % [grid_targets.size(), angle_targets.size()])
