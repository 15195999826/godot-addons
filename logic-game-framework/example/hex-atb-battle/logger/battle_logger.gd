## BattleLogger - 战斗日志管理器
##
## 支持多种输出格式：
## - 控制台：角色名+技能名标识
## - 文件：console.log, summary.log, 角色视角日志
##
## 日志文件结构：
## Logs/
## ├── battle_2026-01-03_153000/
## │   ├── console.log       # 控制台格式
## │   ├── summary.log       # 执行摘要
## │   └── actors/
## │       ├── 牧师.log
## │       └── ...
class_name HexBattleLogger
extends RefCounted


# ========== 类型定义 ==========

## 执行实例信息
class ExecutionInfo:
	var execution_id: String
	var actor_id: String
	var actor_name: String
	var ability_name: String
	var config_id: String
	var start_time: float
	var end_time: float = -1.0
	var triggered_tags: Array[Dictionary] = []  # { tag: String, time: float, actions: Array }
	var status: String = "executing"  # executing, completed, cancelled


# ========== 配置 ==========

## 是否输出到控制台
var console_enabled: bool = true

## 是否输出到文件
var file_enabled: bool = true

## 日志根目录
var log_dir: String = "user://Logs"

## 最大保留战斗日志数
var max_battle_logs: int = 10


# ========== 状态 ==========

var _battle_id: String
var _battle_dir: String = ""

## 控制台日志缓冲
var _console_buffer: Array[String] = []

## 执行实例追踪
var _executions: Dictionary = {}  # execution_id -> ExecutionInfo

## 角色日志缓冲
var _actor_logs: Dictionary = {}  # "actor_id|actor_name" -> Array[String]

## 当前帧信息
var _current_tick: int = 0
var _current_time: float = 0.0

## Actor ID -> 名称映射
var _actor_names: Dictionary = {}


# ========== 初始化 ==========

func _init(battle_id: String, config: Dictionary = {}) -> void:
	_battle_id = battle_id
	console_enabled = config.get("console", true)
	file_enabled = config.get("file", true)
	log_dir = config.get("log_dir", "user://Logs")
	max_battle_logs = config.get("max_battle_logs", 10)
	
	if file_enabled:
		_init_log_dir()


func _init_log_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("[BattleLogger] Cannot open user:// directory")
		return
	
	if not dir.dir_exists(log_dir.replace("user://", "")):
		dir.make_dir_recursive(log_dir.replace("user://", ""))
	
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_battle_dir = log_dir + "/battle_" + timestamp + "_" + _battle_id
	
	dir = DirAccess.open(log_dir)
	if dir != null:
		dir.make_dir(_battle_dir.get_file())
		dir.make_dir(_battle_dir.get_file() + "/actors")
	_clean_old_logs()


func _clean_old_logs() -> void:
	var dir := DirAccess.open(log_dir)
	if dir == null:
		return
	
	var battle_dirs: Array[Dictionary] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and file_name.begins_with("battle_"):
			battle_dirs.append({
				"name": file_name,
				"path": log_dir + "/" + file_name,
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	
	battle_dirs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] > b["name"])
	if battle_dirs.size() > max_battle_logs:
		for i in range(max_battle_logs, battle_dirs.size()):
			var old_dir: String = battle_dirs[i]["path"]
			_remove_dir_recursive(old_dir)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path := path + "/" + file_name
			if dir.current_is_dir():
				_remove_dir_recursive(full_path)
			else:
				dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


# ========== 角色注册 ==========

## 注册角色（用于 ID -> 名称映射）
func register_actor(actor_id: String, actor_name: String) -> void:
	_actor_names[actor_id] = actor_name


## 获取角色名称
func get_actor_name(actor_id: String) -> String:
	return _actor_names.get(actor_id, actor_id)


# ========== 帧控制 ==========

## 开始新的一帧
func tick(tick_count: int, logic_time: float) -> void:
	_current_tick = tick_count
	_current_time = logic_time
	
	var line := "\n--- Tick %d | %.0fms ---" % [tick_count, logic_time]
	_write_console(line)


# ========== 执行实例日志 ==========

## 记录执行开始
func execution_start(
	execution_id: String,
	actor_id: String,
	actor_name: String,
	ability_name: String,
	config_id: String
) -> void:
	var info := ExecutionInfo.new()
	info.execution_id = execution_id
	info.actor_id = actor_id
	info.actor_name = actor_name
	info.ability_name = ability_name
	info.config_id = config_id
	info.start_time = _current_time
	info.status = "executing"
	
	_executions[execution_id] = info
	
	var label := "%s:%s" % [actor_name, ability_name]
	_write_console("[execution] [%s] 开始执行" % label)
	_write_actor_log(actor_id, actor_name, "[%.0fms] 开始执行 [%s]" % [_current_time, ability_name])


## 记录 Tag 触发
func tag_triggered(execution_id: String, tag_name: String, tag_time: float, actions: Array[String]) -> void:
	var info: ExecutionInfo = _executions.get(execution_id)
	if info == null:
		return
	
	info.triggered_tags.append({
		"tag": tag_name,
		"time": tag_time,
		"actions": actions,
	})
	
	var label := "%s:%s" % [info.actor_name, info.ability_name]
	var actions_str := " → " + ", ".join(actions) if actions.size() > 0 else ""
	_write_console("[timeline] [%s] 触发 %s @%.0fms%s" % [label, tag_name, tag_time, actions_str])
	_write_actor_log(info.actor_id, info.actor_name, "  └─ %s @%.0fms%s" % [tag_name, tag_time, actions_str])


## 记录执行完成
func execution_complete(execution_id: String, elapsed: float) -> void:
	var info: ExecutionInfo = _executions.get(execution_id)
	if info == null:
		return
	
	info.end_time = _current_time
	info.status = "completed"
	
	var label := "%s:%s" % [info.actor_name, info.ability_name]
	_write_console("[execution] [%s] 完成 | %.0fms" % [label, elapsed])
	_write_actor_log(info.actor_id, info.actor_name, "[%.0fms] [%s] 完成 | %.0fms" % [_current_time, info.ability_name, elapsed])


## 记录执行取消
func execution_cancel(execution_id: String, elapsed: float) -> void:
	var info: ExecutionInfo = _executions.get(execution_id)
	if info == null:
		return
	
	info.end_time = _current_time
	info.status = "cancelled"
	
	var label := "%s:%s" % [info.actor_name, info.ability_name]
	_write_console("[execution] [%s] 取消 @%.0fms" % [label, elapsed])
	_write_actor_log(info.actor_id, info.actor_name, "[%.0fms] [%s] 取消 @%.0fms" % [_current_time, info.ability_name, elapsed])


# ========== 通用日志 ==========

## 记录角色获得行动机会
func actor_ready(actor_id: String, actor_name: String, atb: float) -> void:
	_write_console("\n⚡ %s 获得行动机会 (ATB: %.1f)" % [actor_name, atb])
	_write_actor_log(actor_id, actor_name, "[%.0fms] 获得行动机会 (ATB: %.1f)" % [_current_time, atb])


## 记录 AI 决策
func ai_decision(actor_id: String, actor_name: String, decision: String) -> void:
	_write_console("  🤖 决策: %s" % decision)
	_write_actor_log(actor_id, actor_name, "  └─ 决策: %s" % decision)


## 记录伤害
func damage_dealt(
	source_id: String,
	target_id: String,
	damage: float,
	damage_type: String,
	is_reflected: bool = false
) -> void:
	var source_name := get_actor_name(source_id)
	var target_name := get_actor_name(target_id)
	var reflect_text := " (反伤)" if is_reflected else ""
	
	_write_console("  💥 [伤害] %s → %s | %.0f %s%s" % [source_name, target_name, damage, damage_type, reflect_text])
	_write_actor_log(source_id, source_name, "[%.0fms] 对 %s 造成 %.0f %s 伤害%s" % [_current_time, target_name, damage, damage_type, reflect_text])
	_write_actor_log(target_id, target_name, "[%.0fms] 受到 %s 的 %.0f %s 伤害%s" % [_current_time, source_name, damage, damage_type, reflect_text])


## 记录治疗
func heal_applied(source_id: String, target_id: String, heal_amount: float) -> void:
	var source_name := get_actor_name(source_id)
	var target_name := get_actor_name(target_id)
	
	_write_console("  💚 [治疗] %s → %s | %.0f HP" % [source_name, target_name, heal_amount])
	_write_actor_log(source_id, source_name, "[%.0fms] 治疗 %s %.0f HP" % [_current_time, target_name, heal_amount])
	_write_actor_log(target_id, target_name, "[%.0fms] 被 %s 治疗 %.0f HP" % [_current_time, source_name, heal_amount])


## 记录死亡
func actor_died(actor_id: String, killer_id: String = "") -> void:
	var actor_name := get_actor_name(actor_id)
	var killer_text := ""
	if killer_id != "":
		killer_text = " (击杀者: %s)" % get_actor_name(killer_id)
	
	_write_console("  ☠️ [死亡] %s 阵亡%s" % [actor_name, killer_text])
	_write_actor_log(actor_id, actor_name, "[%.0fms] ☠️ 阵亡%s" % [_current_time, killer_text])


## 记录自定义日志
func log_message(message: String, actor_id: String = "", actor_name: String = "") -> void:
	_write_console(message)
	if actor_id != "" and actor_name != "":
		_write_actor_log(actor_id, actor_name, "[%.0fms] %s" % [_current_time, message])


# ========== 输出方法 ==========

func _write_console(line: String) -> void:
	_console_buffer.append(line)
	if console_enabled:
		print(line)


func _write_actor_log(actor_id: String, actor_name: String, line: String) -> void:
	var key := "%s|%s" % [actor_id, actor_name]
	if not _actor_logs.has(key):
		_actor_logs[key] = ["=== %s (%s) 战斗日志 ===\n" % [actor_name, actor_id]]
	_actor_logs[key].append(line)


# ========== 保存日志 ==========

## 战斗结束时调用，保存所有日志
func save() -> void:
	if not file_enabled or _battle_dir == "":
		return
	
	var console_file := FileAccess.open(_battle_dir + "/console.log", FileAccess.WRITE)
	if console_file != null:
		console_file.store_string("\n".join(_console_buffer))
		console_file.close()
	
	_save_summary()
	
	for key in _actor_logs:
		var parts: PackedStringArray = key.split("|")
		var actor_name: String = parts[1] if parts.size() > 1 else key
		var file_name := actor_name + ".log"
		var actor_file := FileAccess.open(_battle_dir + "/actors/" + file_name, FileAccess.WRITE)
		if actor_file != null:
			actor_file.store_string("\n".join(_actor_logs[key]))
			actor_file.close()
	
	print("\n📁 日志已保存到: %s" % _battle_dir)


func _save_summary() -> void:
	var lines: Array[String] = [
		"=== 战斗执行摘要 ===",
		"战斗 ID: %s" % _battle_id,
		"总时长: %.0fms" % _current_time,
		"总帧数: %d" % _current_tick,
		"",
		"=== 执行实例列表 ===",
	]
	
	var by_actor: Dictionary = {}
	for execution_id in _executions:
		var info: ExecutionInfo = _executions[execution_id]
		var key := info.actor_name
		if not by_actor.has(key):
			by_actor[key] = []
		by_actor[key].append(info)
	
	for actor_name in by_actor:
		lines.append("\n【%s】" % actor_name)
		for info in by_actor[actor_name]:
			var duration: String = "%.0f" % (info.end_time - info.start_time) if info.end_time >= 0 else "?"
			var tags_arr: Array[String] = []
			for t in info.triggered_tags:
				tags_arr.append("%s@%.0f" % [t["tag"], t["time"]])
			var tags := ", ".join(tags_arr)
			var status_icon := "✓" if info.status == "completed" else ("✗" if info.status == "cancelled" else "...")
			var end_time_str := "%.0f" % info.end_time if info.end_time >= 0 else "?"
			lines.append("  %s [%s] %.0fms → %sms (%sms)" % [status_icon, info.ability_name, info.start_time, end_time_str, duration])
			if tags != "":
				lines.append("    触发: %s" % tags)
	
	var summary_file := FileAccess.open(_battle_dir + "/summary.log", FileAccess.WRITE)
	if summary_file != null:
		summary_file.store_string("\n".join(lines))
		summary_file.close()


## 获取日志目录路径
func get_battle_dir() -> String:
	return _battle_dir


## 获取控制台缓冲
func get_console_buffer() -> Array[String]:
	return _console_buffer.duplicate()
