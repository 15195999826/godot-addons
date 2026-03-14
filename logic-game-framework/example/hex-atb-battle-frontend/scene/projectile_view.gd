## ProjectileView - 投射物 3D 视图组件
##
## 显示投射物的 3D 表现，包括：
## - 几何体（球体/箭头）
## - 拖尾效果
## - 发光效果
class_name FrontendProjectileView
extends Node3D


# ========== 属性 ==========

## 投射物 ID
var projectile_id: String

## 投射物类型
var projectile_type: FrontendProjectileAction.ProjectileType

## 投射物颜色
var projectile_color: Color

## 投射物大小
var projectile_size: float

## 飞行方向
var direction: Vector3


# ========== 内部节点 ==========

var _mesh_instance: MeshInstance3D
var _trail: Node3D  # 拖尾效果容器
var _trail_points: Array[Vector3] = []
var _trail_mesh: ImmediateMesh
var _trail_mesh_instance: MeshInstance3D


# ========== 初始化 ==========

func initialize(
	p_projectile_id: String,
	p_projectile_type: FrontendProjectileAction.ProjectileType,
	p_color: Color,
	p_size: float,
	p_direction: Vector3
) -> void:
	projectile_id = p_projectile_id
	projectile_type = p_projectile_type
	projectile_color = p_color
	projectile_size = p_size
	direction = p_direction
	
	_create_mesh()
	_create_trail()
	_update_rotation()


## 创建投射物网格
func _create_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ProjectileMesh"
	add_child(_mesh_instance)
	
	var mesh: Mesh
	match projectile_type:
		FrontendProjectileAction.ProjectileType.ARROW:
			mesh = _create_arrow_mesh()
		FrontendProjectileAction.ProjectileType.FIREBALL:
			mesh = _create_sphere_mesh()
		_:
			mesh = _create_sphere_mesh()
	
	_mesh_instance.mesh = mesh
	
	# 创建发光材质
	var material := StandardMaterial3D.new()
	material.albedo_color = projectile_color
	material.emission_enabled = true
	material.emission = projectile_color
	material.emission_energy_multiplier = 2.0
	_mesh_instance.material_override = material


## 创建球形网格
func _create_sphere_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = projectile_size
	sphere.height = projectile_size * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	return sphere


## 创建箭头网格（使用圆柱体 + 圆锥体组合）
func _create_arrow_mesh() -> CylinderMesh:
	# 简化版：使用细长圆柱体
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = projectile_size * 0.2
	cylinder.bottom_radius = projectile_size * 0.2
	cylinder.height = projectile_size * 3.0
	cylinder.radial_segments = 8
	return cylinder


## 创建拖尾效果
func _create_trail() -> void:
	_trail = Node3D.new()
	_trail.name = "Trail"
	add_child(_trail)
	
	_trail_mesh = ImmediateMesh.new()
	_trail_mesh_instance = MeshInstance3D.new()
	_trail_mesh_instance.mesh = _trail_mesh
	_trail.add_child(_trail_mesh_instance)
	
	# 拖尾材质
	var trail_material := StandardMaterial3D.new()
	trail_material.albedo_color = Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.5)
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mesh_instance.material_override = trail_material


## 更新旋转（使投射物朝向飞行方向）
func _update_rotation() -> void:
	if direction.length_squared() < 0.001:
		return
	
	# 计算旋转使 Y 轴指向飞行方向
	var up := Vector3.UP
	var forward := direction.normalized()
	
	# 避免 forward 与 up 平行
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.FORWARD
	
	var right := up.cross(forward).normalized()
	up = forward.cross(right).normalized()
	
	var basis := Basis(right, forward, up)
	_mesh_instance.basis = basis


# ========== 更新 ==========

## 更新投射物位置和拖尾
func update_position(new_position: Vector3) -> void:
	# 记录拖尾点
	_trail_points.append(global_position)
	
	# 限制拖尾长度
	const MAX_TRAIL_POINTS := 20
	while _trail_points.size() > MAX_TRAIL_POINTS:
		_trail_points.pop_front()
	
	# 更新位置
	global_position = new_position
	
	# 更新拖尾渲染
	_render_trail()


## 渲染拖尾
func _render_trail() -> void:
	if _trail_points.size() < 2:
		return
	
	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	for i in range(_trail_points.size()):
		var alpha := float(i) / float(_trail_points.size())
		var color := Color(projectile_color.r, projectile_color.g, projectile_color.b, alpha * 0.5)
		_trail_mesh.surface_set_color(color)
		# 转换为本地坐标
		var local_pos := _trail.to_local(_trail_points[i])
		_trail_mesh.surface_add_vertex(local_pos)
	
	_trail_mesh.surface_end()


## 设置飞行方向
func set_direction(new_direction: Vector3) -> void:
	direction = new_direction
	_update_rotation()


## 清理
func cleanup() -> void:
	_trail_points.clear()
	queue_free()
