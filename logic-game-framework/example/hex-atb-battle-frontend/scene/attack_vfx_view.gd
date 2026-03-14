## AttackVFXView - 攻击特效 3D 视图组件
##
## 从攻击者位置飞向目标的箭头特效
class_name FrontendAttackVFXView
extends Node3D


# ========== 属性 ==========

## 特效 ID
var vfx_id: String

## 特效类型
var vfx_type: FrontendAttackVFXAction.AttackVFXType

## 特效颜色
var vfx_color: Color

## 攻击方向
var direction: Vector3

## 攻击距离
var distance: float

## 是否暴击
var is_critical: bool

## 起始位置
var start_position: Vector3

## 目标位置
var target_position: Vector3


# ========== 内部节点 ==========

var _arrow_mesh: MeshInstance3D
var _trail_mesh: MeshInstance3D
var _material: StandardMaterial3D
var _trail_material: StandardMaterial3D


# ========== 初始化 ==========

func initialize(
	p_vfx_id: String,
	p_vfx_type: FrontendAttackVFXAction.AttackVFXType,
	p_color: Color,
	p_direction: Vector3,
	p_distance: float,
	p_is_critical: bool
) -> void:
	vfx_id = p_vfx_id
	vfx_type = p_vfx_type
	vfx_color = p_color
	direction = p_direction.normalized() if p_direction.length_squared() > 0.001 else Vector3.FORWARD
	distance = p_distance
	is_critical = p_is_critical
	
	# 计算起始和目标位置
	start_position = global_position
	target_position = start_position + direction * distance
	
	_create_arrow()
	_create_trail()


## 创建箭头网格
func _create_arrow() -> void:
	_arrow_mesh = MeshInstance3D.new()
	_arrow_mesh.name = "ArrowMesh"
	add_child(_arrow_mesh)
	
	# 创建箭头形状（棱锥）
	var arrow := _create_arrow_shape()
	_arrow_mesh.mesh = arrow
	
	# 发光材质
	_material = StandardMaterial3D.new()
	_material.albedo_color = vfx_color
	_material.emission_enabled = true
	_material.emission = vfx_color
	_material.emission_energy_multiplier = 4.0 if is_critical else 2.5
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_mesh.material_override = _material
	
	# 初始位置和旋转
	_arrow_mesh.position.y = 1.2  # 抬高到角色中心高度
	_update_arrow_rotation()


## 创建箭头形状（棱锥）
func _create_arrow_shape() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	
	# 箭头大小（缩小头部）
	var size := 0.5 if is_critical else 0.3
	var length := size * 1.5
	var width := size * 0.5
	
	# 箭头顶点（指向 +Z 方向）
	vertices.append(Vector3(0, 0, length))             # 0: 尖端
	vertices.append(Vector3(-width, width * 0.3, 0))   # 1: 左上
	vertices.append(Vector3(width, width * 0.3, 0))    # 2: 右上
	vertices.append(Vector3(width, -width * 0.3, 0))   # 3: 右下
	vertices.append(Vector3(-width, -width * 0.3, 0))  # 4: 左下
	vertices.append(Vector3(0, 0, -length * 0.3))      # 5: 尾部
	
	# 三角形面
	indices.append_array([0, 1, 2])  # 上
	indices.append_array([0, 2, 3])  # 右
	indices.append_array([0, 3, 4])  # 下
	indices.append_array([0, 4, 1])  # 左
	indices.append_array([5, 2, 1])  # 后上
	indices.append_array([5, 3, 2])  # 后右
	indices.append_array([5, 4, 3])  # 后下
	indices.append_array([5, 1, 4])  # 后左
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 创建拖尾效果
func _create_trail() -> void:
	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.name = "TrailMesh"
	add_child(_trail_mesh)
	
	# 拖尾使用细长的盒子
	var trail := BoxMesh.new()
	var trail_width := 0.15 if is_critical else 0.1
	trail.size = Vector3(trail_width, trail_width, 1.0)
	_trail_mesh.mesh = trail
	
	# 半透明发光材质
	_trail_material = StandardMaterial3D.new()
	_trail_material.albedo_color = Color(vfx_color.r, vfx_color.g, vfx_color.b, 0.6)
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.emission_enabled = true
	_trail_material.emission = vfx_color
	_trail_material.emission_energy_multiplier = 2.0 if is_critical else 1.5
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mesh.material_override = _trail_material
	
	_trail_mesh.position.y = 1.2
	_trail_mesh.visible = false


## 更新箭头旋转（朝向飞行方向）
func _update_arrow_rotation() -> void:
	if direction.length_squared() < 0.001:
		return
	var angle := atan2(direction.x, direction.z)
	_arrow_mesh.rotation.y = angle


# ========== 更新 ==========

## 更新特效进度（位置插值）
func update_progress(progress: float, _scale_factor: float, alpha: float) -> void:
	# 计算当前位置（从起点飞向终点）
	var current_pos := start_position.lerp(target_position, progress)
	current_pos.y = 1.2
	
	# 更新箭头位置
	_arrow_mesh.global_position = current_pos
	
	# 更新拖尾
	if progress > 0.05:
		_trail_mesh.visible = true
		var trail_length := start_position.distance_to(current_pos)
		var trail_center := start_position.lerp(current_pos, 0.5)
		trail_center.y = 1.2
		
		_trail_mesh.global_position = trail_center
		_trail_mesh.rotation.y = atan2(direction.x, direction.z)
		
		# 动态调整拖尾长度
		var trail_box := _trail_mesh.mesh as BoxMesh
		if trail_box:
			var trail_width := 0.15 if is_critical else 0.1
			trail_box.size = Vector3(trail_width, trail_width, trail_length)
	
	# 透明度（接近目标时淡出）
	var fade := 1.0 if progress < 0.7 else (1.0 - progress) / 0.3
	_material.albedo_color.a = fade
	_material.emission_energy_multiplier = (4.0 if is_critical else 2.5) * fade * alpha
	
	_trail_material.albedo_color.a = 0.6 * fade * alpha
	_trail_material.emission_energy_multiplier = (2.0 if is_critical else 1.5) * fade * alpha


## 清理
func cleanup() -> void:
	queue_free()
