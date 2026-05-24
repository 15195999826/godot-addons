## Phase C · Fire Tile - lifecycle (spawn + pulse damage + expire cleanup)
##
## 时序 (lifetime 3000ms 缩短便于 scenario):
##   t=0     caster cast SpawnFireTile target enemy_0 (站在 [1,0])
##           → HIT @ t=400ms → spawn FireTile at [1,0] (overlay, 不占 grid.occupant)
##           → grant FireTilePulse + FireTileLifetime(3000ms) 给 fire tile
##   t≈1400  FireTilePulse first tick (400 + 1000) → enemy_0 受 20 PURE
##   t≈2400  FireTilePulse second tick → enemy_0 又受 20 PURE
##   t≈3400  FireTileLifetime expire → fire tile actor removed
##
## 断言:
## - 1 个 FireTilePulse grant + 1 个 FireTileLifetime grant
## - >= 1 damage event source=fire_tile target=enemy_0 damage=20 PURE
## - FireTileLifetime expire → ABILITY_REMOVED for fire tile passive
## - FireTile actor 没占用 grid.occupant ([1,0] 上 occupant 仍是 enemy_0)
class_name FireTileLifecycleScenario
extends SkillScenario


const FIRE_TILE_LIFETIME_MS := 3000.0


func get_name() -> String:
	return "Fire Tile: spawn overlay + pulse damage + lifetime cleanup"


func get_scene_config() -> Dictionary:
	return {
		"map": {"radius": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "hp": 2000, "atk": 50},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 2000, "atk": 10}],
	}


func get_actions() -> Array[Dictionary]:
	return [
		{
			"caster": "caster",
			"skill": HexBattleSpawnFireTile.create_config(FIRE_TILE_LIFETIME_MS),
			"target": "enemy_0",
			"time_ms": 0,
		},
	]


func get_max_ticks() -> int:
	return 50


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. FireTilePulse + FireTileLifetime 各 1 grant
	var pulse_grants: Array = []
	var lifetime_grants: Array = []
	var fire_tile_id := ""
	for e in ctx.events_of_kind(GameEvent.ABILITY_GRANTED_EVENT):
		var ability_data: Dictionary = e.get("ability", {}) as Dictionary
		var cfg := str(ability_data.get("configId", ""))
		if cfg == HexBattleFireTilePulse.CONFIG_ID:
			pulse_grants.append(e)
			fire_tile_id = str(e.get("actorId", ""))
		elif cfg == HexBattleFireTileLifetime.CONFIG_ID:
			lifetime_grants.append(e)
	ctx.assert_eq(pulse_grants.size(), 1, "Expect 1 FireTilePulse grant")
	ctx.assert_eq(lifetime_grants.size(), 1, "Expect 1 FireTileLifetime grant")
	ctx.assert_true(not fire_tile_id.is_empty(), "Fire tile actor id captured")
	if fire_tile_id.is_empty():
		return

	# 2. >= 1 pulse damage event source=fire_tile target=enemy_0 damage=20 PURE
	var pulses := ctx.filter_damage_events({
		"source_actor_id": fire_tile_id,
		"target_actor_id": ctx.enemy_id(0),
	})
	ctx.assert_true(pulses.size() >= 1,
		"Expect FireTile pulse damage on enemy_0 (got %d)" % pulses.size())
	if pulses.size() >= 1:
		var dmg := pulses[0].get("damage", 0.0) as float
		ctx.assert_float_eq(dmg, HexBattleFireTilePulse.DEFAULT_PULSE_DAMAGE,
			"Pulse damage = %.1f PURE" % HexBattleFireTilePulse.DEFAULT_PULSE_DAMAGE)

	# 3. FireTileLifetime expire → ABILITY_REMOVED
	var lifetime_inst := str((lifetime_grants[0].get("ability", {}) as Dictionary).get("id", ""))
	var lifetime_removes: Array = []
	for e in ctx.events_of_kind(GameEvent.ABILITY_REMOVED_EVENT):
		if str(e.get("abilityInstanceId", "")) == lifetime_inst:
			lifetime_removes.append(e)
	ctx.assert_true(lifetime_removes.size() >= 1,
		"FireTileLifetime expired (got %d remove events)" % lifetime_removes.size())

	# 4. FireTile 是 overlay，remove_actor(fire_tile) 不允许清掉同格 enemy_0 occupant。
	ctx.assert_eq(
		ctx.grid_occupant_id(1, 0),
		ctx.enemy_id(0),
		"FireTile overlay cleanup must leave enemy_0 as grid occupant at [1,0]",
	)
