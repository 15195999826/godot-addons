@tool
extends EditorPlugin

# ========== 依赖检查 ==========

## 依赖的插件列表
const DEPENDENCIES: Array[String] = ["ultra-grid-map", "lomolib"]

# ========== 常量 ==========

const MENU_NAME := "LGFramework"
const MENU_ITEM_GENERATE := 1
const MENU_ITEM_RUN_TEST := 2
const GENERATOR_SCRIPT := "res://addons/logic-game-framework/scripts/attribute_set_generator_script.gd"
const TEST_SCENE := "res://addons/logic-game-framework/example/hex-atb-battle/main.tscn"

# Log 和 IdGenerator 已移至 lomolib 插件
const AUTOLOAD_GAME_WORLD := "GameWorld"
const AUTOLOAD_GAME_WORLD_PATH := "res://addons/logic-game-framework/core/world/game_world.gd"
const AUTOLOAD_TIMELINE_REGISTRY := "TimelineRegistry"
const AUTOLOAD_TIMELINE_REGISTRY_PATH := "res://addons/logic-game-framework/core/timeline/timeline.gd"

var _menu: PopupMenu

func _enter_tree() -> void:
	if not _check_dependencies():
		return
	_register_autoloads()
	_menu = PopupMenu.new()
	_menu.add_item("生成属性集", MENU_ITEM_GENERATE)
	_menu.add_item("运行 HexATB 测试 (Headless)", MENU_ITEM_RUN_TEST)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_tool_submenu_item(MENU_NAME, _menu)

func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)
	if _menu:
		_menu.queue_free()
		_menu = null
	_unregister_autoloads()

func _on_menu_id_pressed(id: int) -> void:
	if id == MENU_ITEM_GENERATE:
		_run_attribute_set_generator()
	elif id == MENU_ITEM_RUN_TEST:
		_run_headless_test()

func _run_attribute_set_generator() -> void:
	var script: GDScript = load(GENERATOR_SCRIPT) as GDScript
	if script == null:
		push_error("Generator script not found: %s" % GENERATOR_SCRIPT)
		return
	var generator_instance: EditorScript = script.new()
	if generator_instance == null or not generator_instance.has_method("_run"):
		push_error("Generator script does not implement _run(): %s" % GENERATOR_SCRIPT)
		return
	generator_instance._run()


func _run_headless_test() -> void:
	var godot_path := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var scene_path := TEST_SCENE
	
	var args := PackedStringArray([
		"--headless",
		"--path", project_path,
		scene_path
	])
	
	print("[LGFramework] 启动 Headless 测试: %s %s" % [godot_path, " ".join(args)])
	OS.create_process(godot_path, args)

func _register_autoloads() -> void:
	# Log 和 IdGenerator 由 lomolib 插件提供
	_ensure_autoload(AUTOLOAD_GAME_WORLD, AUTOLOAD_GAME_WORLD_PATH)
	_ensure_autoload(AUTOLOAD_TIMELINE_REGISTRY, AUTOLOAD_TIMELINE_REGISTRY_PATH)

func _unregister_autoloads() -> void:
	_remove_autoload_if_matches(AUTOLOAD_GAME_WORLD, AUTOLOAD_GAME_WORLD_PATH)
	_remove_autoload_if_matches(AUTOLOAD_TIMELINE_REGISTRY, AUTOLOAD_TIMELINE_REGISTRY_PATH)

func _ensure_autoload(name: String, path: String) -> void:
	if ProjectSettings.has_setting("autoload/%s" % name):
		return
	add_autoload_singleton(name, path)

func _remove_autoload_if_matches(name: String, path: String) -> void:
	var key := "autoload/%s" % name
	if not ProjectSettings.has_setting(key):
		return
	if ProjectSettings.get_setting(key) != path:
		return
	remove_autoload_singleton(name)


# ========== 依赖检查 ==========

## 检查依赖插件是否已启用
## @return: true 如果所有依赖都已启用
func _check_dependencies() -> bool:
	var missing: Array[String] = []
	
	for dep: String in DEPENDENCIES:
		if not EditorInterface.is_plugin_enabled(dep):
			missing.append(dep)
	
	if not missing.is_empty():
		push_error("[LogicGameFramework] 缺少依赖插件: %s，请先在 Project Settings > Plugins 中启用它们" % ", ".join(missing))
		# 延迟禁用自己，避免在 _enter_tree 中直接调用
		call_deferred("_disable_self")
		return false
	
	return true


## 禁用自己
func _disable_self() -> void:
	EditorInterface.set_plugin_enabled("logic-game-framework", false)
