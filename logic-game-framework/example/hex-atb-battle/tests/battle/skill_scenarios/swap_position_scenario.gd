## Phase E · Swap - atomic position swap + ActorDisplacedEvent 对
##
## V1 契约:
## - caster 与 target 原子互换 hex_position + grid.occupant
## - 双 ActorDisplacedEvent (caster 先 target 后) 同 swap_id
## - target = enemy_0 (敌方 CharacterActor, 验证 swap 跨阵营也 work)
##
## 时序:
##   t=0     caster [0,0] cast Swap target enemy_0 [2,0] → HIT @ t=300
##           → caster 移到 [2,0], enemy_0 移到 [0,0]
##           → 双 ActorDisplacedEvent (caster + enemy_0) 同 swap_id, displacement_kind="swap"
class_name SwapPositionScenario
extends SkillScenario


func get_name() -> String:
	return "Swap: atomic position exchange + paired ActorDisplacedEvent"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 30},
		"enemies": [{"class": "WARRIOR", "pos": [2, 0], "hp": 2000, "atk": 10}],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "caster",
			"skill": HexBattleSwap.ABILITY,
			"target": "enemy_0",
			"time_ms": 0,
		},
	]


func get_max_ticks() -> int:
	return 20


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 收集 ActorDisplacedEvent (kind="actorDisplaced" 实际不是, 看 BattleEvents 实现)
	# ActorDisplacedEvent 的 kind 在 BattleEvents.ActorDisplacedEvent. let me check.
	# 实际 kind 字段 from base class — 不一定 "actorDisplaced"
	var swap_events: Array = []
	for e in ctx.events:
		# ActorDisplacedEvent dict 含 displacement_kind="swap"
		if str(e.get("displacement_kind", "")) == HexBattleSwap.DISPLACEMENT_KIND:
			swap_events.append(e)

	# Expect 2 events (caster + target) 同 swap_id
	ctx.assert_eq(swap_events.size(), 2,
		"Expect 2 ActorDisplacedEvent for swap (caster + target), got %d" % swap_events.size())
	if swap_events.size() != 2:
		return

	var swap_id_a := str(swap_events[0].get("swap_id", ""))
	var swap_id_b := str(swap_events[1].get("swap_id", ""))
	ctx.assert_true(not swap_id_a.is_empty() and swap_id_a == swap_id_b,
		"Both events carry same non-empty swap_id (a=%s b=%s)" % [swap_id_a, swap_id_b])

	# 第一个 actor_id 应是 caster (event order: caster 先)
	ctx.assert_eq(str(swap_events[0].get("actor_id", "")), ctx.caster_id,
		"First displacement event actor_id = caster_id")
	ctx.assert_eq(str(swap_events[1].get("actor_id", "")), ctx.enemy_id(0),
		"Second displacement event actor_id = enemy_0")

	# from/to 互换: caster.from=[0,0] to=[2,0]; enemy_0.from=[2,0] to=[0,0]
	var caster_from: Dictionary = swap_events[0].get("from_hex", {}) as Dictionary
	var caster_to: Dictionary = swap_events[0].get("to_hex", {}) as Dictionary
	ctx.assert_eq(int(caster_from.get("q", -99)), 0, "caster from.q=0")
	ctx.assert_eq(int(caster_from.get("r", -99)), 0, "caster from.r=0")
	ctx.assert_eq(int(caster_to.get("q", -99)), 2, "caster to.q=2")
	ctx.assert_eq(int(caster_to.get("r", -99)), 0, "caster to.r=0")

	var enemy_from: Dictionary = swap_events[1].get("from_hex", {}) as Dictionary
	var enemy_to: Dictionary = swap_events[1].get("to_hex", {}) as Dictionary
	ctx.assert_eq(int(enemy_from.get("q", -99)), 2, "enemy_0 from.q=2")
	ctx.assert_eq(int(enemy_to.get("q", -99)), 0, "enemy_0 to.q=0")
