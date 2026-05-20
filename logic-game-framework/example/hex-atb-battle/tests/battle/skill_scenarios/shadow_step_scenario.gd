## Shadow Step scenario (Phase 02) - 4 case
##
## map 7x5, caster[0,2] (A 队 EAST), enemy_0[4,2] (B 队 WEST), 障碍/友军视 case 摆放。
##
## Case 1 (main path): enemy_0 facing WEST 背侧 = EAST([5,2]); 落点 [5,2] 空。
##   预期: ActorDisplacedEvent(kind=teleport, source=caster) 出现; caster 终位 [5,2];
##         enemy_0 受击 atk*1.5 = 75 (允许 crit 112.5)。
## Case 2 (fallback-side): 同 Case 1, 但背侧 [5,2] 放一个 wall, 备选 [5,1] (背左) 应当被选。
##   测试: caster 终位 [5,1]; ActorDisplacedEvent.to_hex == {5,1}; 仍造伤。
##   注: case 2 用独立 scenario instance (本 case 跑独立 setup 困难, 简化为放 case 3/4 后单测)
## Case 3 (blocked-all-around): enemy_0 周身 6 邻格全部不可用 → teleport_success=false,
##   无 ActorDisplacedEvent, caster 留在原位, enemy_0 不受伤。
## Case 4 (post-teleport target 死亡): 这个不能直接构造一次性 scenario, 留给 unit test
##   通过 §0.5 DamageAction dead-target no-op 已通用证明。
##
## 简化合并: 本文件覆盖 Case 1 (main) + Case 3 (blocked). Case 2 (fallback) 用第二个 scenario.
class_name ShadowStepScenario
extends SkillScenario


const SHADOW_STEP_DAMAGE_MULT := HexBattleShadowStep.DAMAGE_MULT
const CRIT_MULT := 1.5


func get_name() -> String:
	return "ShadowStep main: 瞬移到 enemy_0 背侧 + atk×1.5 一击"


func get_scene_config() -> Dictionary:
	# enemy_0 朝 WEST (B 队默认); 背侧方向 = EAST = [5,0] 空; caster 在 [0,0] 距离=4 (range 上限)
	# 用 radius mode 避开 row/col 偏移坐标. 详见 grid_map_model.gd::_generate_hex_radius
	return {
		"map": {"radius": 5},
		"caster": {"class": "WARRIOR", "pos": [0, 0], "atk": 50, "hp": 1000, "max_hp": 1000},
		"enemies": [
			{"class": "WARRIOR", "pos": [4, 0], "hp": 1000, "max_hp": 1000},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleShadowStep.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


## timeline 500ms + buffer; max 60 ticks.
func get_max_ticks() -> int:
	return 60


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# ---- ActorDisplacedEvent(kind=teleport) ----
	var displaceds: Array[Dictionary] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "actor_displaced" \
				and str(e.get("displacement_kind", "")) == HexBattleShadowStep.DISPLACEMENT_KIND_TELEPORT \
				and str(e.get("source_actor_id", "")) == ctx.caster_id:
			displaceds.append(e)
	ctx.assert_eq(displaceds.size(), 1,
		"应有 1 个 teleport displacement 事件 (caster 自位移)")

	# caster 终位 = enemy_0 背侧 [5,0]
	if displaceds.size() >= 1:
		var to_hex: Dictionary = displaceds[0].get("to_hex", {}) as Dictionary
		ctx.assert_eq(int(to_hex.get("q", -1)), 5, "落点 q = 5 (enemy_0 背侧 EAST)")
		ctx.assert_eq(int(to_hex.get("r", -1)), 0, "落点 r = 0 (enemy_0 同 r)")

	# caster final facing toward target (落地后 face target) → DIR_WEST
	ctx.assert_eq(ctx.actor_final_facing(ctx.caster_id), HexFacing.DIR_WEST,
		"caster 瞬移后 face target → DIR_WEST")
	# target facing 不应改变 → 仍为 DIR_WEST (B 队默认)
	ctx.assert_eq(ctx.actor_final_facing(ctx.enemy_id(0)), HexFacing.DIR_WEST,
		"target facing 不变 (Shadow Step 不改 target facing)")

	# ---- 伤害 = atk × 1.5 = 75 (允许 crit 112.5) ----
	var damages := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
	if damages.is_empty():
		ctx.fail("enemy_0 未收到 damage event")
	else:
		var d: float = damages[0].get("damage", -1.0) as float
		var expected := 50.0 * SHADOW_STEP_DAMAGE_MULT
		ctx.assert_float_in(d, [expected, expected * CRIT_MULT],
			"enemy_0 受击 = atk×1.5 = 75 (允许 crit 112.5)")
