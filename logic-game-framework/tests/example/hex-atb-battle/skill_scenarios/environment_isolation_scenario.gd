## EnvironmentIsolation - 隔离边界验证: strike 不会误中 stone wall
##
## M1 验证: 加入 stone_wall 不会破坏现有战斗管线。
##   - caster (WARRIOR) Strike 攻击 enemy (auto-target)
##   - 地图同时配一面 stone_wall, 占另一格
##
## 期望:
##   - enemy 受到 Strike 伤害 (有 damage event target=enemy_id(0))
##   - stone_wall 不被 Strike 选中 (无 damage event target=environment_id(0))
##   - stone_wall 仍然存在于 environment_ids (preview battle 创建并 staging)
class_name EnvironmentIsolationScenario
extends SkillScenario


func get_name() -> String:
	return "Strike does not target stone_wall (env isolation)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
		"environment": [
			{"type": "stone_wall", "pos": [0, 1]},
		],
		"target":  {"mode": "auto"},
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleStrike.ABILITY


func get_max_ticks() -> int:
	return 50


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var enemy := ctx.enemy_id(0)
	var wall := ctx.environment_id(0)

	if wall.is_empty():
		ctx.fail("environment_id(0) empty — stone_wall not staged into preview battle")
		return

	# enemy 应该收到至少一次伤害
	var enemy_dmgs := ctx.filter_damage_events({"target_actor_id": enemy})
	if enemy_dmgs.is_empty():
		ctx.fail("enemy received no damage (Strike never fired)")

	# wall 不应被任何 damage 事件选中 (current_target selector 隔离了 character vs env)
	var wall_dmgs := ctx.filter_damage_events({"target_actor_id": wall})
	ctx.assert_eq(wall_dmgs.size(), 0, "stone_wall should not be hit by Strike")
