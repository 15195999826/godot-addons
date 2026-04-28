## HpBarView - 血条子组件
##
## UnitView 的 attached visual,响应 update_from_state 同步血量比例 + 颜色。
class_name FrontendHpBarView
extends Node3D


@export var hp_bar_offset: float = 1.2


var _hp_bar_mesh: MeshInstance3D
var _hp_material: StandardMaterial3D


func _ready() -> void:
	_hp_bar_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.1, 0.1)
	_hp_bar_mesh.mesh = box
	_hp_bar_mesh.position = Vector3(0.0, hp_bar_offset, 0.0)
	_hp_material = StandardMaterial3D.new()
	_hp_material.albedo_color = Color.GREEN
	_hp_bar_mesh.material_override = _hp_material
	_hp_bar_mesh.name = "HPBar"
	add_child(_hp_bar_mesh)


func update_from_state(state: FrontendActorRenderState) -> void:
	if _hp_bar_mesh == null:
		return
	var ratio := state.visual_hp / state.max_hp if state.max_hp > 0 else 0.0
	_hp_bar_mesh.scale.x = maxf(0.01, ratio)
	if _hp_material != null:
		if ratio > 0.5:
			_hp_material.albedo_color = Color.GREEN
		elif ratio > 0.25:
			_hp_material.albedo_color = Color.YELLOW
		else:
			_hp_material.albedo_color = Color.RED


## 由 UnitView.set_environment_style 触发,环境单位不显示血条。
func set_hidden(hidden: bool) -> void:
	if _hp_bar_mesh != null:
		_hp_bar_mesh.visible = not hidden
