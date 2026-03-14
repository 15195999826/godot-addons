## HexBattle - 六边形战斗实例
##
## 实现 ATB 战斗系统的主类
##
## ========== 架构设计 ==========
##
## 本类遵循 TS 侧 InkMonBattle 的设计，核心原则：
##
## 1. **Action 内状态同步**：
##    - 所有状态变更（扣血/加血/死亡）都在 Action.execute() 内完成
##    - push 事件 + 应用状态 + post 事件 是原子操作
##    - tick() 不做任何状态同步，只收集事件用于录像
##
## 2. **EventCollector 仅供录像/表演层消费**：
##    - 不参与逻辑状态同步
##    - flush() 只在 tick 结束时调用，用于录像记录
##
## 3. **ATB 行动系统**：
##    - 每帧累积 ATB，满值时触发行动
##    - 行动开始立即重置 ATB，不等待执行完成
##    - Timeline 由 tickExecutions(dt) 逐帧推进
##
## 4. 状态变更在 Action 内立即完成
##    tick() 只调用 flush() 收集事件用于录像
##
class_name HexBattle
extends GameplayInstance

# ========== 常量 ==========

## 安全上限，防止死循环。正常战斗由 _check_battle_end() 判定某方全灭结束。
const MAX_TICKS := 10000


# ========== 属性 ==========

var tick_count: int = 0

## 地图（通过 UGridMap autoload 访问）
## 使用 UGridMap.model 获取当前地图实例
var grid: GridMapModel:
	get:
		return UGridMap.model

## 队伍
var left_team: Array[CharacterActor] = []
var right_team: Array[CharacterActor] = []



## 战斗是否结束
var _ended: bool = false

## 战斗日志管理器
var logger: HexBattleLogger

## 战斗录像器
var recorder: BattleRecorder

## 投射物系统
var projectile_system: ProjectileSystem

## 最终录像数据（战斗结束后可访问）
var _final_replay_data: Dictionary = {}

## 是否启用日志
var _logging_enabled: bool = true

## 是否启用录像
var _recording_enabled: bool = true


# ========== 初始化 ==========

func _init() -> void:
	super._init(IdGenerator.generate("battle"))
	type = "hex_battle"


## 开始战斗
## config 参数:
##   - logging: bool - 是否启用日志 (默认 true)
##   - recording: bool - 是否启用录像 (默认 true)
##   - console_log: bool - 是否输出到控制台 (默认 false)
##   - file_log: bool - 是否输出到文件 (默认 true)
##   - map_config: GridMapConfig - 地图配置（可选，不传则使用默认 9x9 ROW_COLUMN）
func start(config: Dictionary = {}) -> void:
	super.start()
	print("\n========== HexBattle 开始 ==========\n")
	
	_logging_enabled = config.get("logging", true)
	_recording_enabled = config.get("recording", true)
	
	if _logging_enabled:
		logger = HexBattleLogger.new(id, {
			"console": config.get("console_log", false),  # 默认不输出到控制台（已有 print）
			"file": config.get("file_log", true),
		})
	
	if _recording_enabled:
		recorder = BattleRecorder.new({
			"battleId": id,
			"tickInterval": 100,
		})
	
	# 初始化投射物系统
	# 使用 MOBA 类型的碰撞检测器（追踪型投射物）
	var collision_detector := MobaCollisionDetector.new()  # 命中距离由投射物 config.hitDistance 控制
	projectile_system = ProjectileSystem.new(collision_detector, GameWorld.event_collector, false)  # auto_remove=false，手动管理
	add_system(projectile_system)
	
	var grid_config := config.get("map_config", null) as GridMapConfig
	if grid_config == null:
		grid_config = _build_default_grid_config()
	UGridMap.configure(grid_config)
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
	_register_timelines()
	
	print("战斗开始")
	_print_battle_info()
	
	if _recording_enabled and recorder != null:
		var replay_map_config: Dictionary = {}
		if UGridMap.model != null:
			replay_map_config = UGridMap.model.to_config_dict()
		var configs := {
			"positionFormats": {
				"Character": "hex",  # CharacterActor 的 position 是 hex 坐标
			}
		}
		recorder.start_recording(get_all_actors(), configs, replay_map_config)
	
	if _logging_enabled and logger != null:
		for actor in get_all_actors():
			logger.register_actor(actor.get_id(), actor.get_display_name())


## 构建默认地图配置（9x9 ROW_COLUMN，FLAT 方向，size=10）
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
		# Radius 模式：左队在负 q 区域，右队在正 q 区域
		var half := maxi(1, grid_config.radius / 2)
		return {
			"left": { "q_min": -grid_config.radius, "q_max": -1, "r_min": -half, "r_max": half },
			"right": { "q_min": 1, "q_max": grid_config.radius, "r_min": -half, "r_max": half },
		}
	else:
		# Row/Column 模式：根据行列数计算
		var half_rows := grid_config.rows / 2
		var half_cols := grid_config.columns / 2
		
		# 左队在左半边，右队在右半边
		var left_q_max := -1
		var left_q_min := -half_cols
		var right_q_min := 1
		var right_q_max := half_cols
		
		# r 范围取中间区域
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
			if UGridMap.model.has_tile(coord) and not UGridMap.model.is_occupied(coord):
				available_coords.append(coord)
	
	available_coords.shuffle()
	
	for i in range(mini(team.size(), available_coords.size())):
		var coord: HexCoord = available_coords[i]
		UGridMap.model.place_occupant(coord, team[i])
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
			HexBattleInspireBuff.INSPIRE_DEF_BONUS
		])


func _register_timelines() -> void:
	for timeline in HexBattleSkillTimelines.get_all_timelines():
		TimelineRegistry.register(timeline)


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
			actor.attribute_set.atk, actor.attribute_set.def, actor.attribute_set.speed
		])
		print("    技能: %s" % (skill.display_name if skill != null else "无"))
		print("")
	
	print("-".repeat(70))


# ========== 查询方法 ==========

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


## 获取所有存活角色的 ID 列表（用于 EventProcessor.process_post_event）
func get_alive_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor in get_all_actors():
		if not actor.is_dead():
			result.append(actor.get_id())
	return result


## 重写父类方法：移除 Actor 时清理格子占用和预订
## 框架层 GameplayInstance.remove_actor 不感知格子系统，
## 因此在 HexBattle 层补充清理逻辑。
func remove_actor(actor_id: String) -> bool:
	var actor := get_actor(actor_id)
	if actor != null and actor.hex_position.is_valid():
		# 清理该角色占据的格子
		grid.remove_occupant(actor.hex_position)
		# 清理该角色可能预订的格子（角色在移动途中被击杀时，目标格子仍有预订）
		for coord in _find_reservations_by(actor_id):
			grid.cancel_reservation(coord)
	return super.remove_actor(actor_id)


## 查找指定 actor 预订的所有格子
func _find_reservations_by(actor_id: String) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	for coord in grid.get_all_coords():
		if grid.get_reservation(coord) == actor_id:
			result.append(coord)
	return result


## 重写父类方法，返回类型收窄为 CharacterActor
func get_actor(actor_id: String) -> CharacterActor:
	return super.get_actor(actor_id) as CharacterActor


func get_ability_set_for_actor(actor_id: String) -> BattleAbilitySet:
	var actor := get_actor(actor_id)
	if actor != null:
		return actor.ability_set
	return null


# ========== 战斗主循环 ==========

func tick(dt: float) -> void:
	base_tick(dt)
	
	if _ended:
		return
	
	tick_count += 1
	
	if _logging_enabled and logger != null:
		logger.tick(tick_count, _logic_time)
	
	# 处理投射物命中事件（在 base_tick 中 ProjectileSystem 已经更新）
	_process_projectile_events()
	
	# ATB 与技能执行互斥：施法期间 ATB 冻结，不继续充能（经典 ATB 模式）。
	# 若需支持"施法不打断 ATB 累积"等变体，可将此逻辑抽取为独立的 ATBSystem。
	for actor in get_alive_actors():
		actor.ability_set.tick(dt, _logic_time)
		
		if _is_actor_executing(actor):
			actor.ability_set.tick_executions(dt)
		else:
			actor.accumulate_atb(dt)
			
			if actor.can_act():
				_start_actor_action(actor)
	
	var frame_events := GameWorld.event_collector.flush()
	if _recording_enabled and recorder != null:
		recorder.record_frame(tick_count, frame_events)
	
	if tick_count >= MAX_TICKS:
		print("\n战斗结束（达到安全上限 %d 帧，可能存在死循环）" % MAX_TICKS)
		_end("timeout")
	elif _check_battle_end():
		pass  # _check_battle_end 内部会调用 _end


func _is_actor_executing(actor: CharacterActor) -> bool:
	for ability in actor.ability_set.get_abilities():
		if ability.get_executing_instances().size() > 0:
			return true
	return false


## 处理投射物事件（命中/未命中）
## 将投射物事件广播给所有存活 Actor 的 Ability 系统
func _process_projectile_events() -> void:
	# 使用 collect() 获取事件副本（不清空，flush 在帧结束时调用）
	var events := GameWorld.event_collector.collect()
	var alive_actor_ids := get_alive_actor_ids()
	
	for event in events:
		var kind: String = event.get("kind", "")
		if kind == ProjectileEvents.PROJECTILE_HIT_EVENT:
			# 投射物命中：广播给所有存活 Actor
			print("  [投射物] 命中事件: %s -> %s" % [
				event.get("source_actor_id", "unknown"),
				event.get("target_actor_id", "unknown")
			])
			GameWorld.event_processor.process_post_event(event, alive_actor_ids, self)
		elif kind == ProjectileEvents.PROJECTILE_MISS_EVENT:
			# 投射物未命中：也广播（可能有被动响应）
			print("  [投射物] 未命中事件: %s (原因: %s)" % [
				event.get("source_actor_id", "unknown"),
				event.get("reason", "unknown")
			])
			GameWorld.event_processor.process_post_event(event, alive_actor_ids, self)


func _start_actor_action(actor: CharacterActor) -> void:
	print("\n[Tick %d] %s 准备行动 (ATB: %.1f)" % [tick_count, actor.get_display_name(), actor.get_atb_gauge()])
	
	if _logging_enabled and logger != null:
		logger.actor_ready(actor.get_id(), actor.get_display_name(), actor.get_atb_gauge())
	
	var decision := _decide_action(actor)
	
	if decision["type"] == "skip":
		print("  %s 无法行动，跳过本次决策" % actor.get_display_name())
		if _logging_enabled and logger != null:
			logger.ai_decision(actor.get_id(), actor.get_display_name(), "跳过（无可用行动）")
		actor.reset_atb()
		return
	
	var decision_text := ""
	if decision["type"] == "move":
		var coord: HexCoord = decision["target_coord"] as HexCoord
		decision_text = "移动到 (%d, %d)" % [coord.q, coord.r]
	else:
		var target_id: String = decision.get("target_actor_id", "")
		var target_actor := get_actor(target_id)
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
		decision.get("target_coord", null)
	)
	
	actor.ability_set.receive_event(event, self)
	actor.reset_atb()


## 判断 actor 能否对 target 使用 skill
## 检查：目标存活、阵营匹配（enemy/ally tag）、施法距离
func can_use_skill_on(actor: CharacterActor, skill: Ability, target: CharacterActor) -> bool:
	# 目标必须存活
	if target.is_dead():
		return false
	
	# 阵营检查
	var same_team := actor.get_team_id() == target.get_team_id()
	if skill.has_ability_tag("enemy") and same_team:
		return false
	if skill.has_ability_tag("ally") and not same_team:
		return false
	
	# ally 技能不能对自己使用
	if skill.has_ability_tag("ally") and actor.get_id() == target.get_id():
		return false
	
	# 距离检查
	var skill_range := skill.get_meta_int(HexBattleSkillMetaKeys.RANGE, 1)
	var distance := actor.hex_position.distance_to(target.hex_position)
	if distance > skill_range:
		return false
	
	return true


## AI 决策：委托给 actor 的 AI 策略对象
##
## 并发安全说明：不会出现两个单位计划移动到同一格子的情况。
## tick() 中 for actor in get_alive_actors() 是顺序遍历，_start_actor_action 是同步执行的。
## receive_event → ActivateInstanceComponent.on_event → activate_new_execution_instance
## → instance.tick(0) 会在同步调用链中立即触发 START tag 上的 StartMoveAction，
## 该 Action 执行 grid.reserve_tile() 完成预订。
## 因此后续 actor 决策时 is_reserved(n) 已能检测到先前的预订。
## 注意：此安全性依赖 ATB 串行决策 + tick(0) 同步执行 START tag，
## 如果改为并行决策或异步执行，需要额外的并发保护。
func _decide_action(actor: CharacterActor) -> Dictionary:
	return actor.ai_strategy.decide(actor, self)


func _create_action_use_event(ability_instance_id: String, source_id: String, target_actor_id: String, target_coord: HexCoord) -> Dictionary:
	var event := {
		"kind": GameEvent.ABILITY_ACTIVATE_EVENT,
		"abilityInstanceId": ability_instance_id,
		"sourceId": source_id,
		"logicTime": _logic_time,  # 事件快照：记录事件发生时的逻辑时间
	}
	if target_actor_id != "":
		event["target_actor_id"] = target_actor_id
	if target_coord != null and target_coord is HexCoord:
		# 转换为 Dictionary 以便 JSON 序列化
		event["target_coord"] = target_coord.to_dict()
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
		_end("right_win")
		return true
	elif right_alive == 0:
		print("\n战斗结束: 左方胜利!")
		_end("left_win")
		return true
	
	return false


func _end(result: String = "") -> void:
	super.end()
	_ended = true
	print("\n========== HexBattle 结束 ==========")
	print("总帧数: %d" % tick_count)
	print("逻辑时间: %.1f ms" % _logic_time)
	
	if _logging_enabled and logger != null:
		logger.save()
	if _recording_enabled and recorder != null:
		_final_replay_data = recorder.stop_recording(result)
		_save_replay(_final_replay_data)


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


## 获取录像数据（用于外部访问）
## 战斗进行中返回当前录像，战斗结束后返回最终录像
func get_replay_data() -> Dictionary:
	# 战斗结束后，返回保存的最终录像数据
	if not _final_replay_data.is_empty():
		return _final_replay_data
	# 战斗进行中，返回当前录像（会停止录像）
	if recorder != null and recorder.get_is_recording():
		return recorder.stop_recording()
	return {}


## 获取日志目录
func get_log_dir() -> String:
	if logger != null:
		return logger.get_battle_dir()
	return ""
