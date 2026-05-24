## HexItemCatalog - Hex 示例物品 catalog
##
## 本轮(V1)用代码内静态数据,不引入 Resource / data table。
## 字段 = id / display_name / icon_key / max_stack / item_tags / equipable
class_name HexItemCatalog
extends ItemCatalog


## 内部 config map: config_id -> Dictionary
## 写一次 (在 _init), 之后只读;读取时返回 duplicate 避免外部 mutation 污染。
var _configs: Dictionary = {}


func _init() -> void:
	_configs[&"training_sword"] = {
		"id": &"training_sword",
		"display_name": "Training Sword",
		"icon_key": "sword",
		"max_stack": 1,
		"item_tags": [&"equipment"],
		"equipable": true,
	}
	_configs[&"frost_orb"] = {
		"id": &"frost_orb",
		"display_name": "Frost Orb",
		"icon_key": "orb",
		"max_stack": 1,
		"item_tags": [&"equipment"],
		"equipable": true,
	}
	_configs[&"minor_rune"] = {
		"id": &"minor_rune",
		"display_name": "Minor Rune",
		"icon_key": "rune",
		"max_stack": 9,
		"item_tags": [&"equipment", &"rune"],
		"equipable": true,
	}
	_configs[&"broken_stone"] = {
		"id": &"broken_stone",
		"display_name": "Broken Stone",
		"icon_key": "stone",
		"max_stack": 99,
		"item_tags": [&"material"],
		"equipable": false,
	}


func has_config(config_id: StringName) -> bool:
	return _configs.has(config_id)


func get_config(config_id: StringName) -> Dictionary:
	if not _configs.has(config_id):
		return {}
	# 返回 duplicate 避免 caller mutate 内部状态
	return (_configs[config_id] as Dictionary).duplicate()


func list_config_ids() -> Array[StringName]:
	var arr: Array[StringName] = []
	for k in _configs.keys():
		arr.append(k)
	return arr
