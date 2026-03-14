@tool
extends EditorPlugin


const AUTOLOAD_NAME := "UGridMap"
const AUTOLOAD_PATH := "res://addons/ultra-grid-map/u_grid_map.gd"


func _enter_tree() -> void:
	_ensure_autoload()


func _exit_tree() -> void:
	_remove_autoload()


func _ensure_autoload() -> void:
	var key := "autoload/%s" % AUTOLOAD_NAME
	if ProjectSettings.has_setting(key):
		return
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _remove_autoload() -> void:
	var key := "autoload/%s" % AUTOLOAD_NAME
	if not ProjectSettings.has_setting(key):
		return
	var current_path: String = ProjectSettings.get_setting(key)
	# 只移除我们自己添加的 autoload
	if current_path == "*" + AUTOLOAD_PATH:
		remove_autoload_singleton(AUTOLOAD_NAME)
