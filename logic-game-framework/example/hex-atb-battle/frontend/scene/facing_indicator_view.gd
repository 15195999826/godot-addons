## Phase F · FacingIndicatorView - 朝向箭头 attached visual
##
## 显示 CharacterActor 当前 6 向朝向. EnvironmentActor 等无 facing 语义的 actor 由 UnitView
## 跳过 attach (per spec: "只对 CharacterActor 显示").
##
## 实现: 贴近地面的水平 mesh marker, 随 facing_direction 在 X-Z 平面旋转.
## 不引入 turn-speed / lerp 动画 — 每次 update_from_state 都瞬时 snap 到新方向 (per spec).
class_name FrontendFacingIndicatorView
extends Node3D


## Marker 贴近地面, 避免旧 Label3D billboard 看起来像朝天。
const MARKER_FILL_HEIGHT := 0.085
const MARKER_OUTLINE_HEIGHT := 0.075
## 箭头从 unit body 外圈开始, 不压在球体中心。
const MARKER_INNER_RADIUS := 0.52
const MARKER_NECK_RADIUS := 0.76
const MARKER_TIP_RADIUS := 1.02
const MARKER_SHAFT_HALF_WIDTH := 0.045
const MARKER_HEAD_HALF_WIDTH := 0.18


var _marker_root: Node3D
var _fill_mesh: MeshInstance3D
var _outline_mesh: MeshInstance3D


func _ready() -> void:
	_marker_root = Node3D.new()
	_marker_root.name = "MarkerRoot"
	add_child(_marker_root)

	_outline_mesh = _create_marker_instance(
		"FacingMarkerOutline",
		_create_arrow_mesh(MARKER_OUTLINE_HEIGHT, 0.035, 0.04),
		_create_marker_material(Color(0.03, 0.025, 0.01, 0.95))
	)
	_marker_root.add_child(_outline_mesh)

	_fill_mesh = _create_marker_instance(
		"FacingMarkerFill",
		_create_arrow_mesh(MARKER_FILL_HEIGHT, 0.0, 0.0),
		_create_marker_material(Color(1.0, 0.78, 0.18, 1.0))
	)
	_marker_root.add_child(_fill_mesh)


## 接收 FrontendActorRenderState; 仅当 type == "Character" 才可见.
func update_from_state(state: FrontendActorRenderState) -> void:
	if state == null:
		visible = false
		return
	if state.type != HexBattleActor.KIND_CHARACTER:
		# EnvironmentActor 等不显示 facing 箭头 (per spec).
		visible = false
		return
	visible = true
	var dir_vec := _direction_vector_for_state(state)
	_marker_root.rotation.y = atan2(-dir_vec.z, dir_vec.x)


func _direction_vector_for_state(state: FrontendActorRenderState) -> Vector3:
	if state.position != null and state.position.is_valid() and UGridMap.model != null:
		var origin_2d := UGridMap.model.coord_to_world(state.position)
		var neighbor_coord := state.position.neighbor(state.facing_direction)
		var neighbor_2d := UGridMap.model.coord_to_world(neighbor_coord)
		var delta := neighbor_2d - origin_2d
		if delta.length() > 0.001:
			return Vector3(delta.x, 0.0, delta.y).normalized()
	return _fallback_direction_vector(state.facing_direction)


func _fallback_direction_vector(facing_direction: int) -> Vector3:
	var angle_rad := -float(posmod(facing_direction, 6)) * PI / 3.0
	return Vector3(cos(angle_rad), 0.0, sin(angle_rad)).normalized()


func _create_marker_instance(
	instance_name: String,
	mesh: ArrayMesh,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = instance_name
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance


func _create_marker_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.65
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _create_arrow_mesh(marker_height: float, width_pad: float, length_pad: float) -> ArrayMesh:
	var inner_radius := MARKER_INNER_RADIUS - length_pad
	var neck_radius := MARKER_NECK_RADIUS
	var tip_radius := MARKER_TIP_RADIUS + length_pad
	var shaft_half_width := MARKER_SHAFT_HALF_WIDTH + width_pad
	var head_half_width := MARKER_HEAD_HALF_WIDTH + width_pad

	var vertices := PackedVector3Array([
		Vector3(inner_radius, marker_height, -shaft_half_width),
		Vector3(neck_radius, marker_height, -shaft_half_width),
		Vector3(neck_radius, marker_height, shaft_half_width),
		Vector3(inner_radius, marker_height, -shaft_half_width),
		Vector3(neck_radius, marker_height, shaft_half_width),
		Vector3(inner_radius, marker_height, shaft_half_width),
		Vector3(tip_radius, marker_height, 0.0),
		Vector3(neck_radius, marker_height, -head_half_width),
		Vector3(neck_radius, marker_height, head_half_width),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
