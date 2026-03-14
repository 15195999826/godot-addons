extends Node

## 全局日志管理器
## 提供日志级别控制和开关功能
## AutoLoad 名称: Log

## 开发模式：显示所有日志（包括 DEBUG）
## Log.set_debug_mode()

## 生产模式：只显示警告和错误
## Log.set_production_mode()

## 手动设置级别
## Log.set_level(Log.LogLevel.INFO)  # 过滤掉 DEBUG 日志

## 完全关闭日志（性能测试时）
## Log.set_enabled(false)

enum LogLevel {
	DEBUG = 0,    # 调试信息（最详细）
	INFO = 1,     # 一般信息
	WARNING = 2,  # 警告
	ERROR = 3,    # 错误
	NONE = 4      # 禁用所有日志
}

# 当前日志级别（可以在运行时修改）
var current_level: LogLevel = LogLevel.DEBUG

# 是否启用日志（一键开关）
var enabled: bool = true

# 是否显示时间戳
var show_timestamp: bool = true

# 是否显示帧号
var show_frame: bool = true

# 是否显示堆栈跟踪（WARNING 和 ERROR）
var show_stack: bool = true

func _ready() -> void:
	print("[Logger] ✓ 日志系统初始化完成 (级别: %s)" % LogLevel.keys()[current_level])

## 调试日志 - 最详细
func debug(module: String, message: String) -> void:
	_log(LogLevel.DEBUG, module, message, false)

## 信息日志 - 正常流程
func info(module: String, message: String) -> void:
	_log(LogLevel.INFO, module, message, false)

## 警告日志 - 潜在问题
func warning(module: String, message: String) -> void:
	_log(LogLevel.WARNING, module, message, show_stack)

## 错误日志 - 严重问题
func error(module: String, message: String) -> void:
	_log(LogLevel.ERROR, module, message, show_stack)

## 致命断言 - 条件不满足时终止程序
## Debug 模式：走原生 assert 中断
## Release 模式：写入 crash.log + OS.crash() 强制终止
func assert_crash(condition: bool, module: String, message: String) -> void:
	if condition:
		return
	var msg := "[%s] FATAL: %s" % [module, message]
	# Debug 模式：原生 assert 中断，不会执行后续代码
	assert(false, msg)
	# --- 以下仅 Release 模式执行 ---
	error(module, "FATAL: " + message)
	_flush_crash_log(msg)
	OS.crash(msg)

## 将崩溃信息写入 user://crash.log（OS.crash 前调用，确保日志持久化）
func _flush_crash_log(message: String) -> void:
	var file := FileAccess.open("user://crash.log", FileAccess.WRITE)
	if file == null:
		return
	var time := Time.get_datetime_string_from_system()
	file.store_line("[%s] %s" % [time, message])
	file.flush()
	file.close()

## 内部日志处理
func _log(level: LogLevel, module: String, message: String, with_stack: bool) -> void:
	# 日志开关检查
	if not enabled:
		return

	# 日志级别过滤
	if level < current_level:
		return

	# 构建日志消息
	var log_msg = ""

	# 添加时间戳
	if show_timestamp:
		var time = Time.get_time_dict_from_system()
		log_msg += "[%02d:%02d:%02d] " % [time.hour, time.minute, time.second]

	# 添加帧号
	if show_frame:
		log_msg += "[%d] " % Engine.get_process_frames()

	# 添加级别标识
	var level_prefix = ""
	match level:
		LogLevel.DEBUG:   level_prefix = "[DEBUG]"
		LogLevel.INFO:    level_prefix = "[INFO]"
		LogLevel.WARNING: level_prefix = "[WARN]"
		LogLevel.ERROR:   level_prefix = "[ERROR]"

	log_msg += level_prefix
	log_msg += "[%s] %s" % [module, message]

	# 输出日志
	match level:
		LogLevel.DEBUG, LogLevel.INFO:
			print(log_msg)
		LogLevel.WARNING:
			if with_stack:
				push_warning(log_msg)
			else:
				printerr(log_msg)  # 黄色输出但无堆栈
		LogLevel.ERROR:
			if with_stack:
				push_error(log_msg)
			else:
				printerr(log_msg)

## 设置日志级别
func set_level(level: LogLevel) -> void:
	current_level = level
	print("[Logger] 日志级别已设置为: ", LogLevel.keys()[level])

## 一键开关日志
func set_enabled(value: bool) -> void:
	enabled = value
	print("[Logger] 日志已", "启用" if value else "禁用")

## 快捷方法：只显示错误和警告
func set_production_mode() -> void:
	set_level(LogLevel.WARNING)
	show_timestamp = false
	print("[Logger] 生产模式已启用 (仅显示 WARNING 及以上)")

## 快捷方法：显示所有日志
func set_debug_mode() -> void:
	set_level(LogLevel.DEBUG)
	show_timestamp = true
	print("[Logger] 调试模式已启用 (显示所有日志)")
