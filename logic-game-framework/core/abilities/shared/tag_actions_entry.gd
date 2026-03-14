## Tag → Actions 映射条目
##
## 将一个 Timeline Tag（支持通配符如 "hit*"）映射到一组 Action。
## 无状态，所有角色共享同一实例。
class_name TagActionsEntry
extends RefCounted


## Tag 名称（支持通配符，如 "hit*"）
var _tag: String

## 预类型化的 Action 列表
var _cached_actions: Array[Action.BaseAction]


func _init(tag: String, actions: Array[Action.BaseAction]) -> void:
	_tag = tag
	_cached_actions = actions


func get_tag() -> String:
	return _tag


func get_actions() -> Array[Action.BaseAction]:
	return _cached_actions


## 精确匹配 + 通配符匹配
func matches(tag_name: String) -> bool:
	if _tag == tag_name:
		return true
	if _tag.ends_with("*"):
		return tag_name.begins_with(_tag.substr(0, _tag.length() - 1))
	return false


## Debug: 冻结所有 Action，用于检测无状态约束
func freeze_actions() -> void:
	for action in _cached_actions:
		action._freeze()
