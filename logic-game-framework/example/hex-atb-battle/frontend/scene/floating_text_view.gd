## FloatingTextView - 飘字视图
##
## 显示伤害/治疗数字的飘字效果
class_name FrontendFloatingTextView
extends Node3D


# ========== 信号 ==========

## 动画完成
signal animation_finished()


# ========== 属性 ==========

var _label: Label3D
var _start_position: Vector3
var _duration: float = 1000.0
var _elapsed: float = 0.0
var _style: int = 0  # FloatingTextStyle


# ========== 初始化 ==========

func _ready() -> void:
	_create_label()


func _create_label() -> void:
	_label = Label3D.new()
	_label.pixel_size = 0.015
	_label.font_size = 48
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 4
	
	add_child(_label)


# ========== 公共方法 ==========

## 初始化飘字
func initialize(p_text: String, p_color: Color, world_position: Vector3, p_style: int, p_duration: float) -> void:
	_start_position = world_position
	_duration = p_duration
	_style = p_style
	_elapsed = 0.0
	
	position = world_position
	
	if _label:
		_label.text = p_text
		_label.modulate = p_color
		
		# 根据样式调整大小
		match p_style:
			FrontendFloatingTextAction.FloatingTextStyle.CRITICAL:
				_label.font_size = 64
			FrontendFloatingTextAction.FloatingTextStyle.HEAL:
				_label.font_size = 48
			_:
				_label.font_size = 48


func _process(delta: float) -> void:
	_elapsed += delta * 1000.0
	
	var progress := _elapsed / _duration
	
	if progress >= 1.0:
		animation_finished.emit()
		queue_free()
		return
	
	# 上升动画
	var rise_height := 1.0
	position = _start_position + Vector3(0, rise_height * progress, 0)
	
	# 淡出
	if _label:
		var alpha := 1.0 - progress
		_label.modulate.a = alpha
	
	# 缩放效果（暴击）
	if _style == FrontendFloatingTextAction.FloatingTextStyle.CRITICAL:
		var scale_factor := 1.0 + 0.3 * sin(progress * PI)
		scale = Vector3.ONE * scale_factor
