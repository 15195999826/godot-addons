## LomoCameraRig - 弹簧臂相机组件
##
## 从 UE SpringArmCameraActor 移植，提供 RTS/战棋风格的相机控制。
##
## 功能：
## - 弹簧臂平滑距离控制（缩放）
## - Yaw 旋转（保持俯视角度）
## - WASD/方向键移动
## - 目标跟随（平滑插值）
## - 重置到默认视角
##
## 使用方式：
## 1. 实例化场景模板 lomo_camera_rig.tscn
## 2. 或代码创建：var rig = LomoCameraRig.new(); add_child(rig); rig.setup()
class_name LomoCameraRig
extends Node3D


# ========== 信号 ==========

## 相机位置变化
signal position_changed(world_position: Vector3)

## 缩放变化
signal zoom_changed(zoom_level: float)

## 开始跟随目标
signal trace_started(target: Node3D)

## 停止跟随
signal trace_stopped()


# ========== 导出属性 - 缩放 ==========

@export_group("Zoom")

## 默认臂长（缩放距离）
@export var default_arm_length: float = 15.0

## 最小缩放距离
@export var min_zoom: float = 5.0

## 最大缩放距离
@export var max_zoom: float = 50.0

## 缩放速度（每次滚轮的变化量）
@export var zoom_step: float = 2.0

## 缩放插值速度
@export var zoom_lerp_speed: float = 10.0


# ========== 导出属性 - 旋转 ==========

@export_group("Rotation")

## 默认俯视角度（Pitch）
@export_range(-89.0, 0.0) var default_pitch: float = -50.0

## 默认水平角度（Yaw）
@export var default_yaw: float = 0.0

## 旋转速度（度/秒）
@export var rotate_speed: float = 90.0


# ========== 导出属性 - 移动 ==========

@export_group("Movement")

## 移动速度（单位/秒）
@export var move_speed: float = 20.0

## 移动插值速度
@export var move_lerp_speed: float = 5.0


# ========== 导出属性 - 跟随 ==========

@export_group("Follow")

## 跟随偏移（相对于目标）
@export var follow_offset: Vector3 = Vector3(0, 0, 0)

## 跟随插值速度
@export var follow_lerp_speed: float = 3.0

## 是否平滑跟随
@export var smooth_follow: bool = true


# ========== 内部节点引用 ==========

var _spring_arm: SpringArm3D
var _camera: Camera3D


# ========== 内部状态 ==========

## 目标位置（用于平滑移动）
var _desired_position: Vector3 = Vector3.ZERO

## 目标缩放
var _desired_zoom: float = 15.0

## 当前缩放
var _current_zoom: float = 15.0

## 跟随目标
var _trace_target: Node3D = null

## 是否正在跟随
var _is_tracing: bool = false

## 默认旋转（用于重置）
var _default_rotation: Vector3 = Vector3.ZERO


# ========== 生命周期 ==========

func _ready() -> void:
	# 如果是从场景实例化，节点已存在
	_spring_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	_camera = get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	
	# 如果节点不存在，说明是代码创建的，需要调用 setup()
	if _spring_arm == null:
		push_warning("[LomoCameraRig] SpringArm3D not found. Call setup() to create nodes.")
		return
	
	_initialize()


## 代码创建时调用，设置节点结构
func setup() -> void:
	if _spring_arm != null:
		push_warning("[LomoCameraRig] Already setup.")
		return
	
	# 创建 SpringArm3D
	_spring_arm = SpringArm3D.new()
	_spring_arm.name = "SpringArm3D"
	add_child(_spring_arm)
	
	# 创建 Camera3D
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_spring_arm.add_child(_camera)
	
	_initialize()


## 初始化状态
func _initialize() -> void:
	# 设置默认值
	_desired_zoom = default_arm_length
	_current_zoom = default_arm_length
	_spring_arm.spring_length = default_arm_length
	
	# 设置默认旋转
	_default_rotation = Vector3(default_pitch, default_yaw, 0)
	_spring_arm.rotation_degrees = _default_rotation
	
	# 禁用碰撞检测（RTS 相机通常不需要）
	_spring_arm.collision_mask = 0
	
	# 记录初始位置
	_desired_position = global_position


func _process(delta: float) -> void:
	if _spring_arm == null:
		return
	
	_process_tracing(delta)
	_process_movement(delta)
	_process_zoom(delta)


## 处理跟随逻辑
func _process_tracing(delta: float) -> void:
	if not _is_tracing or _trace_target == null:
		return
	
	# 检查目标是否有效
	if not is_instance_valid(_trace_target):
		stop_trace()
		return
	
	# 计算目标位置
	var target_pos := _trace_target.global_position + follow_offset
	
	if smooth_follow:
		_desired_position = _desired_position.lerp(target_pos, delta * follow_lerp_speed)
	else:
		_desired_position = target_pos


## 处理移动插值
func _process_movement(delta: float) -> void:
	if _is_tracing:
		# 跟随模式下直接使用 _desired_position
		global_position = global_position.lerp(_desired_position, delta * move_lerp_speed)
	else:
		# 自由移动模式
		global_position = global_position.lerp(_desired_position, delta * move_lerp_speed)
	
	# 发送位置变化信号（仅当变化显著时）
	if global_position.distance_to(_desired_position) > 0.01:
		position_changed.emit(global_position)


## 处理缩放插值
func _process_zoom(delta: float) -> void:
	if absf(_current_zoom - _desired_zoom) < 0.01:
		return
	
	_current_zoom = lerpf(_current_zoom, _desired_zoom, delta * zoom_lerp_speed)
	_spring_arm.spring_length = _current_zoom
	zoom_changed.emit(_current_zoom)


# ========== 公共方法 - 移动 ==========

## 移动相机（相对于当前朝向）
func move(direction: Vector2) -> void:
	if _is_tracing:
		# 跟随模式下忽略移动输入
		return
	
	# 获取当前 Yaw 旋转
	var yaw := _spring_arm.rotation.y
	var yaw_rotation := Basis(Vector3.UP, yaw)
	
	# 计算世界空间的移动方向
	var forward := yaw_rotation * Vector3.FORWARD
	var right := yaw_rotation * Vector3.RIGHT
	
	var movement := (forward * direction.y + right * direction.x) * move_speed * get_process_delta_time()
	_desired_position += movement


## 直接设置目标位置
func set_desired_position(pos: Vector3) -> void:
	_desired_position = pos


## 立即移动到指定位置（无插值）
func teleport_to(pos: Vector3) -> void:
	_desired_position = pos
	global_position = pos


## 观察指定位置（重置相机并移动到该位置）
func watch_position(pos: Vector3) -> void:
	reset_camera()
	_desired_position = pos


# ========== 公共方法 - 缩放 ==========

## 缩放（正值放大/拉近，负值缩小/拉远）
func zoom(amount: float) -> void:
	_desired_zoom = clampf(_desired_zoom - amount * zoom_step, min_zoom, max_zoom)


## 设置缩放级别
func set_zoom(level: float) -> void:
	_desired_zoom = clampf(level, min_zoom, max_zoom)


## 获取当前缩放级别
func get_zoom() -> float:
	return _current_zoom


# ========== 公共方法 - 旋转 ==========

## 旋转相机（Yaw）
func rotate_camera(amount: float) -> void:
	if _spring_arm == null:
		return
	
	var current_rotation := _spring_arm.rotation_degrees
	current_rotation.y += amount * rotate_speed * get_process_delta_time()
	_spring_arm.rotation_degrees = current_rotation


## 设置旋转角度
func set_camera_rotation_degrees(pitch: float, yaw: float) -> void:
	if _spring_arm == null:
		return
	
	_spring_arm.rotation_degrees = Vector3(
		clampf(pitch, -89.0, 0.0),
		yaw,
		0
	)


## 获取当前旋转
func get_rotation_degrees() -> Vector3:
	if _spring_arm == null:
		return Vector3.ZERO
	return _spring_arm.rotation_degrees


# ========== 公共方法 - 跟随 ==========

## 开始跟随目标
func begin_trace(target: Node3D) -> void:
	if target == null:
		push_warning("[LomoCameraRig] Cannot trace null target.")
		return
	
	_trace_target = target
	_is_tracing = true
	trace_started.emit(target)
	
	print("[LomoCameraRig] Begin tracing: %s" % target.name)


## 停止跟随
func stop_trace() -> void:
	if not _is_tracing:
		return
	
	_trace_target = null
	_is_tracing = false
	trace_stopped.emit()
	
	print("[LomoCameraRig] Stop tracing")


## 是否正在跟随
func is_tracing() -> bool:
	return _is_tracing


## 获取跟随目标
func get_trace_target() -> Node3D:
	return _trace_target


# ========== 公共方法 - 重置 ==========

## 重置相机到默认状态
func reset_camera() -> void:
	if _spring_arm == null:
		return
	
	# 重置旋转
	_spring_arm.rotation_degrees = _default_rotation
	
	# 重置缩放
	_desired_zoom = default_arm_length
	
	# 停止跟随
	stop_trace()


# ========== 公共方法 - 访问器 ==========

## 获取 Camera3D 节点
func get_camera() -> Camera3D:
	return _camera


## 获取 SpringArm3D 节点
func get_spring_arm() -> SpringArm3D:
	return _spring_arm


## 设置为当前相机
func make_current() -> void:
	if _camera != null:
		_camera.make_current()


## 是否是当前相机
func is_current() -> bool:
	if _camera == null:
		return false
	return _camera.is_current()
