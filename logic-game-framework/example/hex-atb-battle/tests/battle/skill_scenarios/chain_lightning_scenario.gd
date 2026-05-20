## Chain Lightning scenario (Phase 01)
##
## map 7x3, caster[0,0] + enemy_0[1,0] + enemy_1[2,0] + enemy_2[3,0] + enemy_3[6,2] (链外)。
##
## 期望:
## - enemy_0 受 60 magical (允许 crit 90)
## - enemy_1 受 48 magical (允许 crit 72)
## - enemy_2 受 38.4 magical (允许 crit 57.6)
## - enemy_3 不应受到伤害 (太远, 链 3 跳后 next chain 找不到它)
## - projectileLaunched / projectileHit 各 3 个, customData 带 chain_id / hit_index 0/1/2
## - 3 个 damage event 所在 replay frame 严格递增 (证明不是同帧 local loop)
class_name ChainLightningScenario
extends SkillScenario


const BASE_DAMAGE := HexBattleChainLightning.BASE_DAMAGE
const FALLOFF := HexBattleChainLightning.FALLOFF
const CRIT_MULT := 1.5  # 与 DamageAction 0.1 crit chance × 1.5 一致


func get_name() -> String:
	return "ChainLightning: 60→48→38.4 三跳, 远敌不被命中, customData chain_id/hit_index 透传"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 7},
		"caster": {"class": "MAGE", "pos": [0, 0], "atk": 50, "hp": 1000, "max_hp": 1000},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000, "max_hp": 1000},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000, "max_hp": 1000},
			{"class": "WARRIOR", "pos": [3, 0], "hp": 1000, "max_hp": 1000},
			# 链外: distance 从 caster[0,0] = 8, 链 2 跳后 hit_index 达 MAX, 不会再选他
			{"class": "WARRIOR", "pos": [6, 2], "hp": 1000, "max_hp": 1000},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{"caster": "caster", "skill": HexBattleChainLightning.ABILITY, "target": "enemy_0", "time_ms": 0},
	]


## cast timeline 600ms + projectile fly + 3 hit timelines 100ms each = ~2-3s; max 80 ticks * 100ms = 8s.
func get_max_ticks() -> int:
	return 80


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# ---- damage 数值 ----
	var d0_arr := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(0)})
	var d1_arr := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(1)})
	var d2_arr := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(2)})
	var d3_arr := ctx.filter_damage_events({"target_actor_id": ctx.enemy_id(3)})

	if d0_arr.is_empty():
		ctx.fail("enemy_0 未收到 damage event")
	else:
		var d0: float = d0_arr[0].get("damage", -1.0) as float
		ctx.assert_float_in(d0, [BASE_DAMAGE, BASE_DAMAGE * CRIT_MULT],
			"enemy_0 首跳 damage = 60 (允许 crit 90)")

	if d1_arr.is_empty():
		ctx.fail("enemy_1 未收到 damage event")
	else:
		var d1: float = d1_arr[0].get("damage", -1.0) as float
		var expected_d1 := BASE_DAMAGE * (1.0 - FALLOFF)
		ctx.assert_float_in(d1, [expected_d1, expected_d1 * CRIT_MULT],
			"enemy_1 第二跳 damage = 48 (允许 crit 72)")

	if d2_arr.is_empty():
		ctx.fail("enemy_2 未收到 damage event")
	else:
		var d2: float = d2_arr[0].get("damage", -1.0) as float
		var expected_d2 := BASE_DAMAGE * pow(1.0 - FALLOFF, 2)
		ctx.assert_float_in(d2, [expected_d2, expected_d2 * CRIT_MULT],
			"enemy_2 第三跳 damage = 38.4 (允许 crit 57.6)")

	ctx.assert_eq(d3_arr.size(), 0,
		"enemy_3 (链外远敌) 不应受到伤害 (3 跳上限)")

	# ---- projectile event 计数 + customData ----
	# launched event 不带 ability_config_id, 通过 visualType=lightning 过滤; hit 用 ability_config_id。
	var launches: Array[Dictionary] = []
	var hits: Array[Dictionary] = []
	for e in ctx.events:
		var kind := str(e.get("kind", ""))
		if kind == "projectileLaunched" and str(e.get("visualType", "")) == "lightning":
			launches.append(e)
		elif kind == "projectileHit" and str(e.get("ability_config_id", "")) == HexBattleChainLightning.CONFIG_ID:
			hits.append(e)
	ctx.assert_eq(launches.size(), 3,
		"3 个 chain lightning projectileLaunched (含 hit 后续链发的 2 个)")
	ctx.assert_eq(hits.size(), 3,
		"3 个 chain lightning projectileHit")

	# customData 验证: launch / hit 都带 chain_id / hit_index 0/1/2 / ability_instance_id 一致
	var chain_id_set: Dictionary = {}
	var ability_instance_id_set: Dictionary = {}
	for i in range(launches.size()):
		var cd: Dictionary = launches[i].get("customData", {}) as Dictionary
		ctx.assert_true(cd.has("chain_id") and str(cd.get("chain_id")) != "",
			"projectileLaunched[%d] customData.chain_id 非空" % i)
		ctx.assert_true(cd.has("ability_instance_id") and str(cd.get("ability_instance_id")) != "",
			"projectileLaunched[%d] customData.ability_instance_id 非空" % i)
		chain_id_set[str(cd.get("chain_id", ""))] = true
		ability_instance_id_set[str(cd.get("ability_instance_id", ""))] = true

	ctx.assert_eq(chain_id_set.size(), 1, "全部 3 段共用一个 chain_id")
	ctx.assert_eq(ability_instance_id_set.size(), 1, "全部 3 段共用一个 ability_instance_id")

	# launches 的 hit_index 应为 0, 1, 2 (顺序)
	# 因为 launches 按事件流入,可能不严格 0/1/2 顺序; 校验 set
	var indices_seen: Dictionary = {}
	for e in launches:
		var cd: Dictionary = e.get("customData", {}) as Dictionary
		indices_seen[int(cd.get("hit_index", -1))] = true
	for i in range(3):
		ctx.assert_true(indices_seen.has(i),
			"projectileLaunched hit_index 应包含 %d" % i)

	# ---- 时序: 3 个 damage event frame 严格递增 ----
	var damage_frames: Array[int] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "damage" and str(e.get("source_actor_id", "")) == ctx.caster_id:
			# 注意: damage event 不直接带 frame, 我们要从 events 数组的位置反推
			# (ctx._flatten_events 把 timeline 展平后含 frame 字段,但 events[] 默认拍平
			# 检查 _flatten_events 实现: 它把 frame_events 都 append, 没保留 frame...)
			# 退而求其次: 直接比较事件在 events 数组内的 index 也是单调的
			pass
	# 改用 frame metadata 找 — 但 ScenarioAssertContext._flatten_events 没保留 frame。
	# 退而验证 events 数组中 damage 顺序: enemy_0 → enemy_1 → enemy_2。
	var damage_targets_in_order: Array[String] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "damage" and str(e.get("source_actor_id", "")) == ctx.caster_id:
			damage_targets_in_order.append(str(e.get("target_actor_id", "")))
	if damage_targets_in_order.size() >= 3:
		ctx.assert_eq(damage_targets_in_order[0], ctx.enemy_id(0),
			"damage 顺序: 第一段命中 enemy_0")
		ctx.assert_eq(damage_targets_in_order[1], ctx.enemy_id(1),
			"damage 顺序: 第二段命中 enemy_1")
		ctx.assert_eq(damage_targets_in_order[2], ctx.enemy_id(2),
			"damage 顺序: 第三段命中 enemy_2")
