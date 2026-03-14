## ReplayControls - 回放控制 UI
##
## 提供播放/暂停/重置/速度控制
class_name FrontendReplayControls
extends Control


# ========== 信号 ==========

signal play_pressed()
signal pause_pressed()
signal reset_pressed()
signal speed_changed(speed: float)


# ========== 节点引用 ==========

var _play_button: Button
var _pause_button: Button
var _reset_button: Button
var _speed_slider: HSlider
var _speed_label: Label
var _frame_label: Label
var _status_label: Label


# ========== 初始化 ==========

func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# 创建容器
	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	add_child(vbox)
	
	# 标题
	var title := Label.new()
	title.text = "Battle Replay"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# 状态标签
	_status_label = Label.new()
	_status_label.text = "Status: Stopped"
	vbox.add_child(_status_label)
	
	# 帧标签
	_frame_label = Label.new()
	_frame_label.text = "Frame: 0 / 0"
	vbox.add_child(_frame_label)
	
	# 按钮容器
	var button_container := HBoxContainer.new()
	vbox.add_child(button_container)
	
	# 播放按钮
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_on_play_pressed)
	button_container.add_child(_play_button)
	
	# 暂停按钮
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.pressed.connect(_on_pause_pressed)
	button_container.add_child(_pause_button)
	
	# 重置按钮
	_reset_button = Button.new()
	_reset_button.text = "Reset"
	_reset_button.pressed.connect(_on_reset_pressed)
	button_container.add_child(_reset_button)
	
	# 速度控制
	var speed_container := HBoxContainer.new()
	vbox.add_child(speed_container)
	
	var speed_title := Label.new()
	speed_title.text = "Speed: "
	speed_container.add_child(speed_title)
	
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.25
	_speed_slider.max_value = 4.0
	_speed_slider.step = 0.25
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size = Vector2(100, 0)
	_speed_slider.value_changed.connect(_on_speed_changed)
	speed_container.add_child(_speed_slider)
	
	_speed_label = Label.new()
	_speed_label.text = "1.0x"
	speed_container.add_child(_speed_label)


# ========== 公共方法 ==========

## 更新播放状态
func update_playback_state(is_playing: bool) -> void:
	_status_label.text = "Status: " + ("Playing" if is_playing else "Paused")
	_play_button.disabled = is_playing
	_pause_button.disabled = not is_playing


## 更新帧信息
func update_frame_info(p_current_frame: int, p_total_frames: int) -> void:
	_frame_label.text = "Frame: %d / %d" % [p_current_frame, p_total_frames]


## 设置播放结束状态
func set_ended_state() -> void:
	_status_label.text = "Status: Ended"
	_play_button.disabled = true
	_pause_button.disabled = true


# ========== 信号处理 ==========

func _on_play_pressed() -> void:
	play_pressed.emit()


func _on_pause_pressed() -> void:
	pause_pressed.emit()


func _on_reset_pressed() -> void:
	reset_pressed.emit()


func _on_speed_changed(value: float) -> void:
	_speed_label.text = "%.2fx" % value
	speed_changed.emit(value)
