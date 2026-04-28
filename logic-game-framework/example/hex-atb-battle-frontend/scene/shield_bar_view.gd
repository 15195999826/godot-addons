## ShieldBarView - 护盾条子组件
##
## UnitView 的 attached visual,显示在血条上方。响应 update_from_state 同步
## actor.shields 数组。
##
## V1 策略:
##   - 宽度 = HpBar 宽度,锚点对齐
##   - 填充比例 = sum(current) / sum(capacity)(多盾聚合)
##   - 颜色取 shields[0].color(Visualizer 已经把 ward 蓝色写进 summary)
##   - shields 为空时整条隐藏,避免空 bar 视觉噪音
##
## shields 数组保留 current/capacity/priority/color 多盾粒度,后续做"分段显示
## 按 LIFO 排序"或"按 ability_id 分色"时只改这个文件,不动 RenderState / 事件结构。
class_name FrontendShieldBarView
extends Node3D


@export var shield_bar_offset: float = 1.33


const BAR_WIDTH := 1.0
const BAR_HEIGHT := 0.08
const BAR_DEPTH := 0.1


var _bar_mesh: MeshInstance3D
var _bar_material: StandardMaterial3D


func _ready() -> void:
	_bar_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BAR_WIDTH, BAR_HEIGHT, BAR_DEPTH)
	_bar_mesh.mesh = box
	_bar_mesh.position = Vector3(0.0, shield_bar_offset, 0.0)
	_bar_material = StandardMaterial3D.new()
	_bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_mesh.material_override = _bar_material
	_bar_mesh.name = "ShieldBar"
	_bar_mesh.visible = false
	add_child(_bar_mesh)


func update_from_state(state: FrontendActorRenderState) -> void:
	_apply(state.shields)


func _apply(shields: Array) -> void:
	if _bar_mesh == null:
		return
	if shields.is_empty():
		_bar_mesh.visible = false
		return

	var sum_current := 0.0
	var sum_capacity := 0.0
	for s in shields:
		var summary: FrontendShieldSummary = s
		sum_current += summary.current
		sum_capacity += summary.capacity

	if sum_capacity <= 0.0 or sum_current <= 0.0:
		_bar_mesh.visible = false
		return

	var first: FrontendShieldSummary = shields[0]
	_bar_material.albedo_color = first.color
	_bar_mesh.scale.x = maxf(0.01, sum_current / sum_capacity)
	_bar_mesh.visible = true
