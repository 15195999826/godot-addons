## Poison DOT 场景：caster 对相邻 enemy 施毒，验证 3→2→1 层衰减伤害 + 耗尽自毁
class_name PoisonScenario
extends SkillScenario


func get_name() -> String:
	return "Poison DOT 3→2→1 (total=6)"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
		"target":  {"mode": "auto"},
	}


func get_active_skill() -> AbilityConfig:
	return HexBattlePoison.ABILITY


## 足够跑完 cast(500ms) + 3 次 DOT tick(2s interval) + 尾巴 = 7500ms = 75 ticks
func get_max_ticks() -> int:
	return 100


func assert_replay(ctx: ScenarioAssertContext) -> void:
	var target := ctx.enemy_id(0)

	# 只看对 target 的 PURE 伤害 = DOT tick 事件（过滤掉其他 damage_type）
	var dmgs := ctx.filter_damage_events({
		"target_actor_id": target,
		"damage_type": "pure",
	})
	var dmg_values: Array = []
	for e in dmgs:
		dmg_values.append(e.get("damage", -1.0))

	ctx.assert_array_float_eq(dmg_values, [3.0, 2.0, 1.0], "DOT damage sequence")
	ctx.assert_float_eq(ctx.total_damage_to(target), 6.0, "total DOT damage")

	# caster 不应受自残伤害
	ctx.assert_float_eq(ctx.total_damage_to(ctx.caster_id), 0.0, "caster took no self-damage")

	# buff 耗尽后应被 revoke
	ctx.assert_actor_ability_absent(target, HexBattlePoisonBuff.CONFIG_ID,
		"PoisonBuff revoked after stacks exhausted")

	# 集成路径:PoisonTickAction 必须把 AbilityStacksChanged push 进 replay collector,
	# 否则 frontend BuffVisualizer 永远收不到 stacks 变化(白盒 smoke 不能覆盖此路径)。
	# 期望 3 次 tick 对应 3 个事件:3→2 / 2→1 / 1→0。
	var stacks_events := ctx.events_of_kind(GameEvent.ABILITY_STACKS_CHANGED_EVENT)
	ctx.assert_eq(stacks_events.size(), 3, "AbilityStacksChanged event count")
	if stacks_events.size() == 3:
		ctx.assert_eq(stacks_events[0].get("oldStacks"), 3, "tick 1 oldStacks")
		ctx.assert_eq(stacks_events[0].get("newStacks"), 2, "tick 1 newStacks")
		ctx.assert_eq(stacks_events[2].get("newStacks"), 0, "tick 3 newStacks reaches 0")
		ctx.assert_eq(stacks_events[0].get("abilityConfigId"), HexBattlePoisonBuff.CONFIG_ID,
			"event abilityConfigId == buff_poison")

	# Buff UI 依赖先 ADD 再 UPDATE。若首次 tick 跟 grant 同帧且进入 replay 顺序早于
	# AbilityGranted, frontend 会忽略 3→2,表现成 3→1→消失。
	var poison_grant_index := -1
	var first_stacks_index := -1
	for i in range(ctx.events.size()):
		var event := ctx.events[i]
		if first_stacks_index < 0 \
			and event.get("kind") == GameEvent.ABILITY_STACKS_CHANGED_EVENT \
			and event.get("abilityConfigId") == HexBattlePoisonBuff.CONFIG_ID:
			first_stacks_index = i
		if poison_grant_index < 0 and event.get("kind") == GameEvent.ABILITY_GRANTED_EVENT:
			var ability: Dictionary = event.get("ability", {})
			if ability.get("configId") == HexBattlePoisonBuff.CONFIG_ID:
				poison_grant_index = i
	ctx.assert_true(poison_grant_index >= 0, "PoisonBuff AbilityGranted recorded")
	ctx.assert_true(first_stacks_index > poison_grant_index,
		"PoisonBuff grant appears before first AbilityStacksChanged")
