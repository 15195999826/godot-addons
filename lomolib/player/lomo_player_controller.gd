## LomoPlayerController - 通用玩家控制器基类
##
## 从 UE LomoGeneralPlayerController 移植，提供统一的输入管理和射线检测。
##
## 功能：
## - 鼠标状态机（Idle/Press/Pressing/Release）
## - 射线检测（地面/可点击物体）
## - 相机绑定
## - 虚函数供子类重写
##
## 使用方式：
## 1. 继承此类创建具体的 Controller
## 2. 重写 _custom_process() 处理游戏逻辑
## 3. 通过 GameWorld 或场景管理器持有 Controller 引用
class_name LomoPlayerController
extends Node


# ========== 信号 ==========

## 点击地面
signal ground_clicked(position: Vector3, button: MouseButton)

## 点击 Actor
signal actor_clicked(actor: Node3D, button: MouseButton)

## 鼠标悬停在 Actor 上
signal actor_hovered(actor: Node3D)

## 鼠标离开 Actor
signal actor_unhovered(actor: Node3D)


# ========== 鼠标状态枚举 ==========

enum MouseState {
	IDLE,      ## 空闲
	PRESS,     ## 刚按下（单帧）
	PRESSING,  ## 持续按住
	RELEASE,   ## 刚释放（单帧）
}


# ========== 导出属性 ==========

@export_group("Raycast")

## 射线检测的碰撞层（地面）
@export_flags_3d_physics var ground_collision_mask: int = 1

## 射线检测的碰撞层（可点击物体）
@export_flags_3d_physics var clickable_collision_mask: int = 2

## 射线最大距离
@export var ray_length: float = 1000.0


@export_group("Camera")

## 是否自动处理相机输入
@export var auto_handle_camera_input: bool = true


# ========== 内部状态 ==========

## 相机引用
var _camera_rig: LomoCameraRig = null

## 左键状态
var _left_mouse_state: MouseState = MouseState.IDLE

## 右键状态
var _right_mouse_state: MouseState = MouseState.IDLE

## 中键状态
var _middle_mouse_state: MouseState = MouseState.IDLE

## 当前悬停的 Actor
var _hovered_actor: Node3D = null

## 上一帧的射线检测结果
var _last_hit_info: Dictionary = {}

## 是否鼠标在 UI 上
var _is_over_ui: bool = false


# ========== 生命周期 ==========

func _ready() -> void:
	# 设置处理优先级（在其他节点之前处理输入）
	process_priority = -100


func _process(delta: float) -> void:
	_update_mouse_states()
	_process_raycast()
	_process_camera_input(delta)
	_custom_process(delta, _last_hit_info)


func _input(event: InputEvent) -> void:
	# 检测鼠标是否在 UI 上
	if event is InputEventMouse:
		# 简单检测：如果有 Control 节点获取了焦点，认为在 UI 上
		var focused := get_viewport().gui_get_focus_owner()
		_is_over_ui = focused != null


# ========== 虚函数（子类重写）==========

## 自定义处理逻辑（每帧调用）
## @param delta 帧时间
## @param hit_info 射线检测结果 { hit_ground, ground_position, hit_actor, actor }
func _custom_process(delta: float, hit_info: Dictionary) -> void:
	pass


## 重新映射命中位置（用于网格对齐等）
## @param location 原始命中位置
## @return 映射后的位置
func _remap_hit_location(location: Vector3) -> Vector3:
	return location


## 命中地面回调
## @param location 地面位置
func _on_hit_ground(location: Vector3) -> void:
	pass


## 命中 Actor 回调
## @param actor 命中的 Actor
func _on_hit_actor(actor: Node3D) -> void:
	pass


# ========== 鼠标状态管理 ==========

## 更新鼠标状态
func _update_mouse_states() -> void:
	_sample_mouse_state(
		_left_mouse_state,
		Input.is_action_just_pressed("ui_select") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)
	
	_sample_mouse_state(
		_right_mouse_state,
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not _was_right_pressed,
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	)
	_was_right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	
	_sample_mouse_state(
		_middle_mouse_state,
		Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and not _was_middle_pressed,
		Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)
	_was_middle_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)


var _was_right_pressed: bool = false
var _was_middle_pressed: bool = false


## 采样鼠标状态（状态机转换）
func _sample_mouse_state(state: MouseState, just_pressed: bool, is_down: bool) -> MouseState:
	match state:
		MouseState.IDLE:
			if just_pressed:
				return MouseState.PRESS
		MouseState.PRESS:
			if is_down:
				return MouseState.PRESSING
			else:
				return MouseState.RELEASE
		MouseState.PRESSING:
			if not is_down:
				return MouseState.RELEASE
		MouseState.RELEASE:
			return MouseState.IDLE
	return state


## 获取左键状态
func get_left_mouse_state() -> MouseState:
	return _left_mouse_state


## 获取右键状态
func get_right_mouse_state() -> MouseState:
	return _right_mouse_state


## 获取中键状态
func get_middle_mouse_state() -> MouseState:
	return _middle_mouse_state


## 左键是否刚按下
func is_left_just_pressed() -> bool:
	return _left_mouse_state == MouseState.PRESS


## 右键是否刚按下
func is_right_just_pressed() -> bool:
	return _right_mouse_state == MouseState.PRESS


## 左键是否持续按住
func is_left_pressing() -> bool:
	return _left_mouse_state == MouseState.PRESSING or _left_mouse_state == MouseState.PRESS


## 右键是否持续按住
func is_right_pressing() -> bool:
	return _right_mouse_state == MouseState.PRESSING or _right_mouse_state == MouseState.PRESS


# ========== 射线检测 ==========

## 处理射线检测
func _process_raycast() -> void:
	var camera := _get_active_camera()
	if camera == null:
		_last_hit_info = {}
		return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * ray_length
	
	var space_state := camera.get_world_3d().direct_space_state
	
	# 检测地面
	var ground_query := PhysicsRayQueryParameters3D.create(from, to, ground_collision_mask)
	var ground_result := space_state.intersect_ray(ground_query)
	
	# 检测可点击物体
	var clickable_query := PhysicsRayQueryParameters3D.create(from, to, clickable_collision_mask)
	var clickable_result := space_state.intersect_ray(clickable_query)
	
	# 构建结果
	_last_hit_info = {
		"hit_ground": not ground_result.is_empty(),
		"ground_position": ground_result.get("position", Vector3.ZERO),
		"hit_actor": not clickable_result.is_empty(),
		"actor": clickable_result.get("collider", null),
		"actor_position": clickable_result.get("position", Vector3.ZERO),
	}
	
	# 处理地面命中
	if _last_hit_info.hit_ground:
		var remapped_pos := _remap_hit_location(_last_hit_info.ground_position)
		_last_hit_info.ground_position = remapped_pos
		_on_hit_ground(remapped_pos)
	
	# 处理 Actor 悬停
	var current_actor: Node3D = _last_hit_info.get("actor")
	if current_actor != _hovered_actor:
		if _hovered_actor != null:
			actor_unhovered.emit(_hovered_actor)
		if current_actor != null:
			actor_hovered.emit(current_actor)
			_on_hit_actor(current_actor)
		_hovered_actor = current_actor
	
	# 处理点击
	if not _is_over_ui:
		if is_left_just_pressed():
			if _last_hit_info.hit_actor:
				actor_clicked.emit(_last_hit_info.actor, MOUSE_BUTTON_LEFT)
			elif _last_hit_info.hit_ground:
				ground_clicked.emit(_last_hit_info.ground_position, MOUSE_BUTTON_LEFT)
		
		if is_right_just_pressed():
			if _last_hit_info.hit_actor:
				actor_clicked.emit(_last_hit_info.actor, MOUSE_BUTTON_RIGHT)
			elif _last_hit_info.hit_ground:
				ground_clicked.emit(_last_hit_info.ground_position, MOUSE_BUTTON_RIGHT)


## 获取当前射线检测结果
func get_hit_info() -> Dictionary:
	return _last_hit_info


## 获取当前悬停的 Actor
func get_hovered_actor() -> Node3D:
	return _hovered_actor


# ========== 相机控制 ==========

## 处理相机输入
func _process_camera_input(delta: float) -> void:
	if not auto_handle_camera_input:
		return
	
	if _camera_rig == null:
		return
	
	# WASD / 方向键移动
	var move_input := Vector2.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_input.y += 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_input.y -= 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_input.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_input.x += 1
	
	if move_input != Vector2.ZERO:
		_camera_rig.move(move_input.normalized())
	
	# Q/E 旋转
	if Input.is_key_pressed(KEY_Q):
		_camera_rig.rotate_camera(-1)
	if Input.is_key_pressed(KEY_E):
		_camera_rig.rotate_camera(1)
	
	# 中键拖拽旋转
	if _middle_mouse_state == MouseState.PRESSING:
		var mouse_delta := Input.get_last_mouse_velocity()
		if absf(mouse_delta.x) > 0.1:
			_camera_rig.rotate_camera(mouse_delta.x * 0.001)
	
	# 滚轮缩放
	# 注意：滚轮输入需要在 _input 中处理


func _unhandled_input(event: InputEvent) -> void:
	if not auto_handle_camera_input:
		return
	
	if _camera_rig == null:
		return
	
	# 滚轮缩放
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_camera_rig.zoom(1)
			elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_camera_rig.zoom(-1)
	
	# 空格重置相机
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_SPACE:
			_camera_rig.reset_camera()


# ========== 相机绑定 ==========

## 绑定相机
func use_camera_rig(rig: LomoCameraRig) -> void:
	_camera_rig = rig
	if rig != null:
		rig.make_current()
		Log.info("LomoPlayerController", "Camera rig bound: %s" % rig.name)


## 获取绑定的相机
func get_camera_rig() -> LomoCameraRig:
	return _camera_rig


## 获取当前活跃的 Camera3D
func _get_active_camera() -> Camera3D:
	if _camera_rig != null:
		return _camera_rig.get_camera()
	
	# 回退到 Viewport 的当前相机
	return get_viewport().get_camera_3d()


# ========== 工具方法 ==========

## 检查鼠标是否在 UI 上
func is_over_ui() -> bool:
	return _is_over_ui


## 获取鼠标世界位置（地面）
func get_mouse_world_position() -> Vector3:
	if _last_hit_info.get("hit_ground", false):
		return _last_hit_info.ground_position
	return Vector3.ZERO


## 屏幕坐标转世界坐标（在指定平面上）
func screen_to_world_on_plane(screen_pos: Vector2, plane: Plane = Plane(Vector3.UP, 0)) -> Vector3:
	var camera := _get_active_camera()
	if camera == null:
		return Vector3.ZERO
	
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	
	var intersection := plane.intersects_ray(from, dir)
	if intersection != null:
		return intersection
	
	return Vector3.ZERO
