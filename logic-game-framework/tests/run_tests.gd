class_name RunTests
extends Node
## 测试运行器
##
## 使用方法（必须通过场景运行，不能直接运行脚本）：
## @example
## ```bash
## # ✅ 正确：通过场景运行
## godot --headless addons/logic-game-framework/tests/run_tests.tscn
##
## # ❌ 错误：直接运行脚本会报错 "doesn't inherit from SceneTree or MainLoop"
## godot --headless --script addons/logic-game-framework/tests/run_tests.gd
## ```

# 测试文件路径
const TEST_PATHS := [
	"res://addons/logic-game-framework/tests/core/attributes/attribute_set_test.gd",
	"res://addons/logic-game-framework/tests/core/attributes/define_attributes_test.gd",
	"res://addons/logic-game-framework/tests/core/events/event_processor_test.gd",
	"res://addons/logic-game-framework/tests/core/events/pre_event_component_test.gd",
	"res://addons/logic-game-framework/tests/core/abilities/ability_test.gd",
	"res://addons/logic-game-framework/tests/core/abilities/ability_execution_instance_test.gd",
	"res://addons/logic-game-framework/tests/core/abilities/activate_instance_component_test.gd",
	"res://addons/logic-game-framework/tests/core/actions/tag_action_test.gd",
	"res://addons/logic-game-framework/tests/core/resolvers/resolvers_test.gd",
	"res://addons/logic-game-framework/tests/core/timeline/timeline_test.gd",
	"res://addons/logic-game-framework/tests/core/timeline/timeline_loop_test.gd",
]

# 测试框架实例
var _test_framework: TestFramework

func _ready() -> void:
	# 初始化测试框架并添加到场景树（触发 _enter_tree 设置 meta）
	_test_framework = load("res://addons/logic-game-framework/tests/test_framework.gd").new()
	add_child(_test_framework)

	# 加载所有测试脚本
	_load_test_scripts()

	# 运行所有测试
	var failures: int = _test_framework.run()

	# 退出并返回失败数
	get_tree().quit(failures)

func _load_test_scripts() -> void:
	for test_path in TEST_PATHS:
		var script: GDScript = load(test_path) as GDScript
		if script == null:
			push_error("Failed to load test script: %s" % test_path)
			continue
		var _test_instance: Node = script.new()

## 自动发现测试

func discover_tests() -> Array[String]:
	var test_paths: Array[String] = []
	var dir: DirAccess = DirAccess.open("res://addons/logic-game-framework/tests/")
	if not dir:
		push_error("Failed to open tests directory")
		return test_paths

	_collect_test_files_recursive(dir, "res://addons/logic-game-framework/tests/", test_paths)
	return test_paths

func _collect_test_files_recursive(dir: DirAccess, base_path: String, paths: Array[String]) -> void:
	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := base_path + file_name

		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				var sub_dir: DirAccess = DirAccess.open(full_path + "/")
				if sub_dir:
					_collect_test_files_recursive(sub_dir, full_path + "/", paths)
		else:
			if file_name.ends_with("_test.gd"):
				paths.append(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()
