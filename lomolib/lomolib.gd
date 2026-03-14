@tool
extends EditorPlugin


func _enable_plugin() -> void:
	# Add autoloads here.
	# 基础工具（其他模块依赖）
	add_autoload_singleton("Log", "res://addons/lomolib/utils/logger.gd")
	add_autoload_singleton("IdGenerator", "res://addons/lomolib/utils/id_generator.gd")
	# 功能模块
	add_autoload_singleton("WaitGroupManager", "res://addons/lomolib/wait_group/wait_group_manager.gd")
	add_autoload_singleton("ItemSystem", "res://addons/lomolib/inventoryKit/item_system.gd")


func _disable_plugin() -> void:
	# Remove autoloads here.
	remove_autoload_singleton("ItemSystem")
	remove_autoload_singleton("WaitGroupManager")
	remove_autoload_singleton("IdGenerator")
	remove_autoload_singleton("Log")


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	pass


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	pass
