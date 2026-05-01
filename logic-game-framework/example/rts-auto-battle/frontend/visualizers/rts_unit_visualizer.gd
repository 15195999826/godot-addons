## RtsUnitVisualizer - 单位最简识别 stub
##
## Node2D, 按 team_id 染色(左红右蓝), 圆形(8 边凸 polygon)+ 上方 hp 文本。
## 不做动画 / 攻击特效 / HUD / 相机控制 — 只负责把 actor.position_2d / hp 状态 sync 出来给肉眼看。
##
## frontend demo / tests 在每帧调 sync(actor)。死亡的 actor 由 demo 自己 queue_free 后清掉。
class_name RtsUnitVisualizer
extends Node2D


const RADIUS: float = 12.0
const POLYGON_SEGMENTS: int = 8


var _polygon: Polygon2D = null
var _hp_label: Label = null
var actor: RtsUnitActor = null


func _ready() -> void:
	_polygon = Polygon2D.new()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(POLYGON_SEGMENTS):
		var angle := TAU * float(i) / float(POLYGON_SEGMENTS)
		pts.append(Vector2(cos(angle), sin(angle)) * RADIUS)
	_polygon.polygon = pts
	add_child(_polygon)

	_hp_label = Label.new()
	_hp_label.position = Vector2(-20.0, -RADIUS - 18.0)
	_hp_label.add_theme_font_size_override("font_size", 12)
	add_child(_hp_label)


# ========== 绑定 ==========

func bind_actor(p_actor: RtsUnitActor) -> void:
	actor = p_actor
	position = p_actor.position_2d
	_polygon.color = _team_color(p_actor.get_team_id())
	_update_hp_label()


# ========== Tick sync ==========

## 由 demo `_process` 每帧调用 sync 位置和 hp 文本。
func sync() -> void:
	if actor == null:
		return
	position = actor.position_2d
	_update_hp_label()


# ========== 内部 ==========

func _team_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(0.85, 0.25, 0.25, 1.0)  # 红
	return Color(0.25, 0.45, 0.85, 1.0)      # 蓝


func _update_hp_label() -> void:
	if actor == null or _hp_label == null:
		return
	if actor.is_dead():
		_hp_label.text = "DEAD"
		_hp_label.modulate = Color(0.5, 0.5, 0.5, 1.0)
	else:
		_hp_label.text = "%.0f" % actor.attribute_set.hp
