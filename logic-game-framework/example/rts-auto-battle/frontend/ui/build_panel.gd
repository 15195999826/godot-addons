## RtsBuildPanel - 玩家建造面板
##
## 屏幕底部居中的 Control 容器, 列出所有 cost != {} 的 building_kind 作为按钮 (cost == {}
## 的 kind 视为不可玩家建造, 自动排除 — 例如 crystal_tower 起手 / 调方手放)。
##
## 用户点击 → emit `building_selected(kind: String)`, 调方接管 placement mode。
##
## 加新建筑 kind 时在 `_ALL_KINDS` 追加常量 (顺序 = HBox 左→右显示顺序)。
class_name RtsBuildPanel
extends Control


signal building_selected(kind: String)


const _ALL_KINDS: Array[String] = [
	RtsBuildingConfig.KIND_BARRACKS,
	RtsBuildingConfig.KIND_ARCHER_TOWER,
	RtsBuildingConfig.KIND_CRYSTAL_TOWER,
]

## 各 kind 的占位 icon 颜色; 缺失 → 灰色默认。后续可替换为 sprite 资源后此 dict 退役。
const _ICON_COLORS: Dictionary[String, Color] = {
	RtsBuildingConfig.KIND_BARRACKS: Color(0.85, 0.45, 0.20, 1.0),
	RtsBuildingConfig.KIND_ARCHER_TOWER: Color(0.30, 0.65, 0.90, 1.0),
}

const _ICON_SIZE: Vector2 = Vector2(18.0, 18.0)
const _BUTTON_MIN_SIZE: Vector2 = Vector2(150.0, 40.0)


func _ready() -> void:
	var hbox := HBoxContainer.new()
	hbox.name = "Buttons"
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	for kind in _ALL_KINDS:
		var stats := RtsBuildingConfig.get_stats(kind)
		if stats.cost.is_empty():
			continue
		hbox.add_child(_make_button(kind, stats))


func _make_button(kind: String, stats: RtsBuildingConfig.StatBlock) -> Button:
	var btn := Button.new()
	btn.name = "Btn_%s" % kind
	btn.text = "  " + stats.name  # 前置空格给浮在按钮左侧的 icon 留位
	btn.tooltip_text = "Cost: %s" % _format_cost(stats.cost)
	btn.custom_minimum_size = _BUTTON_MIN_SIZE
	btn.pressed.connect(func() -> void: building_selected.emit(kind))

	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.color = _ICON_COLORS.get(kind, Color(0.6, 0.6, 0.6, 1.0))
	icon.custom_minimum_size = _ICON_SIZE
	icon.size = _ICON_SIZE
	icon.position = Vector2(8.0, (_BUTTON_MIN_SIZE.y - _ICON_SIZE.y) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡 button 点击 / hover
	btn.add_child(icon)

	return btn


## {"gold": 80, "wood": 50} → "gold 80, wood 50"
static func _format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for key in cost:
		parts.append("%s %d" % [key, int(cost[key])])
	return ", ".join(parts)
