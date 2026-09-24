## Cone debug overlay view: translucent checked-cell fill plus thick boundary/guide lines.
##
## 卡片给的格子 / 外沿是逻辑平面 axial（整数格 / 浮点端点），引导线是逻辑层自己的 2D 平面坐标；
## 多边形与 3D 投影都在这里用棋盘几何建，抬到各自的贴地高度。
class_name FrontendConeDebugOverlayView
extends Node3D


const BOUNDARY_HALF_WIDTH := 0.045
const FADE_OUT_RATIO := 0.25
## 填充 / 边界贴地高度（略抬起避免与棋盘 z-fight）
const FILL_Y := 0.06
const BOUNDARY_Y := 0.12

var _fill_mesh := ImmediateMesh.new()
var _boundary_mesh := ImmediateMesh.new()
var _fill_instance: MeshInstance3D
var _boundary_instance: MeshInstance3D
var _fill_material: StandardMaterial3D
var _boundary_material: StandardMaterial3D
var _duration_ms: float = 0.0
var _elapsed_ms: float = 0.0


func _ready() -> void:
	_fill_instance = MeshInstance3D.new()
	_fill_instance.name = "Fill"
	_fill_instance.mesh = _fill_mesh
	add_child(_fill_instance)

	_boundary_instance = MeshInstance3D.new()
	_boundary_instance.name = "Boundary"
	_boundary_instance.mesh = _boundary_mesh
	add_child(_boundary_instance)

	_fill_material = _create_material()
	_boundary_material = _create_material()
	_fill_instance.material_override = _fill_material
	_boundary_instance.material_override = _boundary_material


## 没有棋盘几何就画不出格子，overlay 保持空白到期自毁
func initialize(data: FrontendConeDebugOverlayAction.Payload, layout: GridLayout) -> void:
	_duration_ms = data.duration
	_elapsed_ms = 0.0
	if layout == null:
		return
	_render_fill(_cell_polygons(data.cells, layout), data.fill_color)
	var segments: Array[PackedVector3Array] = []
	for segment in data.boundary_segments:
		segments.append(_project_segment(segment, layout))
	for segment in data.guide_segments:
		segments.append(_lift_segment(segment))
	_render_boundary(segments, data.boundary_color)


func _process(delta: float) -> void:
	if _duration_ms <= 0.0:
		return
	_elapsed_ms += delta * 1000.0
	var remaining := maxf(_duration_ms - _elapsed_ms, 0.0)
	var fade_window := _duration_ms * FADE_OUT_RATIO
	var alpha_scale := 1.0
	if fade_window > 0.0 and remaining < fade_window:
		alpha_scale = remaining / fade_window
	_fill_material.albedo_color.a = alpha_scale
	_boundary_material.albedo_color.a = alpha_scale
	if _elapsed_ms >= _duration_ms:
		queue_free()


func _create_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## 每个格子的六个角点（棋盘几何给的角点顺序）抬到填充高度
static func _cell_polygons(cells: Array[Vector2], layout: GridLayout) -> Array[PackedVector3Array]:
	var polygons: Array[PackedVector3Array] = []
	for cell in cells:
		var polygon := PackedVector3Array()
		for corner in layout.hex_corners(Vector2i(roundi(cell.x), roundi(cell.y))):
			polygon.append(Vector3(corner.x, FILL_Y, corner.y))
		polygons.append(polygon)
	return polygons


## axial 浮点端点 → 世界坐标，抬到边界高度
static func _project_segment(segment: PackedVector2Array, layout: GridLayout) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in segment:
		var world := FrontendHexProjection.to_world(layout, point)
		out.append(Vector3(world.x, BOUNDARY_Y, world.z))
	return out


## 逻辑层 2D 平面点 (x, y) → X/Z 平面，抬到边界高度
static func _lift_segment(segment: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in segment:
		out.append(Vector3(point.x, BOUNDARY_Y, point.y))
	return out


func _render_fill(cell_polygons: Array[PackedVector3Array], fill_color: Color) -> void:
	_fill_mesh.clear_surfaces()
	if cell_polygons.is_empty():
		return
	_fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for polygon in cell_polygons:
		if polygon.size() < 3:
			continue
		var center := Vector3.ZERO
		for point in polygon:
			center += point
		center /= float(polygon.size())
		for i in range(polygon.size()):
			_fill_mesh.surface_set_color(fill_color)
			_fill_mesh.surface_add_vertex(center)
			_fill_mesh.surface_set_color(fill_color)
			_fill_mesh.surface_add_vertex(polygon[i])
			_fill_mesh.surface_set_color(fill_color)
			_fill_mesh.surface_add_vertex(polygon[(i + 1) % polygon.size()])
	_fill_mesh.surface_end()


func _render_boundary(boundary_segments: Array[PackedVector3Array], boundary_color: Color) -> void:
	_boundary_mesh.clear_surfaces()
	if boundary_segments.is_empty():
		return
	_boundary_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in boundary_segments:
		if segment.size() < 2:
			continue
		_add_boundary_quad(segment[0], segment[1], boundary_color)
	_boundary_mesh.surface_end()


func _add_boundary_quad(start: Vector3, finish: Vector3, boundary_color: Color) -> void:
	var direction := finish - start
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var normal := Vector3(-direction.z, 0.0, direction.x).normalized() * BOUNDARY_HALF_WIDTH
	var p0 := start + normal
	var p1 := finish + normal
	var p2 := finish - normal
	var p3 := start - normal
	_boundary_mesh.surface_set_color(boundary_color)
	_boundary_mesh.surface_add_vertex(p0)
	_boundary_mesh.surface_set_color(boundary_color)
	_boundary_mesh.surface_add_vertex(p1)
	_boundary_mesh.surface_set_color(boundary_color)
	_boundary_mesh.surface_add_vertex(p2)
	_boundary_mesh.surface_set_color(boundary_color)
	_boundary_mesh.surface_add_vertex(p0)
	_boundary_mesh.surface_set_color(boundary_color)
	_boundary_mesh.surface_add_vertex(p2)
	_boundary_mesh.surface_set_color(boundary_color)
	_boundary_mesh.surface_add_vertex(p3)
