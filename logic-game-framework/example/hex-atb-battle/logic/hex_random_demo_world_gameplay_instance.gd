## HexRandomDemoWorldGameplayInstance - 随机组装技能的完整 demo 战斗。
##
## 用于 demo_random_frontend: 复用 HexDemoWorldGameplayInstance 的地图、录像、
## frontend wire 和 battle procedure, 只替换 roster/loadout/AI。
class_name HexRandomDemoWorldGameplayInstance
extends HexDemoWorldGameplayInstance


const RandomLoadoutStrategyScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/ai/random_loadout_strategy.gd")

const FIXED_TEAM_SIZE := 3
const DEFAULT_PASSIVES_PER_ACTOR := 1
const MAX_PASSIVES_PER_ACTOR := 3


var _rng := RandomNumberGenerator.new()
var _resolved_seed: int = 0
var _team_size: int = FIXED_TEAM_SIZE
var _passives_per_actor: int = DEFAULT_PASSIVES_PER_ACTOR
var _active_pool: Array[AbilityConfig] = []
var _offensive_pool: Array[AbilityConfig] = []
var _passive_pool: Array[AbilityConfig] = []
var _shared_random_strategy: AIStrategy = null
var _loadout_summary: Array[Dictionary] = []


func _init() -> void:
	super._init()
	type = "hex_random_demo"
	HexBattleAllSkills.register_all_timelines()


func _setup_teams(config: Dictionary, _grid_config: GridMapConfig) -> void:
	_resolved_seed = _resolve_seed(int(config.get("random_seed", 0)))
	_rng.seed = _resolved_seed
	_team_size = FIXED_TEAM_SIZE
	_passives_per_actor = clampi(
		int(config.get("passives_per_actor", DEFAULT_PASSIVES_PER_ACTOR)),
		0,
		MAX_PASSIVES_PER_ACTOR
	)
	_active_pool = _build_active_skill_pool()
	_offensive_pool = _build_offensive_skill_pool(_active_pool)
	_passive_pool = _build_passive_skill_pool()
	_loadout_summary = []
	left_team = _create_random_team(0)
	right_team = _create_random_team(1)
	_assign_neutral_names(left_team, "左方")
	_assign_neutral_names(right_team, "右方")


func _after_teams_equipped(_config: Dictionary) -> void:
	_shared_random_strategy = RandomLoadoutStrategyScript.new() as AIStrategy
	_assign_team_loadouts(left_team)
	_assign_team_loadouts(right_team)


func _place_team_randomly(team: Array[CharacterActor], range_config: Dictionary) -> void:
	var available_coords: Array[HexCoord] = []
	for q in range(range_config["q_min"], range_config["q_max"] + 1):
		for r in range(range_config["r_min"], range_config["r_max"] + 1):
			var coord := HexCoord.new(q, r)
			if grid.has_tile(coord) and not grid.is_occupied(coord):
				available_coords.append(coord)
	_shuffle_hex_coords(available_coords)
	for i in range(mini(team.size(), available_coords.size())):
		var coord := available_coords[i]
		grid.place_occupant(coord, team[i])
		team[i].hex_position = coord.duplicate()


func _print_battle_info() -> void:
	print("\n随机战斗 seed: %d, team_size=%d, passives_per_actor=%d" % [
		_resolved_seed,
		_team_size,
		_passives_per_actor,
	])
	super._print_battle_info()
	print("随机 Loadout:")
	for item in _loadout_summary:
		print("  [%s] %s -> %s + passives=%s" % [
			item.get("actor_id", ""),
			item.get("actor_name", ""),
			item.get("active_skill", ""),
			str(item.get("passives", [])),
		])


func get_resolved_seed() -> int:
	return _resolved_seed


func get_random_summary() -> Dictionary:
	var replay := get_replay_data()
	var result := ""
	if not replay.is_empty():
		var meta: Dictionary = replay.get("meta", {})
		result = meta.get("result", "")
	return {
		"seed": _resolved_seed,
		"team_size": _team_size,
		"passives_per_actor": _passives_per_actor,
		"result": result,
		"actors": _loadout_summary.duplicate(true),
	}


func _resolve_seed(requested_seed: int) -> int:
	if requested_seed != 0:
		return requested_seed
	var generated := int(Time.get_ticks_usec())
	if generated == 0:
		return 1
	return generated


func _create_random_team(team_id: int) -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	var base_classes := _base_character_classes()
	var class_cycle: Array[int] = []
	for i in range(_team_size):
		if i % base_classes.size() == 0:
			class_cycle = _shuffled_ints(base_classes)
		var char_class: HexBattleClassConfig.CharacterClass = class_cycle[i % class_cycle.size()]
		result.append(_create_team_actor(char_class, team_id))
	return result


func _assign_neutral_names(team: Array[CharacterActor], prefix: String) -> void:
	for i in range(team.size()):
		team[i].set_display_name("%s %d" % [prefix, i + 1])


func _base_character_classes() -> Array[int]:
	return [
		HexBattleClassConfig.CharacterClass.PRIEST,
		HexBattleClassConfig.CharacterClass.WARRIOR,
		HexBattleClassConfig.CharacterClass.ARCHER,
		HexBattleClassConfig.CharacterClass.MAGE,
		HexBattleClassConfig.CharacterClass.BERSERKER,
		HexBattleClassConfig.CharacterClass.ASSASSIN,
	]


func _assign_team_loadouts(team: Array[CharacterActor]) -> void:
	var shuffled_team := _shuffled_actors(team)
	var offensive_slots := mini(team.size(), maxi(1, int(ceil(float(team.size()) * 0.67))))
	for i in range(shuffled_team.size()):
		_assign_actor_loadout(shuffled_team[i], i < offensive_slots)


func _assign_actor_loadout(actor: CharacterActor, force_offensive: bool) -> void:
	var active_pool := _offensive_pool if force_offensive and not _offensive_pool.is_empty() else _active_pool
	var active_cfg := _pick_config(active_pool)
	var active_ability := actor.replace_skill_ability(active_cfg, self)
	_grant_fallback_strike(actor, active_cfg)
	actor.ai_strategy = _shared_random_strategy
	var granted_passives := _grant_random_passives(actor)
	_loadout_summary.append({
		"actor_id": actor.get_id(),
		"actor_name": actor.get_display_name(),
		"team": actor.get_team_id(),
		"active_skill": active_ability.config_id,
		"active_display_name": active_ability.display_name,
		"passives": granted_passives,
	})


func _grant_fallback_strike(actor: CharacterActor, active_cfg: AbilityConfig) -> void:
	if active_cfg.config_id == HexBattleStrike.CONFIG_ID:
		return
	if actor.ability_set.has_ability(HexBattleStrike.CONFIG_ID):
		return
	var fallback_ability := Ability.new(HexBattleStrike.ABILITY, actor.get_id())
	actor.ability_set.grant_ability(fallback_ability, self)


func _grant_random_passives(actor: CharacterActor) -> Array[String]:
	var granted: Array[String] = []
	if _passives_per_actor <= 0 or _passive_pool.is_empty():
		return granted
	var candidates := _shuffled_configs(_passive_pool)
	for passive_cfg in candidates:
		if granted.size() >= _passives_per_actor:
			break
		if actor.ability_set.has_ability(passive_cfg.config_id):
			continue
		var passive_ability := Ability.new(passive_cfg, actor.get_id())
		actor.ability_set.grant_ability(passive_ability, self)
		granted.append(passive_cfg.config_id)
	return granted


func _build_active_skill_pool() -> Array[AbilityConfig]:
	var result: Array[AbilityConfig] = []
	for cfg in HexBattleAllSkills.all_abilities():
		if _is_active_loadout_config(cfg):
			result.append(cfg)
	Log.assert_crash(not result.is_empty(), "HexRandomDemoWorldGI", "active skill pool is empty")
	return result


func _build_offensive_skill_pool(source: Array[AbilityConfig]) -> Array[AbilityConfig]:
	var result: Array[AbilityConfig] = []
	for cfg in source:
		if cfg.ability_tags.has("enemy"):
			result.append(cfg)
	return result


func _build_passive_skill_pool() -> Array[AbilityConfig]:
	var result: Array[AbilityConfig] = []
	for cfg in HexBattleAllSkills.all_abilities():
		if _is_passive_loadout_config(cfg):
			result.append(cfg)
	return result


func _is_active_loadout_config(cfg: AbilityConfig) -> bool:
	if cfg == null:
		return false
	return not cfg.active_use_components.is_empty() and cfg.ability_tags.has("skill")


func _is_passive_loadout_config(cfg: AbilityConfig) -> bool:
	if cfg == null or not cfg.active_use_components.is_empty():
		return false
	if not cfg.ability_tags.has("passive"):
		return false
	if cfg.ability_tags.has("intrinsic"):
		return false
	if cfg.ability_tags.has("totem") or cfg.ability_tags.has("fire_tile"):
		return false
	if cfg.ability_tags.has("lifetime"):
		return false
	return true


func _pick_config(pool: Array[AbilityConfig]) -> AbilityConfig:
	Log.assert_crash(not pool.is_empty(), "HexRandomDemoWorldGI", "cannot pick from empty pool")
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _shuffled_configs(source: Array[AbilityConfig]) -> Array[AbilityConfig]:
	var result: Array[AbilityConfig] = []
	result.append_array(source)
	for i in range(result.size()):
		var swap_index := _rng.randi_range(i, result.size() - 1)
		var tmp := result[i]
		result[i] = result[swap_index]
		result[swap_index] = tmp
	return result


func _shuffled_actors(source: Array[CharacterActor]) -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	result.append_array(source)
	for i in range(result.size()):
		var swap_index := _rng.randi_range(i, result.size() - 1)
		var tmp := result[i]
		result[i] = result[swap_index]
		result[swap_index] = tmp
	return result


func _shuffled_ints(source: Array[int]) -> Array[int]:
	var result: Array[int] = []
	result.append_array(source)
	for i in range(result.size()):
		var swap_index := _rng.randi_range(i, result.size() - 1)
		var tmp := result[i]
		result[i] = result[swap_index]
		result[swap_index] = tmp
	return result


func _shuffle_hex_coords(coords: Array[HexCoord]) -> void:
	for i in range(coords.size()):
		var swap_index := _rng.randi_range(i, coords.size() - 1)
		var tmp := coords[i]
		coords[i] = coords[swap_index]
		coords[swap_index] = tmp
