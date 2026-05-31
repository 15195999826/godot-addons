## HexDemoWorldGameplayInstance - 6v6 demo 战斗场景的 world instance
##
## HexWorldGameplayInstance 的 demo 场景子类: 6 职业 vs 6 职业默认 9x9 战斗,
## 含 inspire buff / 队伍随机放置 / 录像存盘 / 战斗信息打印 等 demo 行为。
##
## 服务三处 demo entry: addons/.../hex-atb-battle/logic/demo_headless.gd,
## addons/.../hex-atb-battle/frontend/demo_frontend.gd, scripts/SimulationManager.gd
## (web 桥接 godot_run_battle)。skill-preview 走 SkillPreviewWorldGI, 不走这里。
##
## 与 SkillPreviewWorldGI 范式一致: 每个独立场景拥有自己的 GI 子类,
## 框架类 HexWorldGameplayInstance 保持通用不含 demo hardcode。
##
## 详见 docs/README.md（World owns Battle + 响应式前端 节）。
class_name HexDemoWorldGameplayInstance
extends HexWorldGameplayInstance


var tick_count: int = 0
var left_team: Array[CharacterActor] = []
var right_team: Array[CharacterActor] = []
var _ended: bool = false

## recorder.stop_recording() 单次有效, 缓存兜底"读过一次仍可再读"。
var _final_replay_data: Dictionary = {}

var _logging_enabled: bool = true
var _recording_enabled: bool = true

## 延命到 _on_battle_finished handler 结束: WorldGI.tick 末尾清 _active_battle,
## 但 handler 还要读 procedure 最终状态。
var _hex_procedure: HexBattleProcedure = null


func _init() -> void:
	super._init(IdGenerator.generate("demo"))
	type = "hex_demo"
	battle_finished.connect(_on_battle_finished)


## 启动 demo 战斗。config 键:
##   - logging: bool        启用日志 (默认 true)
##   - recording: bool      启用录像 (默认 true)
##   - console_log: bool    日志同时输出到控制台 (默认 false)
##   - file_log: bool       日志写到文件 (默认 true)
##   - map_config: GridMapConfig  地图配置 (默认 9x9 ROW_COLUMN FLAT)
func start(config: Dictionary = {}) -> void:
	super.start()
	print("\n========== Hex Demo Battle 开始 ==========\n")

	_logging_enabled = config.get("logging", true)
	_recording_enabled = config.get("recording", true)

	var grid_config := config.get("map_config", null) as GridMapConfig
	if grid_config == null:
		grid_config = _build_default_grid_config()
	configure_grid(grid_config)

	var collision_detector := MobaCollisionDetector.new()
	var projectile_system := ProjectileSystem.new(collision_detector, GameWorld.event_collector, false)
	add_system(projectile_system)

	# team_id 必须在 add_actor 之前设置:add_actor emit actor_added signal,
	# WorldView 收到后立刻 _hydrate_from_actor 读 team_id 决定颜色;晚设会让
	# view 一律按默认 team=0 染色。
	_setup_teams(config, grid_config)
	for actor in get_all_actors():
		actor.equip_abilities(self)
	_after_teams_equipped(config)

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
		logger = _hex_procedure.logger


func tick(dt: float) -> void:
	super.tick(dt)
	if _hex_procedure != null:
		tick_count = _hex_procedure.get_current_tick()


func _create_team_actor(cls: HexBattleClassConfig.CharacterClass, team_id: int) -> CharacterActor:
	var actor := CharacterActor.new(cls)
	actor.set_team_id(team_id)
	return add_actor(actor) as CharacterActor


func _setup_teams(_config: Dictionary, _grid_config: GridMapConfig) -> void:
	left_team = [
		_create_team_actor(HexBattleClassConfig.CharacterClass.PRIEST, 0),
		_create_team_actor(HexBattleClassConfig.CharacterClass.WARRIOR, 0),
		_create_team_actor(HexBattleClassConfig.CharacterClass.ARCHER, 0),
	]
	right_team = [
		_create_team_actor(HexBattleClassConfig.CharacterClass.MAGE, 1),
		_create_team_actor(HexBattleClassConfig.CharacterClass.BERSERKER, 1),
		_create_team_actor(HexBattleClassConfig.CharacterClass.ASSASSIN, 1),
	]


func _after_teams_equipped(_config: Dictionary) -> void:
	pass


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
	print("\n========== Hex Demo Battle 结束 ==========")
	print("总帧数: %d" % tick_count)
	print("逻辑时间: %.1f ms" % _logic_time)
	if proc_result != "":
		print("结果: %s" % proc_result)
	end()
	_save_replay(_final_replay_data)
	_hex_procedure = null


## 走 left_team + right_team staging 让"队伍语义"显式可读, 不走 actor registry。
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
	var rec: BattleRecorder = _hex_procedure.get_recorder() if _hex_procedure != null else null
	if rec != null and rec.get_is_recording():
		return rec.stop_recording()
	return {}


func get_log_dir() -> String:
	if logger != null:
		return logger.get_battle_dir()
	return ""


func _save_replay(replay_data: Dictionary) -> void:
	if replay_data.is_empty():
		return

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var replay_path := "user://Replays/demo_%s_%s.json" % [timestamp, id]
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("Replays"):
		dir.make_dir("Replays")

	var file := FileAccess.open(replay_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(replay_data, "\t"))
		file.close()
		print("📼 录像已保存到: %s" % replay_path)
	else:
		push_error("[HexDemoWorldGI] 无法保存录像: %s" % replay_path)


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
		var coord := available_coords[i]
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
