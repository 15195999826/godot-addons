## HexBattle - 六边形战斗兼容门面
##
## 在"世界 owns 战斗"架构下(见 docs/design-notes/2026-04-19-world-as-single-instance.md),
## World(registry/grid/systems) 与 Procedure(ATB/teams/recorder) 分居两个类。
## HexBattle 做 thin 门面, 对外维持 start(config)/tick(dt) 一把入口语义,
## 内部通过 WorldGI.start_battle 起 HexBattleProcedure 推进。
class_name HexBattle
extends HexWorldGameplayInstance

## 安全上限, 与 HexBattleProcedure.MAX_TICKS 保持一致; 改动需两边同步。
const MAX_TICKS := 10000

var tick_count: int = 0
var left_team: Array[CharacterActor] = []
var right_team: Array[CharacterActor] = []
var logger: HexBattleLogger = null
var recorder: BattleRecorder = null

## 战斗是否结束。外部调用端 (`example/hex-atb-battle/main.gd`) 直接读此字段,
## 保留以避免调用点修改; `is_running()` 同样可判断。
var _ended: bool = false

## 战斗结束后缓存录像, 供 get_replay_data() 复用 —— recorder.stop_recording()
## 只能调一次, 调方拿到后可能隔几帧再读, 这里是"读过一次仍可再读"的兜底。
var _final_replay_data: Dictionary = {}

var _logging_enabled: bool = true
var _recording_enabled: bool = true

## Procedure 强引用。WorldGI.tick 结束时清空 _active_battle, 但 _on_battle_finished
## 还要访问 procedure 最终状态(tick_count / result), 由本字段延命到 handler 结束。
var _hex_procedure: HexBattleProcedure = null


func _init() -> void:
	super._init(IdGenerator.generate("battle"))
	type = "hex_battle"
	battle_finished.connect(_on_battle_finished)


## 启动战斗。config 键:
##   - logging: bool        启用日志 (默认 true)
##   - recording: bool      启用录像 (默认 true)
##   - console_log: bool    日志同时输出到控制台 (默认 false)
##   - file_log: bool       日志写到文件 (默认 true)
##   - map_config: GridMapConfig  地图配置 (默认 9x9 ROW_COLUMN FLAT)
func start(config: Dictionary = {}) -> void:
	super.start()
	print("\n========== HexBattle 开始 ==========\n")

	_logging_enabled = config.get("logging", true)
	_recording_enabled = config.get("recording", true)

	var grid_config := config.get("map_config", null) as GridMapConfig
	if grid_config == null:
		grid_config = _build_default_grid_config()
	configure_grid(grid_config)

	var collision_detector := MobaCollisionDetector.new()
	var projectile_system := ProjectileSystem.new(collision_detector, GameWorld.event_collector, false)
	add_system(projectile_system)

	left_team = [
		add_actor(CharacterActor.new(HexBattleClassConfig.CharacterClass.PRIEST)) as CharacterActor,
		add_actor(CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)) as CharacterActor,
		add_actor(CharacterActor.new(HexBattleClassConfig.CharacterClass.ARCHER)) as CharacterActor,
	]
	right_team = [
		add_actor(CharacterActor.new(HexBattleClassConfig.CharacterClass.MAGE)) as CharacterActor,
		add_actor(CharacterActor.new(HexBattleClassConfig.CharacterClass.BERSERKER)) as CharacterActor,
		add_actor(CharacterActor.new(HexBattleClassConfig.CharacterClass.ASSASSIN)) as CharacterActor,
	]
	for actor in left_team:
		actor.set_team_id(0)
	for actor in right_team:
		actor.set_team_id(1)
	for actor in get_all_actors():
		actor.equip_abilities()

	var placement_ranges := _calculate_placement_ranges(grid_config)
	_place_team_randomly(left_team, placement_ranges["left"])
	_place_team_randomly(right_team, placement_ranges["right"])

	_apply_inspire_buff_to_all()
	HexBattleAllSkills.register_all_timelines()

	print("战斗开始")
	_print_battle_info()

	var participants_as_actors: Array[Actor] = []
	for actor in get_all_actors():
		participants_as_actors.append(actor)
	start_battle(participants_as_actors)

	if _hex_procedure != null:
		recorder = _hex_procedure.get_recorder()
		logger = _hex_procedure.logger


func tick(dt: float) -> void:
	super.tick(dt)
	if _hex_procedure != null:
		tick_count = _hex_procedure.get_current_tick()


func _create_battle_procedure(_participants: Array[Actor]) -> BattleProcedure:
	_hex_procedure = HexBattleProcedure.new(self, left_team, right_team, {
		"logging": _logging_enabled,
		"recording": _recording_enabled,
		"console_log": false,
		"file_log": true,
	})
	return _hex_procedure


func _on_battle_finished(timeline: Dictionary) -> void:
	_ended = true
	_final_replay_data = timeline
	var proc_result := ""
	if _hex_procedure != null:
		proc_result = _hex_procedure.get_result()
		tick_count = _hex_procedure.get_current_tick()
	print("\n========== HexBattle 结束 ==========")
	print("总帧数: %d" % tick_count)
	print("逻辑时间: %.1f ms" % _logic_time)
	if proc_result != "":
		print("结果: %s" % proc_result)
	end()
	_save_replay(_final_replay_data)
	_hex_procedure = null


func get_all_actors() -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	result.append_array(left_team)
	result.append_array(right_team)
	return result


func get_alive_actors() -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	for actor in get_all_actors():
		if not actor.is_dead():
			result.append(actor)
	return result


# ========== 录像 / 日志 ==========

## 获取录像数据。战斗进行中返回当前录像(会停止录像), 结束后返回最终录像。
func get_replay_data() -> Dictionary:
	if not _final_replay_data.is_empty():
		return _final_replay_data
	if recorder != null and recorder.get_is_recording():
		return recorder.stop_recording()
	return {}


func get_log_dir() -> String:
	if logger != null:
		return logger.get_battle_dir()
	return ""


func _save_replay(replay_data: Dictionary) -> void:
	if replay_data.is_empty():
		return

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var replay_path := "user://Replays/battle_%s_%s.json" % [timestamp, id]
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("Replays"):
		dir.make_dir("Replays")

	var file := FileAccess.open(replay_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(replay_data, "\t"))
		file.close()
		print("📼 录像已保存到: %s" % replay_path)
	else:
		push_error("[HexBattle] 无法保存录像: %s" % replay_path)


# ========== 战斗布阵辅助 ==========

## 构建默认地图配置(9x9 ROW_COLUMN, FLAT 方向, size=10)
func _build_default_grid_config() -> GridMapConfig:
	var config := GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
	config.rows = 9
	config.columns = 9
	config.size = 10.0
	config.orientation = GridMapConfig.Orientation.FLAT
	return config


## 根据地图配置计算队伍放置区域
func _calculate_placement_ranges(grid_config: GridMapConfig) -> Dictionary:
	if grid_config.draw_mode == GridMapConfig.DrawMode.RADIUS:
		var half := maxi(1, grid_config.radius / 2)
		return {
			"left": { "q_min": -grid_config.radius, "q_max": -1, "r_min": -half, "r_max": half },
			"right": { "q_min": 1, "q_max": grid_config.radius, "r_min": -half, "r_max": half },
		}
	var half_rows := grid_config.rows / 2
	var half_cols := grid_config.columns / 2
	var left_q_max := -1
	var left_q_min := -half_cols
	var right_q_min := 1
	var right_q_max := half_cols
	var r_range := maxi(1, half_rows / 2)
	return {
		"left": { "q_min": left_q_min, "q_max": left_q_max, "r_min": -r_range, "r_max": r_range },
		"right": { "q_min": right_q_min, "q_max": right_q_max, "r_min": -r_range, "r_max": r_range },
	}


func _place_team_randomly(team: Array[CharacterActor], range_config: Dictionary) -> void:
	var available_coords: Array[HexCoord] = []
	for q in range(range_config["q_min"], range_config["q_max"] + 1):
		for r in range(range_config["r_min"], range_config["r_max"] + 1):
			var coord := HexCoord.new(q, r)
			if grid.has_tile(coord) and not grid.is_occupied(coord):
				available_coords.append(coord)
	available_coords.shuffle()
	for i in range(mini(team.size(), available_coords.size())):
		var coord: HexCoord = available_coords[i]
		grid.place_occupant(coord, team[i])
		team[i].hex_position = coord.duplicate()


func _apply_inspire_buff_to_all() -> void:
	for actor in get_all_actors():
		var inspire_buff := Ability.new(HexBattleInspireBuff.INSPIRE_BUFF, actor.get_id())
		actor.ability_set.grant_ability(inspire_buff)
		var current_def: float = actor.attribute_set.def
		print("  %s 获得振奋 Buff: DEF %.0f -> %.0f (+%.0f)" % [
			actor.get_display_name(),
			current_def - HexBattleInspireBuff.INSPIRE_DEF_BONUS,
			current_def,
			HexBattleInspireBuff.INSPIRE_DEF_BONUS,
		])


func _register_timelines() -> void:
	HexBattleAllSkills.register_all_timelines()


func _print_battle_info() -> void:
	print("\n角色信息:")
	print("-".repeat(70))
	for actor in get_all_actors():
		var pos := actor.hex_position
		var skill: Ability = actor.get_skill_ability()
		var team_label := "左方" if actor.get_team_id() == 0 else "右方"
		var pos_str := "(%d, %d)" % [pos.q, pos.r] if pos != null else "未放置"
		print("  [%s] %s (%s)" % [actor.get_id(), actor.get_display_name(), team_label])
		print("    位置: %s" % pos_str)
		print("    属性: HP=%.0f/%.0f ATK=%.0f DEF=%.0f SPD=%.0f" % [
			actor.attribute_set.hp, actor.attribute_set.max_hp,
			actor.attribute_set.atk, actor.attribute_set.def, actor.attribute_set.speed,
		])
		print("    技能: %s" % (skill.display_name if skill != null else "无"))
		print("")
	print("-".repeat(70))
