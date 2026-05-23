## SpawnActorAction - 战斗中途 spawn 一个新 CharacterActor
##
## V1 用例: Phase C0 Summon Totem 主动技能在 timeline HIT 调用本 action 召唤图腾。
##
## 合同:
## - actor source: caster (ctx.ability_ref.owner_actor_id) → 新 actor 的 source_actor_id
## - team list: 新 actor 继承 caster team_id (HexBattleProcedure / SkillPreview 都消费 team_id)
## - spawn position: caster.hex_position 的某个邻格 (第一个未占的 6 邻格); 全占满则 spawn 失败
## - grant abilities: action 配置传入 AbilityConfig 列表 (TotemAttack / TotemLifetime 等), 在 spawn
##   后立即 grant 给新 actor; GRANTED_SELF trigger 自激活 periodic timeline
## - spawn 立即 add_actor + place_occupant; 不延迟 / 不排队
## - 失败语义: 邻格全占满 → 返回 success + metadata { spawn_failed: "no_free_neighbor" }
##   (不算 action 失败, 不 abort skill timeline; caller 期望简单 best-effort)
class_name HexBattleSpawnActorAction
extends Action.PrimitiveAction


var _character_class: HexBattleClassConfig.CharacterClass
var _grant_ability_configs: Array
var _attribute_overrides: Dictionary


func _init(
	target_selector: TargetSelector,
	char_class: HexBattleClassConfig.CharacterClass,
	grant_ability_configs: Array = [],
	attribute_overrides: Dictionary = {},
) -> void:
	super._init(target_selector)
	type = "spawn_actor"
	_character_class = char_class
	_grant_ability_configs = grant_ability_configs.duplicate(true)
	_attribute_overrides = attribute_overrides.duplicate(true)


func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	if battle == null:
		return ActionResult.create_success_result([], { "spawn_failed": "no_game_state" })
	var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if caster_id.is_empty():
		return ActionResult.create_success_result([], { "spawn_failed": "no_caster" })
	var caster := battle.get_actor(caster_id) as CharacterActor
	if caster == null:
		return ActionResult.create_success_result([], { "spawn_failed": "caster_missing" })

	var spawn_coord := _find_free_neighbor(battle, caster.hex_position)
	if spawn_coord == null:
		return ActionResult.create_success_result([], { "spawn_failed": "no_free_neighbor" })

	var spawned := CharacterActor.new(_character_class)
	battle.add_actor(spawned)
	spawned.set_team_id(caster.get_team_id())
	battle.grid.place_occupant(spawn_coord, spawned)
	spawned.hex_position = spawn_coord

	# 属性覆盖 (可选: max_hp / atk / def / speed)
	if not _attribute_overrides.is_empty():
		if _attribute_overrides.has("max_hp"):
			spawned.attribute_set.set_max_hp_base(_attribute_overrides["max_hp"] as float)
		if _attribute_overrides.has("hp"):
			spawned.attribute_set.set_hp_base(_attribute_overrides["hp"] as float)
		if _attribute_overrides.has("atk"):
			spawned.attribute_set.set_atk_base(_attribute_overrides["atk"] as float)

	# Grant abilities (passive periodic timeline / TimeDuration lifetime etc.)
	for cfg in _grant_ability_configs:
		if cfg is AbilityConfig:
			var ab := Ability.new(cfg, spawned.get_id(), caster_id)
			spawned.ability_set.grant_ability(ab, battle)

	return ActionResult.create_success_result([], {
		"spawned_actor_id": spawned.get_id(),
		"spawn_coord": [spawn_coord.q, spawn_coord.r],
	})


## 找 anchor 的第一个未占邻格。全占满返回 null。
static func _find_free_neighbor(battle: HexWorldGameplayInstance, anchor: HexCoord) -> HexCoord:
	for neighbor in anchor.get_neighbors():
		if not battle.grid.has_tile(neighbor):
			continue
		if battle.grid.get_occupant(neighbor) == null:
			return neighbor
	return null
