## UnitView - 单位视图
##
## 3D 单位的视觉表现，包含：
## - 球体网格（代表单位）
## - 血条
## - 名称标签
class_name FrontendUnitView
extends Node3D


# ========== 信号 ==========

## 死亡动画完成
signal death_animation_finished(actor_id: String)


# ========== 导出属性 ==========

## 单位半径
@export var unit_radius: float = 0.5

## 血条高度偏移
@export var hp_bar_offset: float = 1.2

## 名称标签高度偏移
@export var name_label_offset: float = 1.5


# ========== 节点引用 ==========

var _mesh_instance: MeshInstance3D
var _hp_bar: ProgressBar
var _name_label: Label3D


# ========== 状态 ==========

var _actor_id: String = ""
var _team: int = 0
var _max_hp: float = 100.0
var _current_hp: float = 100.0
var _is_alive: bool = true
var _flash_progress: float = 0.0
var _base_material: StandardMaterial3D
var _target_position: Vector3 = Vector3.ZERO
var _death_tween: Tween  # 死亡动画 Tween (修复 C3)


# ========== 初始化 ==========

func _ready() -> void:
	_create_mesh()
	_create_hp_bar()
	_create_name_label()
	_target_position = position


func _process(delta: float) -> void:
	# 平滑插值到目标位置
	position = position.lerp(_target_position, delta * 15.0)


## 创建球体网格
func _create_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	
	var sphere := SphereMesh.new()
	sphere.radius = unit_radius
	sphere.height = unit_radius * 2.0
	_mesh_instance.mesh = sphere
	
	# 创建材质
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = Color.WHITE
	_mesh_instance.material_override = _base_material
	
	add_child(_mesh_instance)


## 创建血条
func _create_hp_bar() -> void:
	# 使用 Label3D 显示血条（简化实现）
	# 实际项目中可以使用 SubViewport + Control 实现更复杂的血条
	_hp_bar = null  # 暂时不创建复杂的血条
	
	# 简单的血条实现：使用另一个扁平的 MeshInstance3D
	var hp_bar_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.1, 0.1)
	hp_bar_mesh.mesh = box
	hp_bar_mesh.position = Vector3(0, hp_bar_offset, 0)
	
	var hp_material := StandardMaterial3D.new()
	hp_material.albedo_color = Color.GREEN
	hp_bar_mesh.material_override = hp_material
	hp_bar_mesh.name = "HPBar"
	
	add_child(hp_bar_mesh)


## 创建名称标签
func _create_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.position = Vector3(0, name_label_offset, 0)
	_name_label.pixel_size = 0.01
	_name_label.font_size = 32
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.modulate = Color.WHITE
	
	add_child(_name_label)


# ========== 公共方法 ==========

## 初始化单位
func initialize(p_actor_id: String, display_name: String, team: int, max_hp: float, current_hp: float) -> void:
	_actor_id = p_actor_id
	_team = team
	_max_hp = max_hp
	_current_hp = current_hp
	_is_alive = current_hp > 0
	
	# 设置名称
	if _name_label:
		_name_label.text = display_name
	
	# 设置队伍颜色
	_update_team_color()
	
	# 更新血条
	_update_hp_bar()


## 获取 Actor ID
func get_actor_id() -> String:
	return _actor_id


## 更新状态
func update_state(new_state: FrontendActorRenderState) -> void:
	_current_hp = new_state.visual_hp
	_is_alive = new_state.is_alive
	_flash_progress = new_state.flash_progress
	
	_update_hp_bar()
	_update_flash_effect(new_state.flash_progress)
	_update_tint_color(new_state.tint_color)
	
	# 处理死亡
	if not _is_alive:
		_play_death_animation()


## 设置世界位置
func set_world_position(new_world_pos: Vector3) -> void:
	_target_position = new_world_pos


# ========== 内部方法 ==========

## 更新队伍颜色
func _update_team_color() -> void:
	if _base_material:
		if _team == 0:
			_base_material.albedo_color = Color(0.2, 0.6, 1.0)  # 蓝色
		else:
			_base_material.albedo_color = Color(1.0, 0.3, 0.3)  # 红色


## 更新血条
func _update_hp_bar() -> void:
	var hp_bar_node := get_node_or_null("HPBar") as MeshInstance3D
	if hp_bar_node:
		var hp_ratio := _current_hp / _max_hp if _max_hp > 0 else 0.0
		hp_bar_node.scale.x = maxf(0.01, hp_ratio)
		
		# 更新颜色
		var material := hp_bar_node.material_override as StandardMaterial3D
		if material:
			if hp_ratio > 0.5:
				material.albedo_color = Color.GREEN
			elif hp_ratio > 0.25:
				material.albedo_color = Color.YELLOW
			else:
				material.albedo_color = Color.RED


## 更新闪白效果
func _update_flash_effect(flash_progress: float) -> void:
	if _base_material:
		var base_color := Color(0.2, 0.6, 1.0) if _team == 0 else Color(1.0, 0.3, 0.3)
		var flash_color := Color.WHITE
		_base_material.albedo_color = base_color.lerp(flash_color, flash_progress)


## 更新染色
func _update_tint_color(tint_color: Color) -> void:
	if _base_material and tint_color != Color.WHITE:
		_base_material.albedo_color = _base_material.albedo_color.blend(tint_color)


## 播放死亡动画
func _play_death_animation() -> void:
	# 防止重复创建 Tween
	if _death_tween and _death_tween.is_running():
		return
	
	_death_tween = create_tween()
	_death_tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.5)
	_death_tween.parallel().tween_property(self, "position:y", position.y - 0.5, 0.5)
	_death_tween.tween_callback(_on_death_animation_finished)


func _on_death_animation_finished() -> void:
	death_animation_finished.emit(_actor_id)
	visible = false


func _exit_tree() -> void:
	# 清理死亡动画 Tween
	if _death_tween:
		_death_tween.kill()
