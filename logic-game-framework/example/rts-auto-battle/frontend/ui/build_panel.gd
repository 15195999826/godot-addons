## RtsBuildPanel - 玩家建造面板
##
## 屏幕底部居中的 Control 容器, 列出可建造的 building kind 按钮。
## 布局走 .tscn (节点树 + anchor 在编辑器拼好), script 只挂 signal + click handler。
##
## 加新建筑 kind: 在 .tscn 加 Btn_<Kind> + Icon 子节点, 在下方 _BUTTONS 表加 (button_path, kind) 映射。
class_name RtsBuildPanel
extends Control


signal building_selected(kind: String)


## (button NodePath, building_kind) 映射. button text + tooltip 在 _ready 从 RtsBuildingConfig 读.
const _BUTTONS: Array = [
	["Buttons/Btn_Barracks", RtsBuildingConfig.KIND_BARRACKS],
	["Buttons/Btn_ArcherTower", RtsBuildingConfig.KIND_ARCHER_TOWER],
]


func _ready() -> void:
	for entry in _BUTTONS:
		var path: String = entry[0]
		var kind: String = entry[1]
		var btn := get_node(path) as Button
		if btn == null:
			push_warning("[RtsBuildPanel] missing button at path: %s" % path)
			continue
		var stats := RtsBuildingConfig.get_stats(kind)
		btn.text = "  " + stats.name
		btn.tooltip_text = "Cost: %s" % _format_cost(stats.cost)
		# bind 局部 kind 防止闭包共享同一变量 (lambda 默认 capture by reference)
		var k := kind
		btn.pressed.connect(func() -> void: building_selected.emit(k))


## {"gold": 80, "wood": 50} → "gold 80, wood 50"
static func _format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for key in cost:
		parts.append("%s %d" % [key, int(cost[key])])
	return ", ".join(parts)
