## HpBarView - 血条子组件
##
## UnitView 的 attached visual 之一,响应 update_from_state 同步血量比例 + 颜色。
##
## 实现保留旧 BoxMesh 简化方案(从 UnitView 搬过来,不改视觉行为);后续若要升级
## 成 SubViewport+ProgressBar 在此处独立迭代,不再触动 UnitView。
class_name FrontendHpBarView
extends Node3D


@export var hp_bar_offset: float = 1.2


var _hp_bar_mesh: MeshInstance3D
var _hp_material: StandardMaterial3D
var _max_hp: float = 100.0
var _current_hp: float = 0.0


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
	_apply()


func update_from_state(state: FrontendActorRenderState) -> void:
	_max_hp = state.max_hp
	_current_hp = state.visual_hp
	_apply()


## 由 UnitView.set_environment_style 触发,环境单位不显示血条。
func set_hidden(hidden: bool) -> void:
	if _hp_bar_mesh != null:
		_hp_bar_mesh.visible = not hidden


## 给 ShieldBarView 等需要"和血条同宽对齐"的子 view 用。
## 当前血条宽度硬编码 1.0(BoxMesh 边长),沿用旧实现。
func get_bar_width() -> float:
	return 1.0


func get_bar_offset() -> float:
	return hp_bar_offset


func _apply() -> void:
	if _hp_bar_mesh == null:
		return
	var ratio := _current_hp / _max_hp if _max_hp > 0 else 0.0
	_hp_bar_mesh.scale.x = maxf(0.01, ratio)
	if _hp_material != null:
		if ratio > 0.5:
			_hp_material.albedo_color = Color.GREEN
		elif ratio > 0.25:
			_hp_material.albedo_color = Color.YELLOW
		else:
			_hp_material.albedo_color = Color.RED
