class_name GridMapRenderer3D
extends Node3D

## 3D Grid Map Renderer
##
## 两层渲染:
##   1. Wireframe / Highlight / Fill — ImmediateMesh + MeshInstance3D 画线/三角形
##   2. Env Mesh — MultiMeshInstance3D 按 mesh 分组批渲染地形 tile (UE ISMC 等价物)
##
## Env mesh 用法:
##   register_env(&"grass", grass_mesh)
##   register_env(&"road", road_mesh, 0.0, Color(1, 0.9, 0.7))
##   set_tile_env(coord, &"grass")
##   clear_tile_env(coord)
##
## 两层互不干涉, wireframe 走旧路径,env mesh 走新 MultiMesh 路径,共享 _model。
## 多个 env_id 可以共享同一 Mesh — 自动合批进同一个 MultiMeshInstance3D。
##
## 对应 UE 端 AGridMapRenderer 的 DynamicEnvironmentComponents + Mesh2ISMCIndexMap 设计。




## Grid line color
@export var grid_color: Color = Color.WHITE

## Highlight color
@export var highlight_color: Color = Color.YELLOW

## Fill color
@export var fill_color: Color = Color(0.2, 0.6, 1.0, 0.3)

## Line width
@export var line_width: float = 2.0

## Height scale factor
## Final Y position = tile.height * height_scale
@export var height_scale: float = 10.0

## Offset above the tile surface to prevent z-fighting for grid lines
@export var vertical_offset: float = 0.05

# Internal state
var _model: GridMapModel = null
var _show_grid: bool = false
var _highlighted_cells: Dictionary = {}  # String (key) -> Color
var _filled_cells: Dictionary = {}  # String (key) -> Color

# Render components
var _grid_mesh_instance: MeshInstance3D = null
var _fill_mesh_instance: MeshInstance3D = null
var _grid_mesh: ImmediateMesh = null
var _fill_mesh: ImmediateMesh = null

# ========== Env Mesh (MultiMesh) state ==========
# env_id (StringName) -> { mesh, yaw_offset_deg, custom (Color) }
var _env_configs: Dictionary = {}
# Mesh -> MultiMeshInstance3D (按 mesh 分组,多 env_id 共享同 mesh 时合批进同一节点)
var _mesh_to_mm: Dictionary = {}
# Mesh -> Array[Transform3D]  待写入的 transform 列表 (set_tile_env 累积,_flush_envs() 提交)
var _mesh_to_transforms: Dictionary = {}
# Mesh -> Array[Color]  per-instance custom data
var _mesh_to_customs: Dictionary = {}
# coord_key (String) -> { env_id, mesh, idx }   base layer (替换式)
var _coord_env: Dictionary = {}
# coord_key (String) -> Array[{ env_id, mesh, idx }]   overlay layer (累加式装饰)
var _coord_decorations: Dictionary = {}
# MultiMeshInstance3D 的父节点
var _env_root: Node3D = null
# 是否需要 flush (set_tile_env / clear_tile_env 标记 dirty)
var _envs_dirty: bool = false

# (grid_type, orientation) -> tile yaw offset(degrees), 对应 UE 端 FlatRotator/HexPointyRotator/RectPointyRotator
# 假设 mesh 内置朝向是 pointy-top hex: pointy 模式 yaw=0 直接用,flat 模式 yaw=30 把尖角转成平边对齐 X 轴。
const _GRID_YAW := {
	GridMapConfig.GridType.HEX: {
		GridMapConfig.Orientation.FLAT: 30.0,
		GridMapConfig.Orientation.POINTY: 0.0,
	},
	GridMapConfig.GridType.RECT_SIX_DIR: {
		GridMapConfig.Orientation.FLAT: 0.0,
		GridMapConfig.Orientation.POINTY: 90.0,
	},
}


func _ready() -> void:
	# Create Grid MeshInstance3D
	_grid_mesh = ImmediateMesh.new()
	_grid_mesh_instance = MeshInstance3D.new()
	_grid_mesh_instance.mesh = _grid_mesh
	add_child(_grid_mesh_instance)
	
	var grid_mat := StandardMaterial3D.new()
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.vertex_color_use_as_albedo = true
	_grid_mesh_instance.material_override = grid_mat
	
	# Create Fill MeshInstance3D
	_fill_mesh = ImmediateMesh.new()
	_fill_mesh_instance = MeshInstance3D.new()
	_fill_mesh_instance.mesh = _fill_mesh
	add_child(_fill_mesh_instance)
	
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.vertex_color_use_as_albedo = true
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mesh_instance.material_override = fill_mat

	_env_root = Node3D.new()
	_env_root.name = "EnvRoot"
	add_child(_env_root)


## Set the GridMapModel to render
## @param model: GridMapModel instance, pass null to clear
func set_model(model: GridMapModel) -> void:
	if _model != model:
		_model = model
		if _model:
			# Connect signals if needed in future
			pass
	_render()


## Render the grid lines
func render_grid() -> void:
	_show_grid = true
	_render()


## Highlight specific tiles
## @param coords: Array of coordinates to highlight (Array[HexCoord])
## @param color: Highlight color (default: highlight_color)
func highlight_tiles(coords: Array, color: Color = highlight_color) -> void:
	for coord in coords:
		_highlighted_cells[coord.to_key()] = color
	_render()


## Fill specific tiles
## @param coords: Array of coordinates to fill (Array[HexCoord])
## @param color: Fill color (default: fill_color)
func fill_tiles(coords: Array, color: Color = fill_color) -> void:
	for coord in coords:
		_filled_cells[coord.to_key()] = color
	_render()


## Clear all highlights
func clear_highlights() -> void:
	_highlighted_cells.clear()
	_render()


## Clear all fills
func clear_fills() -> void:
	_filled_cells.clear()
	_render()


## Clear all (highlights + fills + grid)
func clear_all() -> void:
	_highlighted_cells.clear()
	_filled_cells.clear()
	_show_grid = false
	_render()


## Core rendering method
func _render() -> void:
	if _model == null:
		return
	
	# Clear old geometry
	_grid_mesh.clear_surfaces()
	_fill_mesh.clear_surfaces()
	
	var layout: GridLayout = _model.get_layout()
	var grid_type: int = _model.get_grid_type()
	
	# 1. Draw Fills (Triangles)
	if not _filled_cells.is_empty():
		_fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		
		for key in _filled_cells.keys():
			var color: Color = _filled_cells[key]
			var coord: HexCoord = HexCoord.from_key(key)
			var corners: PackedVector2Array = _get_cell_corners(layout, grid_type, coord.to_axial())
			var height: float = _get_cell_height(coord)
			var center_2d: Vector2 = layout.coord_to_pixel(coord.to_axial())
			var center_3d: Vector3 = Vector3(center_2d.x, height + vertical_offset, center_2d.y)
			
			# Triangle fan from center to corners
			for i in range(corners.size()):
				var p1_2d := corners[i]
				var p2_2d := corners[(i + 1) % corners.size()]
				
				var p1 := Vector3(p1_2d.x, height + vertical_offset, p1_2d.y)
				var p2 := Vector3(p2_2d.x, height + vertical_offset, p2_2d.y)
				
				_fill_mesh.surface_set_color(color)
				_fill_mesh.surface_add_vertex(center_3d)
				_fill_mesh.surface_set_color(color)
				_fill_mesh.surface_add_vertex(p1)
				_fill_mesh.surface_set_color(color)
				_fill_mesh.surface_add_vertex(p2)
				
		_fill_mesh.surface_end()
	
	# 2. Draw Grid Lines and Highlights
	var has_grid_content := _show_grid or not _highlighted_cells.is_empty()
	
	if has_grid_content:
		_grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		
		# Draw base grid lines
		if _show_grid:
			for coord in _model.get_all_coords():
				var corners := _get_cell_corners(layout, grid_type, coord.to_axial())
				var height := _get_cell_height(coord)
				
				for i in range(corners.size()):
					var p1_2d := corners[i]
					var p2_2d := corners[(i + 1) % corners.size()]
					
					var p1 := Vector3(p1_2d.x, height + vertical_offset, p1_2d.y)
					var p2 := Vector3(p2_2d.x, height + vertical_offset, p2_2d.y)
					
					_grid_mesh.surface_set_color(grid_color)
					_grid_mesh.surface_add_vertex(p1)
					_grid_mesh.surface_set_color(grid_color)
					_grid_mesh.surface_add_vertex(p2)
		
		# Draw highlights (on top, same mesh but different color)
		for key in _highlighted_cells.keys():
			var color: Color = _highlighted_cells[key]
			var coord: HexCoord = HexCoord.from_key(key)
			var corners := _get_cell_corners(layout, grid_type, coord.to_axial())
			var height := _get_cell_height(coord) + (vertical_offset * 2) # Slightly higher than grid
			
			for i in range(corners.size()):
				var p1_2d := corners[i]
				var p2_2d := corners[(i + 1) % corners.size()]
				
				var p1 := Vector3(p1_2d.x, height, p1_2d.y)
				var p2 := Vector3(p2_2d.x, height, p2_2d.y)
				
				_grid_mesh.surface_set_color(color)
				_grid_mesh.surface_add_vertex(p1)
				_grid_mesh.surface_set_color(color)
				_grid_mesh.surface_add_vertex(p2)
				
		_grid_mesh.surface_end()


## Helper to get cell corners based on grid type
func _get_cell_corners(layout: GridLayout, grid_type: int, coord: Vector2i) -> PackedVector2Array:
	# Note: GridMapConfig.GridType is an enum, accessing via int is safe if passed correctly
	# We rely on the layout to handle the specific geometry
	if grid_type == GridMapConfig.GridType.HEX:
		return layout.hex_corners(coord)
	else:
		return layout.rect_corners(coord)


## Helper to get cell height from model
func _get_cell_height(coord: HexCoord) -> float:
	if _model:
		return _model.get_tile_height(coord) * height_scale
	return 0.0


# ========================================================================
# Env Mesh API
# ========================================================================


## 注册 env_id 到 mesh 配置。同一 mesh 多 env_id 注册共享一个 MultiMeshInstance3D 节点合批渲染。
## yaw_offset_deg 在 grid orientation 自动旋转之上叠加 (per-env mesh facing 调整)。
## custom 写入 INSTANCE_CUSTOM(vec4),用户的 ShaderMaterial 自行消费,默认 StandardMaterial3D 不响应。
func register_env(env_id: StringName, mesh: Mesh, yaw_offset_deg: float = 0.0, custom: Color = Color(1, 1, 1, 1)) -> void:
	if mesh == null:
		push_error("[GridMapRenderer3D] register_env(%s): mesh is null" % env_id)
		return
	_env_configs[env_id] = {
		"mesh": mesh,
		"yaw_offset_deg": yaw_offset_deg,
		"custom": custom,
	}
	if not _mesh_to_mm.has(mesh):
		var mmi := MultiMeshInstance3D.new()
		var label := "MM_" + str(_mesh_to_mm.size())
		if mesh.resource_path != "":
			label = "MM_" + mesh.resource_path.get_file().get_basename()
		mmi.name = label
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mmi.multimesh = mm
		_env_root.add_child(mmi)
		_mesh_to_mm[mesh] = mmi
		_mesh_to_transforms[mesh] = []
		_mesh_to_customs[mesh] = []


## 设置单 tile 的 env mesh。修改累积到内部数组,_flush_envs() 时一次性 commit 到 MultiMesh。
## facing_override: 不为 NAN 时覆盖 env 注册的 yaw_offset。
##
## 注意: 不会立即生效, 调用方需在批量 set 完毕后调 flush_envs() 提交。set_tile_env 内部会
## 自动 flush_envs() 一次保证使用方便, 但批量大量 tile 时建议显式 flush 一次。
func set_tile_env(coord: HexCoord, env_id: StringName, facing_override: float = NAN) -> void:
	if coord == null or not coord.is_valid():
		return
	if not _env_configs.has(env_id):
		push_warning("[GridMapRenderer3D] env_id not registered: %s" % env_id)
		return
	var key := coord.to_key()
	if _coord_env.has(key):
		_remove_coord_entry(key)

	var cfg: Dictionary = _env_configs[env_id]
	var mesh: Mesh = cfg["mesh"]
	var transforms: Array = _mesh_to_transforms[mesh]
	var customs: Array = _mesh_to_customs[mesh]

	var yaw: float = facing_override if not is_nan(facing_override) else cfg["yaw_offset_deg"]
	var t := _build_instance_transform(coord, yaw)

	var idx := transforms.size()
	transforms.append(t)
	customs.append(cfg["custom"])

	_coord_env[key] = { "env_id": env_id, "mesh": mesh, "idx": idx }
	_envs_dirty = true
	flush_envs()


## 清除单 tile env mesh。内部 swap-to-end + flush。
func clear_tile_env(coord: HexCoord) -> void:
	if coord == null:
		return
	var key := coord.to_key()
	if _coord_env.has(key):
		_remove_coord_entry(key)
		flush_envs()


## 在 coord 上叠加一个装饰 instance,不替换 base env。可在同 coord 多次调用叠多层。
## 第一版不支持单装饰 remove,要清装饰只能 clear_all_envs() 重灌。建筑/树/山等附加在
## grass tile 上的视觉物件用这个,不要用 set_tile_env (那是替换地形语义)。
func add_decoration(coord: HexCoord, env_id: StringName, facing_override: float = NAN) -> void:
	if coord == null or not coord.is_valid():
		return
	if not _env_configs.has(env_id):
		push_warning("[GridMapRenderer3D] env_id not registered: %s" % env_id)
		return
	var key := coord.to_key()
	var cfg: Dictionary = _env_configs[env_id]
	var mesh: Mesh = cfg["mesh"]
	var transforms: Array = _mesh_to_transforms[mesh]
	var customs: Array = _mesh_to_customs[mesh]

	var yaw: float = facing_override if not is_nan(facing_override) else cfg["yaw_offset_deg"]
	var idx := transforms.size()
	transforms.append(_build_instance_transform(coord, yaw))
	customs.append(cfg["custom"])

	var arr: Array = _coord_decorations.get(key, [])
	arr.append({ "env_id": env_id, "mesh": mesh, "idx": idx })
	_coord_decorations[key] = arr
	_envs_dirty = true
	flush_envs()


## 清空所有 env mesh instance,保留注册的 env_configs。
func clear_all_envs() -> void:
	for mesh in _mesh_to_mm.keys():
		_mesh_to_transforms[mesh] = []
		_mesh_to_customs[mesh] = []
	_coord_env.clear()
	_coord_decorations.clear()
	_envs_dirty = true
	flush_envs()


## 把累积的 transform / custom 一次性提交到 MultiMesh.buffer。
## set_tile_env / clear_tile_env / clear_all_envs 自动调用一次; 大批量修改时可
## 先调 set_envs_deferred(true), 改完再手动 flush_envs() 减少重复刷新。
func flush_envs() -> void:
	if not _envs_dirty:
		return
	for mesh in _mesh_to_mm.keys():
		var mmi: MultiMeshInstance3D = _mesh_to_mm[mesh]
		var mm := mmi.multimesh
		var transforms: Array = _mesh_to_transforms[mesh]
		var n := transforms.size()
		# 关键: 一次性写 instance_count + buffer, 避免逐个 set_instance_transform 在 Godot 4
		# 触发的 buffer reset 怪现象。
		mm.instance_count = n
		if n > 0:
			var buf := PackedFloat32Array()
			buf.resize(n * 12)
			for i in range(n):
				var t: Transform3D = transforms[i]
				var b := t.basis
				var o := t.origin
				var off := i * 12
				buf[off + 0] = b.x.x; buf[off + 1] = b.y.x; buf[off + 2] = b.z.x; buf[off + 3] = o.x
				buf[off + 4] = b.x.y; buf[off + 5] = b.y.y; buf[off + 6] = b.z.y; buf[off + 7] = o.y
				buf[off + 8] = b.x.z; buf[off + 9] = b.y.z; buf[off + 10] = b.z.z; buf[off + 11] = o.z
			mm.buffer = buf
	_envs_dirty = false


## 当前已渲染的 env tile 数量。
func get_env_tile_count() -> int:
	return _coord_env.size()


# 内部: 从 _coord_env 移除 entry, 同步从 transforms / customs 数组里 swap-to-end + pop_back, 修补换上来那条的 idx。
func _remove_coord_entry(key: String) -> void:
	var entry: Dictionary = _coord_env[key]
	var mesh: Mesh = entry["mesh"]
	var idx: int = entry["idx"]
	var transforms: Array = _mesh_to_transforms[mesh]
	var customs: Array = _mesh_to_customs[mesh]
	var last_idx := transforms.size() - 1

	if idx != last_idx:
		transforms[idx] = transforms[last_idx]
		customs[idx] = customs[last_idx]
		for k in _coord_env.keys():
			var e: Dictionary = _coord_env[k]
			if e["mesh"] == mesh and e["idx"] == last_idx:
				e["idx"] = idx
				_coord_env[k] = e
				break

	transforms.pop_back()
	customs.pop_back()
	_coord_env.erase(key)
	_envs_dirty = true


# ========================================================================
# Env Mesh internals
# ========================================================================


func _build_instance_transform(coord: HexCoord, yaw_offset_deg: float) -> Transform3D:
	var pixel := Vector2.ZERO
	var height := 0.0
	if _model != null:
		pixel = _model.coord_to_world(coord)
		height = _get_cell_height(coord)
	var pos := Vector3(pixel.x, height, pixel.y)
	var grid_yaw := _get_grid_yaw_deg()
	var basis := Basis(Vector3.UP, deg_to_rad(grid_yaw + yaw_offset_deg))
	return Transform3D(basis, pos)


## 根据 model.config.grid_type / orientation 查 tile 整体 yaw 偏移。
func _get_grid_yaw_deg() -> float:
	if _model == null:
		return 0.0
	var cfg := _model.get_config()
	if cfg == null:
		return 0.0
	var by_orient: Dictionary = _GRID_YAW.get(cfg.grid_type, {})
	return by_orient.get(cfg.orientation, 0.0)

