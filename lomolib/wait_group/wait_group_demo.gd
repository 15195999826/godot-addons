## WaitGroup 示例场景
## 演示 WaitGroup 的各种使用方式
extends Control

@onready var log_label: Label = $MarginContainer/VBoxContainer/LogLabel
@onready var button_container: VBoxContainer = $MarginContainer/VBoxContainer/ButtonContainer

var log_text: String = ""


func _ready() -> void:
	_setup_buttons()
	_add_log("WaitGroup 示例准备就绪")


func _setup_buttons() -> void:
	_create_button("示例1：基本用法 (await)", _example_basic_await)
	_create_button("示例2：链式回调 (next)", _example_next_callback)
	_create_button("示例3：动态任务数量", _example_dynamic_tasks)
	_create_button("示例4：游戏初始化模拟", _example_game_init)
	_create_button("清空日志", _clear_log)


func _create_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	button_container.add_child(button)


func _add_log(message: String) -> void:
	var time_str := Time.get_time_string_from_system()
	log_text += "[%s] %s\n" % [time_str, message]
	log_label.text = log_text


func _clear_log() -> void:
	log_text = ""
	log_label.text = ""


## ============================================
## 示例 1: 基本用法 (await)
## ============================================
func _example_basic_await() -> void:
	_add_log("=== 示例1：基本用法 (await) ===")

	var result = WaitGroupManager.create_wait_group(&"Example1")
	var wg: LomoWaitGroup = result[1]

	# 添加 3 个任务
	wg.add(3)

	_add_log("开始执行 3 个异步任务...")

	_task_async(1, 1.0, wg)
	_task_async(2, 0.5, wg)
	_task_async(3, 1.5, wg)

	# 等待所有任务完成
	await wg.wait()

	_add_log("✅ 所有任务完成！\n")


func _task_async(task_id: int, delay: float, wg: LomoWaitGroup) -> void:
	await get_tree().create_timer(delay).timeout
	_add_log("  - 任务 %d 完成 (延迟 %.1fs)" % [task_id, delay])
	wg.done(&"Task_%d" % task_id)


## ============================================
## 示例 2: 链式回调 (next)
## ============================================
func _example_next_callback() -> void:
	_add_log("=== 示例2：链式回调 (next) ===")

	var result = WaitGroupManager.create_wait_group(&"Example2")
	var wg: LomoWaitGroup = result[1]

	wg.add(4)

	_add_log("开始执行 4 个任务...")

	for i in range(4):
		_task_with_random_delay(i + 1, wg)

	# 完成后执行回调
	wg.next(func():
		_add_log("✅ 所有任务完成！执行回调")
		_add_log("🎉 开始后续处理...\n")
	)


func _task_with_random_delay(task_id: int, wg: LomoWaitGroup) -> void:
	var delay := randf_range(0.3, 1.2)
	await get_tree().create_timer(delay).timeout
	_add_log("  - 任务 %d 完成 (随机延迟 %.2fs)" % [task_id, delay])
	wg.done(&"RandomTask_%d" % task_id)


## ============================================
## 示例 3: 动态任务数量
## ============================================
func _example_dynamic_tasks() -> void:
	_add_log("=== 示例3：动态任务数量 ===")

	var task_count := randi_range(3, 6)
	_add_log("随机生成 %d 个任务..." % task_count)

	var result = WaitGroupManager.create_wait_group(&"Example3")
	var wg: LomoWaitGroup = result[1]

	# 动态设置任务数量
	wg.add(task_count)

	for i in range(task_count):
		_download_file_simulation(i + 1, wg)

	await wg.wait()

	_add_log("✅ 所有文件下载完成！\n")


func _download_file_simulation(file_id: int, wg: LomoWaitGroup) -> void:
	var delay := randf_range(0.5, 1.5)
	await get_tree().create_timer(delay).timeout
	_add_log("  - 文件 %d 下载完成" % file_id)
	wg.done(&"File_%d" % file_id)


## ============================================
## 示例 4: 游戏初始化模拟
## ============================================
func _example_game_init() -> void:
	_add_log("=== 示例4：游戏初始化模拟 ===")

	var result = WaitGroupManager.create_wait_group(&"GameInit")
	var wg: LomoWaitGroup = result[1]

	wg.add(5)

	_add_log("开始初始化游戏系统...")

	_init_system("音频系统", 0.8, wg)
	_init_system("存档系统", 1.2, wg)
	_init_system("网络系统", 1.5, wg)
	_init_system("UI 系统", 0.6, wg)
	_init_system("资源系统", 1.0, wg)

	await wg.wait()

	_add_log("✅ 游戏初始化完成！")
	_add_log("🎮 开始游戏...\n")


func _init_system(system_name: String, delay: float, wg: LomoWaitGroup) -> void:
	_add_log("  - 正在初始化：%s..." % system_name)
	await get_tree().create_timer(delay).timeout
	_add_log("  ✓ %s 初始化完成" % system_name)
	wg.done(&"Init_%s" % system_name)
