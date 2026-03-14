extends Node3D

## 3D 网格渲染器测试场景
##
## 用于手动验证 GridMapRenderer3D 的功能。
## 提供 UI 控件来测试不同绘制模式和参数。
## 使用 LomoCameraRig 提供相机控制（WASD移动、QE旋转、滚轮缩放）。
##
## 场景结构要求：
## - GridMapRenderer3D 节点
## - LomoCameraRig 相机（通过代码实例化）
## - DirectionalLight3D 节点
## - UI 控件（下拉框、输入框、按钮）

@onready var renderer: GridMapRenderer3D = $GridMapRenderer3D

# UI 控件引用
@onready var draw_mode_option: OptionButton = $UI/VBoxContainer/DrawModeOption
@onready var rows_container: HBoxContainer = $UI/VBoxContainer/RowsContainer
@onready var columns_container: HBoxContainer = $UI/VBoxContainer/ColumnsContainer
@onready var radius_container: HBoxContainer = $UI/VBoxContainer/RadiusContainer
@onready var rows_input: SpinBox = $UI/VBoxContainer/RowsContainer/RowsInput
@onready var columns_input: SpinBox = $UI/VBoxContainer/ColumnsContainer/ColumnsInput
@onready var radius_input: SpinBox = $UI/VBoxContainer/RadiusContainer/RadiusInput
@onready var hex_size_input: SpinBox = $UI/VBoxContainer/HexSizeContainer/HexSizeInput

var _model: GridMapModel
var _camera_rig: LomoCameraRig
var _controller: LomoPlayerController


func _ready() -> void:
	# 设置相机控制
	_setup_camera()
	
	# 初始化下拉框选项
	draw_mode_option.add_item("Row/Column", 0)
	draw_mode_option.add_item("Radius", 1)
	draw_mode_option.selected = 0
	
	# 初始化输入框默认值
	rows_input.value = 9
	columns_input.value = 9
	radius_input.value = 4
	hex_size_input.value = 50
	
	# 初始显示/隐藏对应的输入框
	_update_input_visibility()
	
	# 创建初始网格
	_recreate_world()
	
	# 打印控制说明
	print("\n========== Grid Map 3D Test ==========")
	print("Camera Controls:")
	print("  WASD / Arrow Keys - Move camera")
	print("  Q / E - Rotate camera")
	print("  Mouse Wheel - Zoom")
	print("  Space - Reset camera")
	print("")


## 设置相机和控制器
func _setup_camera() -> void:
	# 实例化 LomoCameraRig
	var camera_scene: PackedScene = preload("res://addons/lomolib/camera/lomo_camera_rig.tscn")
	_camera_rig = camera_scene.instantiate() as LomoCameraRig
	_camera_rig.name = "CameraRig"
	add_child(_camera_rig)
	_camera_rig.make_current()
	
	# 创建控制器
	_controller = LomoPlayerController.new()
	_controller.name = "PlayerController"
	add_child(_controller)
	_controller.use_camera_rig(_camera_rig)


## 根据当前选择的模式更新输入框可见性
func _update_input_visibility() -> void:
	var is_row_column: bool = draw_mode_option.selected == 0
	rows_container.visible = is_row_column
	columns_container.visible = is_row_column
	radius_container.visible = not is_row_column


## 根据当前参数重新创建世界
func _recreate_world() -> void:
	var config: GridMapConfig = GridMapConfig.new()
	config.grid_type = GridMapConfig.GridType.HEX
	config.orientation = GridMapConfig.Orientation.FLAT
	config.size = hex_size_input.value
	
	if draw_mode_option.selected == 0:
		# Row/Column 模式
		config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		config.rows = int(rows_input.value)
		config.columns = int(columns_input.value)
	else:
		# Radius 模式
		config.draw_mode = GridMapConfig.DrawMode.RADIUS
		config.radius = int(radius_input.value)
	
	_model = GridMapModel.new()
	_model.initialize(config)
	renderer.set_model(_model)
	renderer.clear_all()


## 绘制模式下拉框变化回调
func _on_draw_mode_option_item_selected(_index: int) -> void:
	_update_input_visibility()
	_recreate_world()


## 行数输入变化回调
func _on_rows_input_value_changed(_value: float) -> void:
	_recreate_world()


## 列数输入变化回调
func _on_columns_input_value_changed(_value: float) -> void:
	_recreate_world()


## 半径输入变化回调
func _on_radius_input_value_changed(_value: float) -> void:
	_recreate_world()


## 六边形大小输入变化回调
func _on_hex_size_input_value_changed(_value: float) -> void:
	_recreate_world()


## 渲染按钮回调：显示网格线框
func _on_render_button_pressed() -> void:
	renderer.render_grid()


## 高亮按钮回调：高亮中心区域的格子
func _on_highlight_button_pressed() -> void:
	# 高亮中心 7 格（半径 1）
	var center := HexCoord.new(0, 0)
	var coords: Array[HexCoord] = []
	coords.append(center)
	for neighbor in center.get_neighbors():
		coords.append(neighbor)
	renderer.highlight_tiles(coords)


## 填充按钮回调：填充外围一圈格子
func _on_fill_button_pressed() -> void:
	var coords: Array[HexCoord] = []
	var center := HexCoord.new(0, 0)
	
	# 遍历所有格子，选择外围一圈（距离中心较远的格子）
	var all_coords: Array[HexCoord] = _model.get_all_coords()
	if all_coords.is_empty():
		return
	
	# 计算最大距离
	var max_dist: int = 0
	for coord: HexCoord in all_coords:
		var dist: int = center.distance_to(coord)
		if dist > max_dist:
			max_dist = dist
	
	# 选择最外圈
	for coord: HexCoord in all_coords:
		var dist: int = center.distance_to(coord)
		if dist >= max_dist - 1:
			coords.append(coord)
	
	renderer.fill_tiles(coords)


## 清除按钮回调：清除所有渲染效果
func _on_clear_button_pressed() -> void:
	renderer.clear_all()
