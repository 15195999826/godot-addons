## PreciseShot 远程投射物场景：cast 发射 projectile → 命中后 45 physical
##
## 验证 pattern:
##   - LaunchProjectileAction 发射 projectile
##   - ProjectileSystem tick 驱动 → 命中 → 发 projectileHit 事件
##   - ActivateInstanceConfig 响应 projectileHit → 第二条 timeline → DamageAction
class_name PreciseShotScenario
extends SkillScenario


const DAMAGE := 45.0


func get_name() -> String:
	return "PreciseShot projectile hits for 45 physical"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 5, "cols": 5},
		"caster":  {"class": "ARCHER", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [3, 0], "hp": 1000}],
	}


func get_active_skill() -> AbilityConfig:
	return HexBattlePreciseShot.ABILITY


## 投射物飞行需要时间(距离 3 格,speed 250),额外给够 tick 预算
func get_max_ticks() -> int:
	return 80


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var target := ctx.enemy_id(0)
	var hits := ctx.filter_damage_events({
		"target_actor_id": target,
		"damage_type": "physical",
	})
	ctx.assert_eq(hits.size(), 1, "exactly 1 PreciseShot hit")
	if hits.size() >= 1:
		var dmg: float = hits[0].get("damage", 0.0)
		ctx.assert_float_in(dmg, [DAMAGE, DAMAGE * 1.5],
			"damage = 45 or 67.5 (crit)")
