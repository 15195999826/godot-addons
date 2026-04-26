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

## buff 行高度偏移(在血条下方)
@export var buff_row_offset: float = 0.95

## 每个 buff 色块的尺寸(meters)
@export var buff_block_width: float = 0.18
@export var buff_block_height: float = 0.06
@export var buff_block_spacing: float = 0.04


# ========== 节点引用 ==========

var _mesh_instance: MeshInstance3D
var _hp_bar: ProgressBar
var _name_label: Label3D
var _buff_label: Label3D
## 已渲染的 buff 块,key = buff.id,value = MeshInstance3D。
## 池化复用:同一 buff 的 mesh 在多次 update_state 之间稳定。
## 顺序由 _buff_order 数组维护(按首次 ADD 顺序),避免 Dictionary 遍历乱序导致重排。
var _buff_blocks: Dictionary = {}
## buff.id 的稳定显示顺序(按出现顺序 append),消失时从中移除。
var _buff_order: Array[String] = []


# ========== 状态 ==========

var _actor_id: String = ""
var _team: int = 0
var _max_hp: float = 100.0
var _current_hp: float = 100.0
var _is_alive: bool = true
var _flash_progress: float = 0.0
var _base_material: StandardMaterial3D
var _target_position: Vector3 = Vector3.ZERO
var _death_tween: Tween
## 死亡动画 once 策略 flag。play_death() 是 transition event 入口,但同一战斗内
## 的非战斗事件(动画系统重入 / debug 重 wire)仍可能触发多次,view 自己挡 once。
var _death_played: bool = false


# ========== 初始化 ==========

func _ready() -> void:
	_create_mesh()
	_create_hp_bar()
	_create_name_label()
	_create_buff_label()
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


## 创建 buff 文字行(Label3D,billboard,显示 "P3 S20 T" 这种紧凑文字)。
## 色块 mesh 由 _sync_buff_row 按需创建/回收。
func _create_buff_label() -> void:
	_buff_label = Label3D.new()
	_buff_label.position = Vector3(0, buff_row_offset - buff_block_height - 0.04, 0)
	_buff_label.pixel_size = 0.006
	_buff_label.font_size = 24
	_buff_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_buff_label.no_depth_test = true
	_buff_label.modulate = Color.WHITE
	_buff_label.text = ""
	add_child(_buff_label)


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


## 同步可覆盖 state(hp / flash / tint)。一次性动画(死亡 / 复活)走 play_death /
## revive 公共方法,不在这里推断 transition。
func update_state(new_state: FrontendActorRenderState) -> void:
	_current_hp = new_state.visual_hp
	_is_alive = new_state.is_alive
	_flash_progress = new_state.flash_progress

	_update_hp_bar()
	_update_flash_effect(new_state.flash_progress)
	_update_tint_color(new_state.tint_color)
	_sync_buff_row(new_state.buffs)


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


## 同步 buff 行(色块 + 文字)。
##
## 顺序契约:_buff_order 维护"首次 ADD 顺序",新 buff append 到末尾,旧 buff
## 消失时从中间移除 — 已存在的 buff 位置不变,避免 UI 重排闪动。
##
## 入场动画(0.15s scale.x 0→1)只在新增时触发;数值变化(stacks-1 / shield 吸收)
## 静默更新文字,不弹动画(避免 Poison tick / 频繁吸收引起的视觉吵闹)。
func _sync_buff_row(buffs: Array) -> void:
	# 1. 收集本帧 id → summary
	var current_ids: Dictionary = {}
	for b in buffs:
		current_ids[b.id] = b

	# 2. 移除消失的 buff(从 _buff_order 和 _buff_blocks 同步删)
	var to_remove: Array[String] = []
	for buff_id in _buff_order:
		if not current_ids.has(buff_id):
			to_remove.append(buff_id)
	for buff_id in to_remove:
		_buff_order.erase(buff_id)
		var node: MeshInstance3D = _buff_blocks.get(buff_id)
		if node != null and is_instance_valid(node):
			node.queue_free()
		_buff_blocks.erase(buff_id)

	# 3. 新增的 buff append 到 _buff_order 末尾;创建 mesh + 入场动画
	for buff_id in current_ids.keys():
		if _buff_order.has(buff_id):
			continue
		_buff_order.append(buff_id)
		var summary = current_ids[buff_id]
		var block := _create_buff_block(summary.color)
		_buff_blocks[buff_id] = block
		add_child(block)
		# 入场:scale.x 从 0 弹到 1
		block.scale.x = 0.0
		var tween := create_tween()
		tween.tween_property(block, "scale:x", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 4. 重排所有 block 的 x 位置(按 _buff_order 顺序居中排列)
	var n := _buff_order.size()
	if n > 0:
		var step := buff_block_width + buff_block_spacing
		var total_width := step * n - buff_block_spacing
		var start_x := -total_width * 0.5 + buff_block_width * 0.5
		for i in range(n):
			var bid: String = _buff_order[i]
			var node: MeshInstance3D = _buff_blocks.get(bid)
			if node != null:
				node.position = Vector3(start_x + step * i, buff_row_offset, 0.0)

	# 5. 更新文字行(按顺序拼接 "短标识+数字",带颜色丢失,因 Label3D 不支持 BBCode)
	var parts: Array[String] = []
	for buff_id in _buff_order:
		var s = current_ids[buff_id]
		if s.primary > 0.0:
			parts.append("%s%d" % [s.short, int(s.primary)])
		else:
			parts.append(s.short)
	if _buff_label != null:
		_buff_label.text = " ".join(parts)


## 创建一个 buff 色块 mesh
func _create_buff_block(block_color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(buff_block_width, buff_block_height, 0.04)
	node.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = block_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	return node


## 更新染色
func _update_tint_color(tint_color: Color) -> void:
	if _base_material and tint_color != Color.WHITE:
		_base_material.albedo_color = _base_material.albedo_color.blend(tint_color)


## 播放死亡动画(once 策略)。已播过则忽略 — 用于 transition event 入口,调方
## (BattleAnimator._on_actor_died)不需要做幂等。
func play_death() -> void:
	if _death_played:
		return
	_death_played = true
	_death_tween = create_tween()
	_death_tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.5)
	_death_tween.parallel().tween_property(self, "position:y", position.y - 0.5, 0.5)
	_death_tween.tween_callback(_on_death_animation_finished)


## 复活:取消死亡 tween,恢复 visible/scale,清 once flag 让下次 play_death 可再起播。
## 由 Animator.reset() 在 playback session control 路径上遍历 view 调用,
## 不通过 Director event(reset 是 session 控制,不是战斗内复活)。
func revive() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	visible = true
	scale = Vector3.ONE
	_death_played = false


func _on_death_animation_finished() -> void:
	death_animation_finished.emit(_actor_id)
	visible = false


func _exit_tree() -> void:
	# 清理死亡动画 Tween
	if _death_tween:
		_death_tween.kill()
