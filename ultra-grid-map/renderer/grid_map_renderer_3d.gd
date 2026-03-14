class_name GridMapRenderer3D
extends Node3D

## 3D Grid Map Renderer
##
## Renders grid lines, highlights, and fills for all grid types (Hex, Square, Rect).
## Uses ImmediateMesh + MeshInstance3D.
## Supports height mapping based on tile data.




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

