## SkillPreviewProcedure - 技能预览战斗过程
##
## BattleProcedure 的 skill_preview 特化：不跑 ATB / AI / 胜负判定，直接让
## caster 施放指定 ability，tick 到"所有技能无 executing instance 且无飞行
## 投射物"后 +POST_EXECUTION_TICKS 延迟关停。承接原 SkillPreviewBattle 的
## tick loop 语义，但寄生在外部常驻 WorldGI 上 —— 不 GameWorld.destroy()，
## actor 生命周期归 world 管，procedure 结束后可再次 start_battle。
##
## 由 SkillPreviewWorldGI._create_battle_procedure 构造；preview 参数通过
## SkillPreviewWorldGI.queue_preview 预存。
class_name SkillPreviewProcedure
extends BattleProcedure


## 安全上限，防止死循环。
const MAX_TICKS := 500

## 技能 executing 清空后再 tick 的缓冲，等投射物落完 / 延迟伤害触发。
const POST_EXECUTION_TICKS := 10


# ========== 字段 ==========

var _caster_id: String
var _ability_config: AbilityConfig
var _target_id: String
var _passive_configs: Array[AbilityConfig] = []
var _post_countdown: int = -1
var _preview_ability_instance_id: String = ""


# ========== 初始化 ==========

func _init(
	world: WorldGameplayInstance,
	participants: Array[Actor],
	caster_id: String,
	ability_config: AbilityConfig,
	target_id: String = "",
	passives: Array[AbilityConfig] = [],
) -> void:
	super._init(world, participants)
	_caster_id = caster_id
	_ability_config = ability_config
	_target_id = target_id
	# duplicate 防御调方后续 mutate 数组反向影响 procedure
	_passive_configs = passives.duplicate()


# ========== 生命周期 ==========

## 走旧版 start_recording 路径保留 initial_actors / map_config，让
## FrontendBattleAnimator 消费 timeline dict 时 BattleRecord.from_dict 能正常构造。
func _start_recorder() -> void:
	if _recorder == null:
		return
	var world := _get_world() as HexWorldGameplayInstance
	var replay_map_config: Dictionary = {}
	if world != null and world.grid != null:
		replay_map_config = world.grid.to_config_dict()
	var actors: Array[Actor] = []
	for pid in _participant_ids:
		var a := _get_actor(pid)
		if a != null:
			actors.append(a)
	_recorder.start_recording(actors, {
		"positionFormats": {"Character": "hex"},
	}, replay_map_config)


func start() -> void:
	super.start()
	var world := _get_world()
	if world == null:
		mark_finished()
		return
	var caster := world.get_actor(_caster_id) as CharacterActor
	if caster == null:
		mark_finished()
		return

	for passive_cfg in _passive_configs:
		if passive_cfg != null:
			caster.ability_set.grant_ability(Ability.new(passive_cfg, caster.get_id()), world)

	if _ability_config == null:
		mark_finished()
		return
	var ability := Ability.new(_ability_config, caster.get_id())
	_preview_ability_instance_id = ability.id
	caster.ability_set.grant_ability(ability, world)

	var activate_event := {
		"kind": GameEvent.ABILITY_ACTIVATE_EVENT,
		"abilityInstanceId": ability.id,
		"sourceId": caster.get_id(),
		"logicTime": 0.0,
	}
	if _target_id != "":
		activate_event["target_actor_id"] = _target_id
	caster.ability_set.receive_event(activate_event, world)


func tick_once() -> void:
	if _finished:
		return
	_current_tick += 1

	var world := _get_world() as HexWorldGameplayInstance
	if world != null:
		world.base_tick(_tick_interval)

	var cur_logic_time := world.get_logic_time() if world != null else float(_current_tick) * _tick_interval

	# 合并两件事到同一循环:跑 ability tick + 探测 executing ability。避免 _still_executing
	# 再全量扫一遍 world.get_actors() 里的 CharacterActor 与其 abilities。
	var any_ability_executing := false
	for pid in _participant_ids:
		var actor := _get_actor(pid)
		if actor is CharacterActor:
			var cchar := actor as CharacterActor
			cchar.ability_set.tick(_tick_interval, cur_logic_time)
			cchar.ability_set.tick_executions(_tick_interval, world)
			if not any_ability_executing:
				for ability in cchar.ability_set.get_abilities():
					if not ability.is_expired() and ability.get_executing_instances().size() > 0:
						any_ability_executing = true
						break

	if world != null:
		world.broadcast_projectile_events()

	record_current_frame_events()

	if _current_tick >= MAX_TICKS:
		mark_finished()
		return

	if _post_countdown < 0:
		if not (any_ability_executing or _any_projectile_flying(world)):
			_post_countdown = POST_EXECUTION_TICKS
	else:
		_post_countdown -= 1
		if _post_countdown <= 0:
			mark_finished()


# ========== Virtual hooks ==========

func _mark_in_combat(actor_id: String, active: bool) -> void:
	var world := _get_world()
	if world == null:
		return
	var actor := world.get_actor(actor_id)
	if actor == null or not (actor is CharacterActor):
		return
	var cchar := actor as CharacterActor
	if cchar.ability_set == null:
		return
	if active:
		cchar.ability_set.add_loose_tag("in_combat")
	else:
		cchar.ability_set.remove_loose_tag("in_combat")


# ========== 内部工具 ==========

## 扫 world.get_actors() 里是否有飞行中的投射物。仅此一项 —— ability executing
## 探测在 tick_once 循环里顺带做了,不再重复扫 CharacterActor。
func _any_projectile_flying(world: HexWorldGameplayInstance) -> bool:
	if world == null:
		return false
	for actor in world.get_actors():
		if actor is ProjectileActor and (actor as ProjectileActor).is_flying():
			return true
	return false
