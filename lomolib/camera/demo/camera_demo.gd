## CameraDemo - 相机和控制器演示
##
## 演示 LomoCameraRig 和 LomoPlayerController 的基本用法
extends Node3D


# ========== 节点引用 ==========

var _camera_rig: LomoCameraRig
var _controller: LomoPlayerController
var _target_cube: MeshInstance3D
var _ground: MeshInstance3D
var _info_label: Label


# ========== 生命周期 ==========

func _ready() -> void:
	print("\n========== Camera Demo ==========\n")
	print("Controls:")
	print("  WASD / Arrow Keys - Move camera")
	print("  Q / E - Rotate camera")
	print("  Mouse Wheel - Zoom")
	print("  Space - Reset camera")
	print("  F - Toggle follow mode")
	print("  Left Click - Print ground position")
	print("")
	
	_setup_scene()
	_setup_camera()
	_setup_controller()
	_setup_ui()


func _setup_scene() -> void:
	# 创建棋盘格地面
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(50, 50)
	plane_mesh.subdivide_width = 50
	plane_mesh.subdivide_depth = 50
	_ground.mesh = plane_mesh
	
	# 棋盘格材质
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.4, 0.45, 0.4)
	_ground.material_override = ground_material
	
	# 添加碰撞体（用于射线检测）
	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundBody"
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(50, 0.1, 50)
	ground_collision.shape = ground_shape
	ground_collision.position.y = -0.05
	ground_body.add_child(ground_collision)
	_ground.add_child(ground_body)
	
	add_child(_ground)
	
	# 创建网格线参照物
	_create_grid_lines()
	
	# 创建坐标轴指示器
	_create_axis_indicator()
	
	# 创建散布的参照物体
	_create_reference_objects()
	
	# 创建目标立方体（用于跟随演示）- 红色，会移动
	_target_cube = MeshInstance3D.new()
	_target_cube.name = "TargetCube"
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3(1, 1, 1)
	_target_cube.mesh = cube_mesh
	_target_cube.position = Vector3(5, 0.5, 5)
	
	var cube_material := StandardMaterial3D.new()
	cube_material.albedo_color = Color(0.9, 0.2, 0.2)
	cube_material.emission_enabled = true
	cube_material.emission = Color(0.5, 0.1, 0.1)
	_target_cube.material_override = cube_material
	
	add_child(_target_cube)
	
	# 创建光照
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "DirectionalLight"
	dir_light.rotation_degrees = Vector3(-45, 45, 0)
	dir_light.light_energy = 1.0
	dir_light.shadow_enabled = true
	add_child(dir_light)
	
	# 创建环境
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	world_env.environment = env
	add_child(world_env)


## 创建网格线
func _create_grid_lines() -> void:
	var grid_container := Node3D.new()
	grid_container.name = "GridLines"
	add_child(grid_container)
	
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.3, 0.3, 0.35)
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	# 创建网格线 (-20 到 20，间隔 2)
	for i in range(-20, 21, 2):
		# X 方向线
		var line_x := _create_line(Vector3(i, 0.01, -20), Vector3(i, 0.01, 20), line_material)
		grid_container.add_child(line_x)
		
		# Z 方向线
		var line_z := _create_line(Vector3(-20, 0.01, i), Vector3(20, 0.01, i), line_material)
		grid_container.add_child(line_z)


## 创建单条线
func _create_line(from: Vector3, to: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(from)
	immediate_mesh.surface_add_vertex(to)
	immediate_mesh.surface_end()
	
	mesh_instance.mesh = immediate_mesh
	mesh_instance.material_override = material
	return mesh_instance


## 创建坐标轴指示器
func _create_axis_indicator() -> void:
	var axis_container := Node3D.new()
	axis_container.name = "AxisIndicator"
	add_child(axis_container)
	
	# X 轴 - 红色
	var x_material := StandardMaterial3D.new()
	x_material.albedo_color = Color.RED
	x_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var x_line := _create_line(Vector3.ZERO, Vector3(5, 0, 0), x_material)
	axis_container.add_child(x_line)
	
	# X 轴箭头
	var x_arrow := _create_arrow(Vector3(5, 0, 0), Vector3(1, 0, 0), Color.RED)
	axis_container.add_child(x_arrow)
	
	# Z 轴 - 蓝色
	var z_material := StandardMaterial3D.new()
	z_material.albedo_color = Color.BLUE
	z_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var z_line := _create_line(Vector3.ZERO, Vector3(0, 0, 5), z_material)
	axis_container.add_child(z_line)
	
	# Z 轴箭头
	var z_arrow := _create_arrow(Vector3(0, 0, 5), Vector3(0, 0, 1), Color.BLUE)
	axis_container.add_child(z_arrow)
	
	# Y 轴 - 绿色
	var y_material := StandardMaterial3D.new()
	y_material.albedo_color = Color.GREEN
	y_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var y_line := _create_line(Vector3.ZERO, Vector3(0, 3, 0), y_material)
	axis_container.add_child(y_line)
	
	# 原点球
	var origin_sphere := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.2
	sphere_mesh.height = 0.4
	origin_sphere.mesh = sphere_mesh
	var origin_material := StandardMaterial3D.new()
	origin_material.albedo_color = Color.WHITE
	origin_sphere.material_override = origin_material
	axis_container.add_child(origin_sphere)


## 创建箭头
func _create_arrow(pos: Vector3, dir: Vector3, color: Color) -> MeshInstance3D:
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0
	cone.bottom_radius = 0.15
	cone.height = 0.4
	arrow.mesh = cone
	arrow.position = pos
	
	# 旋转箭头指向正确方向
	if dir.x > 0:
		arrow.rotation_degrees = Vector3(0, 0, -90)
	elif dir.z > 0:
		arrow.rotation_degrees = Vector3(90, 0, 0)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	arrow.material_override = material
	return arrow


## 创建散布的参照物体
func _create_reference_objects() -> void:
	var objects_container := Node3D.new()
	objects_container.name = "ReferenceObjects"
	add_child(objects_container)
	
	# 四个角落的柱子
	var pillar_positions := [
		Vector3(-15, 0, -15),
		Vector3(15, 0, -15),
		Vector3(-15, 0, 15),
		Vector3(15, 0, 15),
	]
	var pillar_colors := [
		Color(0.2, 0.6, 0.8),  # 青色
		Color(0.8, 0.6, 0.2),  # 橙色
		Color(0.6, 0.2, 0.8),  # 紫色
		Color(0.2, 0.8, 0.4),  # 绿色
	]
	
	for i in range(pillar_positions.size()):
		var pillar := _create_pillar(pillar_positions[i], pillar_colors[i], 3.0)
		objects_container.add_child(pillar)
	
	# 中间区域的小物体
	var small_objects := [
		{ "pos": Vector3(-8, 0.5, -8), "color": Color(0.7, 0.7, 0.2), "type": "box" },
		{ "pos": Vector3(8, 0.5, -8), "color": Color(0.2, 0.7, 0.7), "type": "sphere" },
		{ "pos": Vector3(-8, 0.5, 8), "color": Color(0.7, 0.2, 0.7), "type": "cylinder" },
		{ "pos": Vector3(0, 0.5, -12), "color": Color(0.5, 0.5, 0.5), "type": "box" },
		{ "pos": Vector3(0, 0.5, 12), "color": Color(0.6, 0.4, 0.3), "type": "box" },
		{ "pos": Vector3(-12, 0.5, 0), "color": Color(0.3, 0.6, 0.4), "type": "sphere" },
		{ "pos": Vector3(12, 0.5, 0), "color": Color(0.4, 0.3, 0.6), "type": "cylinder" },
	]
	
	for obj_data in small_objects:
		var obj := _create_small_object(obj_data.pos, obj_data.color, obj_data.type)
		objects_container.add_child(obj)


## 创建柱子
func _create_pillar(pos: Vector3, color: Color, height: float) -> MeshInstance3D:
	var pillar := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = height
	pillar.mesh = cylinder
	pillar.position = pos + Vector3(0, height / 2, 0)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	pillar.material_override = material
	return pillar


## 创建小物体
func _create_small_object(pos: Vector3, color: Color, type: String) -> MeshInstance3D:
	var obj := MeshInstance3D.new()
	
	match type:
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(1, 1, 1)
			obj.mesh = box
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			obj.mesh = sphere
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.4
			cylinder.bottom_radius = 0.4
			cylinder.height = 1.0
			obj.mesh = cylinder
	
	obj.position = pos
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	obj.material_override = material
	return obj


func _setup_camera() -> void:
	# 从场景模板实例化相机
	var camera_scene := preload("res://addons/lomolib/camera/lomo_camera_rig.tscn")
	_camera_rig = camera_scene.instantiate() as LomoCameraRig
	_camera_rig.name = "CameraRig"
	_camera_rig.position = Vector3(0, 0, 0)
	add_child(_camera_rig)
	
	# 设置为当前相机
	_camera_rig.make_current()
	
	# 连接信号
	_camera_rig.trace_started.connect(_on_trace_started)
	_camera_rig.trace_stopped.connect(_on_trace_stopped)


func _setup_controller() -> void:
	_controller = LomoPlayerController.new()
	_controller.name = "PlayerController"
	add_child(_controller)
	
	# 绑定相机
	_controller.use_camera_rig(_camera_rig)
	
	# 连接信号
	_controller.ground_clicked.connect(_on_ground_clicked)
	_controller.actor_clicked.connect(_on_actor_clicked)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	
	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.position = Vector2(10, 10)
	_info_label.add_theme_color_override("font_color", Color.WHITE)
	_info_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_info_label)


func _process(delta: float) -> void:
	# 更新信息显示
	_update_info_label()
	
	# 移动目标立方体（用于跟随演示）
	var time := Time.get_ticks_msec() / 1000.0
	_target_cube.position.x = 5 + sin(time * 0.5) * 3
	_target_cube.position.z = 5 + cos(time * 0.5) * 3


func _input(event: InputEvent) -> void:
	# F 键切换跟随模式
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_F:
			if _camera_rig.is_tracing():
				_camera_rig.stop_trace()
			else:
				_camera_rig.begin_trace(_target_cube)


func _update_info_label() -> void:
	var hit_info := _controller.get_hit_info()
	var ground_pos: Vector3 = hit_info.get("ground_position", Vector3.ZERO)
	
	var text := "Camera Demo\n"
	text += "─────────────────\n"
	text += "Zoom: %.1f\n" % _camera_rig.get_zoom()
	text += "Rotation: %.1f°\n" % _camera_rig.get_rotation_degrees().y
	text += "Following: %s\n" % ("Yes" if _camera_rig.is_tracing() else "No")
	text += "─────────────────\n"
	text += "Ground Hit: %s\n" % ("Yes" if hit_info.get("hit_ground", false) else "No")
	text += "Position: (%.1f, %.1f, %.1f)\n" % [ground_pos.x, ground_pos.y, ground_pos.z]
	text += "─────────────────\n"
	text += "Press F to toggle follow"
	
	_info_label.text = text


# ========== 信号处理 ==========

func _on_ground_clicked(position: Vector3, button: MouseButton) -> void:
	var button_name := "Left" if button == MOUSE_BUTTON_LEFT else "Right"
	print("[Demo] %s clicked ground at: %s" % [button_name, position])


func _on_actor_clicked(actor: Node3D, button: MouseButton) -> void:
	var button_name := "Left" if button == MOUSE_BUTTON_LEFT else "Right"
	print("[Demo] %s clicked actor: %s" % [button_name, actor.name])


func _on_trace_started(target: Node3D) -> void:
	print("[Demo] Started following: %s" % target.name)


func _on_trace_stopped() -> void:
	print("[Demo] Stopped following")
