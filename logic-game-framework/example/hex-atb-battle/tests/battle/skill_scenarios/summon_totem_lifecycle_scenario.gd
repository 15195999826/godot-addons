## Phase C0 · Summon Totem - end-to-end lifecycle (spawn + auto-attack + expire + cleanup)
##
## 时序 (totem_lifetime=5000ms 缩短便于 scenario 验证):
##   t=0     caster cast Summon Totem → HIT @ t=400ms → spawn TOTEM 邻格
##                                       + grant TotemAttack + TotemLifetime(5000ms)
##                                       TotemAttack GRANTED_SELF → periodic timeline 启动
##   t=3400  TotemAttack first tick (400 + 3000) → 最近敌方 enemy_0 受 totem.atk=30 PHYSICAL
##   t=5400  TotemLifetime expire (400 + 5000) → totem actor removed + grid 清
##
## 断言:
## - 1 个 spawned_actor_id (从 spawn action result; 反映为 TOTEM ABILITY_GRANTED 给新 actor)
## - >= 1 damage event source=totem_actor_id target=enemy_0 damage≈30
## - totem actor 在战斗结束前已 remove (replay 含 abilityRemoved for TotemLifetime)
## - replay 含 ABILITY_GRANTED for TotemAttack / TotemLifetime
class_name SummonTotemLifecycleScenario
extends SkillScenario


const TOTEM_LIFETIME_MS := 5000.0
const TOTEM_DEFAULT_ATK := 30.0


func get_name() -> String:
	return "Summon Totem: spawn + auto-attack + lifetime expire cleanup"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 50},
		"enemies": [{"class": "WARRIOR", "pos": [3, 0], "hp": 2000, "atk": 10}],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "caster",
			"skill": HexBattleSummonTotem.create_config(TOTEM_LIFETIME_MS),
			"target": "auto",
			"time_ms": 0,
		},
	]


# 70 ticks = 7000ms: 含 spawn (400ms) + 1 attack (3400ms) + expire (5400ms) + buffer。
# TotemAttack periodic 永不停, harness 会 max_ticks timeout — smoke runner only_timeout ok。
func get_max_ticks() -> int:
	return 70


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. 找 spawn 事件: TOTEM 上的 abilityGranted 含 TotemAttack 或 TotemLifetime config_id
	#    (TOTEM actor 是新 spawn 的, 没有自己的 abilityGranted 通知 actor 本身, 但它接收 grant 自带 passives)
	var totem_attack_grants: Array = []
	var totem_lifetime_grants: Array = []
	var totem_actor_id := ""
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		var cfg_id := str(ability_data.get("configId", ""))
		if cfg_id == HexBattleTotemAttack.CONFIG_ID:
			totem_attack_grants.append(e)
			totem_actor_id = str(e.get("actorId", ""))
		elif cfg_id == HexBattleTotemLifetime.CONFIG_ID:
			totem_lifetime_grants.append(e)
	ctx.assert_eq(totem_attack_grants.size(), 1,
		"Expect 1 TotemAttack ability granted on spawned TOTEM (got %d)" % totem_attack_grants.size())
	ctx.assert_eq(totem_lifetime_grants.size(), 1,
		"Expect 1 TotemLifetime ability granted on spawned TOTEM (got %d)" % totem_lifetime_grants.size())
	ctx.assert_true(not totem_actor_id.is_empty(),
		"Spawned TOTEM actor id captured from TotemAttack grant event")

	if totem_actor_id.is_empty():
		return

	# 2. >= 1 damage event source=totem target=enemy_0
	var totem_damages := ctx.filter_damage_events({
		"source_actor_id": totem_actor_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	ctx.assert_true(totem_damages.size() >= 1,
		"Expect TotemAttack to fire >=1 damage on enemy_0 (got %d)" % totem_damages.size())

	var totem_attack_cues: Array = []
	for e in ctx.events_of_kind(GameEvent.STAGE_CUE_EVENT):
		if str(e.get("sourceActorId", "")) == totem_actor_id \
				and str(e.get("cueId", "")) == HexBattleTotemAttack.STAGE_CUE_ID:
			totem_attack_cues.append(e)
	ctx.assert_true(totem_attack_cues.size() >= 1,
		"Expect TotemAttack stageCue for frontend attack VFX (got %d)" % totem_attack_cues.size())

	# 3. TotemLifetime expire → totem actor removed (TotemLifetime ability 在 replay 中 ABILITY_REMOVED)
	var lifetime_inst := str((totem_lifetime_grants[0].get("ability", {}) as Dictionary).get("id", ""))
	var lifetime_removes: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("abilityInstanceId", "")) == lifetime_inst:
			lifetime_removes.append(e)
	ctx.assert_true(lifetime_removes.size() >= 1,
		"Expect TotemLifetime to expire by end of run (got %d remove events)" % lifetime_removes.size())
