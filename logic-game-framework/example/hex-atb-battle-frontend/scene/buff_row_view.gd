## BuffRowView - buff 头顶图标行子组件
##
## UnitView 的 attached visual 之一,响应 update_from_state 同步 actor.buffs 数组,
## 维护一行"小色块 + 文字摘要"展示 buff 状态。
##
## 入场动画(0.15s scale.x 0→1)只在 ADD 时触发;数值变化(stacks-1 / shield 吸收)
## 静默更新文字,不弹动画(避免 Poison tick / 频繁吸收引起的视觉吵闹)。
##
## 实现行为完全沿用从 UnitView._sync_buff_row 搬过来的逻辑,无视觉变更。
class_name FrontendBuffRowView
extends Node3D


@export var buff_row_offset: float = 0.95
@export var buff_block_width: float = 0.18
@export var buff_block_height: float = 0.06
@export var buff_block_spacing: float = 0.04


var _buff_label: Label3D
## key = buff.id,value = MeshInstance3D。GDScript Dictionary 是 insertion-ordered,
## 直接用 keys() 获取首次 ADD 顺序,避免重排闪动。
var _buff_blocks: Dictionary = {}


func _ready() -> void:
	_buff_label = Label3D.new()
	_buff_label.position = Vector3(0.0, buff_row_offset - buff_block_height - 0.04, 0.0)
	_buff_label.pixel_size = 0.006
	_buff_label.font_size = 24
	_buff_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_buff_label.no_depth_test = true
	_buff_label.modulate = Color.WHITE
	_buff_label.text = ""
	add_child(_buff_label)


func update_from_state(state: FrontendActorRenderState) -> void:
	_sync_buff_row(state.buffs)


## 暴露给 smoke 测试用,避免 poke 内部 _buff_label 字段。
func get_label_text() -> String:
	if _buff_label == null:
		return ""
	return _buff_label.text


func _sync_buff_row(buffs: Array) -> void:
	if buffs.is_empty() and _buff_blocks.is_empty():
		return

	var current_ids: Dictionary = {}
	for b in buffs:
		current_ids[b.id] = b

	var to_remove: Array[String] = []
	for buff_id in _buff_blocks.keys():
		if not current_ids.has(buff_id):
			to_remove.append(buff_id)
	for buff_id in to_remove:
		var dead_node: MeshInstance3D = _buff_blocks[buff_id]
		if is_instance_valid(dead_node):
			dead_node.queue_free()
		_buff_blocks.erase(buff_id)

	for buff_id in current_ids.keys():
		if _buff_blocks.has(buff_id):
			continue
		var summary = current_ids[buff_id]
		var block := _create_buff_block(summary.color)
		_buff_blocks[buff_id] = block
		add_child(block)
		block.scale.x = 0.0
		create_tween().tween_property(block, "scale:x", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var ordered_ids: Array = _buff_blocks.keys()
	var n := ordered_ids.size()
	var step := buff_block_width + buff_block_spacing
	var total_width := step * n - buff_block_spacing
	var start_x := -total_width * 0.5 + buff_block_width * 0.5
	var parts: Array[String] = []
	for i in range(n):
		var bid: String = ordered_ids[i]
		var node: MeshInstance3D = _buff_blocks[bid]
		node.position = Vector3(start_x + step * i, buff_row_offset, 0.0)
		var s = current_ids[bid]
		if s.primary > 0.0:
			parts.append("%s%d" % [s.short, int(s.primary)])
		else:
			parts.append(s.short)
	if _buff_label != null:
		_buff_label.text = " ".join(parts)


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
