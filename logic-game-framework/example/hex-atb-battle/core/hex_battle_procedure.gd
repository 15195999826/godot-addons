## HexBattleProcedure - 六边形 ATB 战斗过程
##
## BattleProcedure 的 hex 特化: ATB 累积、AI 决策、技能施放、投射物事件广播、
## 胜负判定(某方全灭)、MAX_TICKS 安全上限。
##
## 由 HexWorldGameplayInstance(或其兼容子类 HexBattle)通过 start_battle 创建,
## 战斗结束即随 WorldGI._active_battle 释放。
class_name HexBattleProcedure
extends BattleProcedure

## 安全上限, 防止死循环。正常战斗由 _check_battle_end() 判定某方全灭结束。
const MAX_TICKS := 10000


# ========== 字段 ==========

var left_team: Array[CharacterActor] = []
var right_team: Array[CharacterActor] = []
var logger: HexBattleLogger = null

var _world_instance: HexWorldGameplayInstance = null
var _logging_enabled: bool = true
var _recording_enabled: bool = true
var _result: String = ""


# ========== 初始化 ==========

## opts 键:
##   - logging: bool           启用日志
##   - recording: bool         启用录像
##   - console_log: bool       日志同时输出到控制台
##   - file_log: bool          日志写到文件
func _init(
	world: HexWorldGameplayInstance,
	left: Array[CharacterActor],
	right: Array[CharacterActor],
	opts: Dictionary = {},
) -> void:
	var all_actors: Array[Actor] = []
	for a in left:
		all_actors.append(a)
	for a in right:
		all_actors.append(a)
	super._init(world, all_actors)
	_world_instance = world
	left_team = left
	right_team = right
	_logging_enabled = opts.get("logging", true)
	_recording_enabled = opts.get("recording", true)
	if _logging_enabled:
		logger = HexBattleLogger.new(world.id, {
			"console": opts.get("console_log", false),
			"file": opts.get("file_log", true),
		})


# ========== 生命周期 ==========

func start() -> void:
	super.start()
	if logger != null:
		for actor in get_all_characters():
			logger.register_actor(actor.get_id(), actor.get_display_name())


## 沿用带 initial_actors 的旧录像格式以兼容 FrontendBattleReplayScene / WebBridge;
## 录像格式 v3(split world_snapshot + event_timeline) 落地时再切到 start_recording_events_only。
func _start_recorder() -> void:
	if not _recording_enabled or _recorder == null:
		return
	var replay_map_config: Dictionary = {}
	if _world_instance != null and _world_instance.grid != null:
		replay_map_config = _world_instance.grid.to_config_dict()
	var configs := {
		"positionFormats": {
			"Character": "hex",
			"Environment": "hex",
		},
	}
	_recorder.start_recording(get_all_characters(), configs, replay_map_config)


func tick_once() -> void:
	if _finished:
		return
	_current_tick += 1

	var world := _world_instance
	if world != null:
		world.base_tick(_tick_interval)

	var cur_logic_time := world.get_logic_time() if world != null else float(_current_tick) * _tick_interval

	if _logging_enabled and logger != null:
		logger.tick(_current_tick, cur_logic_time)

	if world != null:
		world.broadcast_projectile_events()

	# ATB 与技能执行互斥: 施法期间 ATB 冻结, 不继续充能(经典 ATB 模式)。
	for actor in get_alive_characters():
		if HexBattleProcedure.tick_actor_ability_runtime(actor, _tick_interval, cur_logic_time, world):
			continue
		actor.accumulate_atb(_tick_interval)
		if actor.can_act():
			_start_actor_action(actor, cur_logic_time)

	# Phase C0/C: 战斗中途 spawn 的 CharacterActor (totem) + EnvironmentActor (fire tile)
	# 也要 tick ability_set + tick_executions, 否则 TotemAttack / FireTilePulse periodic
	# timeline 永不 fire, lifetime 永不 expire — production demo battle 才会触发。
	# initial team 已在上方主循环处理, 这里只补 mid-spawn 的 HexBattleActor。
	if world != null:
		var seen_ids: Dictionary = {}
		for a in get_alive_characters():
			seen_ids[a.get_id()] = true
		for actor in world.get_actors():
			if not (actor is HexBattleActor):
				continue
			var h := actor as HexBattleActor
			if seen_ids.has(h.get_id()):
				continue
			# CharacterActor mid-spawn: tick + executions (与 production 主循环对齐, 但不进 ATB/AI)
			# EnvironmentActor (fire tile): 同上 tick + executions
			h.ability_set.tick(_tick_interval, cur_logic_time)
			h.ability_set.tick_executions(_tick_interval, world)

	record_current_frame_events()

	if _current_tick >= MAX_TICKS:
		print("\n战斗结束(达到安全上限 %d 帧, 可能存在死循环)" % MAX_TICKS)
		_result = "timeout"
		mark_finished()
	else:
		_check_battle_end()


func finish(result: String = "") -> Dictionary:
	var effective := result if result != "" else _result
	if effective == "":
		effective = "battle_complete"
	var replay := super.finish(effective)
	if logger != null:
		logger.save()
	return replay


# ========== Virtual hooks ==========

func _mark_in_combat(actor_id: String, active: bool) -> void:
	var world := _world_instance
	if world == null:
		return
	var actor := world.get_actor(actor_id)
	if actor == null or actor.ability_set == null:
		return
	if active:
		actor.ability_set.add_loose_tag("in_combat")
	else:
		actor.ability_set.remove_loose_tag("in_combat")


# ========== 查询 ==========

func get_all_characters() -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	result.append_array(left_team)
	result.append_array(right_team)
	return result


func get_alive_characters() -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	for actor in get_all_characters():
		if not actor.is_dead():
			result.append(actor)
	return result


func get_result() -> String:
	return _result


# ========== 战斗主循环辅助 ==========

static func actor_has_executing_ability(actor: CharacterActor) -> bool:
	for ability in actor.ability_set.get_abilities():
		if ability.get_executing_instances().size() > 0:
			return true
	return false


## 正式 hex battle 的 ability runtime tick。
## SkillPreviewProcedure 复用这里, 只替换"选择/启动 action"阶段, 不另写 ability tick 合同。
static func tick_actor_ability_runtime(
	actor: CharacterActor,
	tick_interval: float,
	logic_time: float,
	world: HexWorldGameplayInstance,
) -> bool:
	actor.ability_set.tick(tick_interval, logic_time)
	if HexBattleProcedure.actor_has_executing_ability(actor):
		actor.ability_set.tick_executions(tick_interval, world)
		return true
	return false


func _is_actor_executing(actor: CharacterActor) -> bool:
	return HexBattleProcedure.actor_has_executing_ability(actor)


func _start_actor_action(actor: CharacterActor, logic_time: float) -> void:
	var world := _world_instance
	print("\n[Tick %d] %s 准备行动 (ATB: %.1f)" % [_current_tick, actor.get_display_name(), actor.get_atb_gauge()])

	if _logging_enabled and logger != null:
		logger.actor_ready(actor.get_id(), actor.get_display_name(), actor.get_atb_gauge())

	var decision := _decide_action(actor)

	if decision["type"] == "skip":
		print("  %s 无法行动, 跳过本次决策" % actor.get_display_name())
		if _logging_enabled and logger != null:
			logger.ai_decision(actor.get_id(), actor.get_display_name(), "跳过(无可用行动)")
		actor.reset_atb()
		return

	var decision_text := ""
	if decision["type"] == "move":
		var coord: HexCoord = decision["target_coord"] as HexCoord
		decision_text = "移动到 (%d, %d)" % [coord.q, coord.r]
	else:
		var target_id: String = decision.get("target_actor_id", "")
		var target_actor: CharacterActor = null
		if world != null:
			target_actor = world.get_character_actor(target_id)
		var target_name := target_actor.get_display_name() if target_actor != null else "未知"
		var skill := actor.get_skill_ability()
		var skill_name := skill.display_name if skill != null else "技能"
		decision_text = "%s -> %s" % [skill_name, target_name]

	print("  AI 决策: %s" % decision_text)
	if _logging_enabled and logger != null:
		logger.ai_decision(actor.get_id(), actor.get_display_name(), decision_text)

	var event := _create_action_use_event(
		decision["ability_instance_id"],
		actor.get_id(),
		decision.get("target_actor_id", ""),
		decision.get("target_coord", null),
		logic_time,
	)

	actor.ability_set.receive_event(event, world)
	actor.reset_atb()


## AI 决策: 委托给 actor 的 AI 策略对象。
## game_state 参数传 world instance(运行时 HexBattle 实例, 兼容现有 AI/Action 转型)。
func _decide_action(actor: CharacterActor) -> Dictionary:
	return actor.ai_strategy.decide(actor, _world_instance)


func _create_action_use_event(
	ability_instance_id: String,
	source_id: String,
	target_actor_id: String,
	target_coord: Variant,
	logic_time: float,
) -> Dictionary:
	var event := {
		"kind": GameEvent.ABILITY_ACTIVATE_EVENT,
		"abilityInstanceId": ability_instance_id,
		"sourceId": source_id,
		"logicTime": logic_time,
	}
	if target_actor_id != "":
		event["target_actor_id"] = target_actor_id
	if target_coord != null and target_coord is HexCoord:
		event["target_coord"] = (target_coord as HexCoord).to_dict()
	return event


func _check_battle_end() -> bool:
	var left_alive := 0
	var right_alive := 0

	for actor in left_team:
		if not actor.is_dead():
			left_alive += 1
	for actor in right_team:
		if not actor.is_dead():
			right_alive += 1

	if left_alive == 0:
		print("\n战斗结束: 右方胜利!")
		_result = "right_win"
		mark_finished()
		return true
	elif right_alive == 0:
		print("\n战斗结束: 左方胜利!")
		_result = "left_win"
		mark_finished()
		return true

	return false
