## NameLabelView - 名字标签子组件
##
## UnitView 的 attached visual 之一,显示 actor 的 display_name(或 environment 单位
## 的 override 名,如 "StoneWall")。
class_name FrontendNameLabelView
extends Node3D


@export var name_label_offset: float = 1.5


var _name_label: Label3D
## set_override_text 设置后,update_from_state 不再覆盖(environment 单位优先)。
var _override_text: String = ""


func _ready() -> void:
	_name_label = Label3D.new()
	_name_label.position = Vector3(0.0, name_label_offset, 0.0)
	_name_label.pixel_size = 0.01
	_name_label.font_size = 32
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.modulate = Color.WHITE
	add_child(_name_label)


func update_from_state(state: FrontendActorRenderState) -> void:
	if not _override_text.is_empty():
		return
	if _name_label != null:
		_name_label.text = state.display_name


func set_override_text(text: String) -> void:
	_override_text = text
	if _name_label != null:
		_name_label.text = text
