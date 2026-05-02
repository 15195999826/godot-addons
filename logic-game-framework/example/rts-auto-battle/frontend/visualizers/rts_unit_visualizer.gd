## RtsUnitVisualizer - 单位最简识别 stub (P2.7 改写: push 模式 + alpha 插值)
##
## Node2D, 按 team_id 染色 (左红右蓝), 圆形 (8 边凸 polygon) + 上方 hp 文本.
##
## P2.7 改写要点:
##   - **不再持 actor 引用** (AC6: frontend 0 处 actor.position_2d 直读)
##   - **不再有 sync(actor) 拉模式** — 改为接收 director.actor_render_state_updated signal 后
##     update_render_state(...) 写到本地字段
##   - _process(delta) 走 director.get_alpha() 在 prev_pos / curr_pos 之间 lerp,
##     得到平滑插值位置 (跨 logic tick 的渲染帧填补 — 60FPS / 30Hz tick → 每 tick 2 渲染帧)
##
## 关键不变量:
##   - bind(actor_id, team_id, director) 后 actor_id 不变 (1:1 绑定)
##   - 不读 actor — actor 字段全部通过 update_render_state 由 director push 进来
##   - 死亡触发由 on_died() 入口 (可选; update_render_state 的 is_dead 也会更新 hp 显示)
class_name RtsUnitVisualizer
extends Node2D


# ========== 视觉常量 ==========

const RADIUS: float = 12.0
const POLYGON_SEGMENTS: int = 8
const HP_LABEL_OFFSET: Vector2 = Vector2(-20.0, -RADIUS - 18.0)


# ========== 字段 ==========

var actor_id: String = ""
var _team_id: int = -1
var _director_ref: WeakRef = null

## P2.8 — 渲染高度 (AIR 单位画在 8px 上空); 由 bind() 注入, 战斗期间不变。
## Godot 2D 坐标 y 向下增加, 故 y 偏移用 -render_height 实现"上抬"。
var _render_height: float = 0.0

var _polygon: Polygon2D = null
var _hp_label: Label = null

# Push 模式: WorldView 经 director signal 写到这些字段
var _prev_pos: Vector2 = Vector2.ZERO
var _curr_pos: Vector2 = Vector2.ZERO
var _hp: float = 0.0
var _max_hp: float = 0.0
var _is_dead: bool = false


# ========== 生命周期 ==========

func _ready() -> void:
	_polygon = Polygon2D.new()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(POLYGON_SEGMENTS):
		var angle: float = TAU * float(i) / float(POLYGON_SEGMENTS)
		pts.append(Vector2(cos(angle), sin(angle)) * RADIUS)
	_polygon.polygon = pts
	_polygon.color = _team_color(_team_id)
	add_child(_polygon)

	_hp_label = Label.new()
	_hp_label.position = HP_LABEL_OFFSET
	_hp_label.add_theme_font_size_override("font_size", 12)
	add_child(_hp_label)
	_update_hp_label()


func _process(_delta: float) -> void:
	# 跨 tick 渲染插值: 在 prev_pos / curr_pos 之间用 director alpha lerp.
	# 死亡后停在 curr_pos (alpha=1), 不再插值.
	var alpha: float = 1.0
	if not _is_dead:
		var director: RtsBattleDirector = _get_director()
		if director != null:
			alpha = director.get_alpha()
	# P2.8: 飞行单位上抬 _render_height px (Godot 2D y 向下, 故减)。
	position = _prev_pos.lerp(_curr_pos, alpha) - Vector2(0.0, _render_height)


# ========== 公共 API ==========

## 由 WorldView 在 _spawn_visualizer 内调用.
##
## actor_id 是 LGF 全 actor id (含 instance prefix); team_id 0=left/red, 1=right/blue.
## director 用于 _process 内拿 alpha (持 weakref 防循环).
## p_render_height (P2.8): 飞行单位 8px, 地面单位 0; 创建期 hydrate 自 actor.get_render_height()。
func bind(p_actor_id: String, p_team_id: int, p_director: RtsBattleDirector, p_render_height: float = 0.0) -> void:
	actor_id = p_actor_id
	_team_id = p_team_id
	_render_height = p_render_height
	if p_director != null:
		_director_ref = weakref(p_director)
	# 起手从 director 拉一次初始 render state (visualizer 接信号前 director 可能没 emit 过)
	if p_director != null:
		var state: Dictionary = p_director.get_render_state(p_actor_id)
		if not state.is_empty():
			_prev_pos = state.get("prev_pos", Vector2.ZERO)
			_curr_pos = state.get("curr_pos", Vector2.ZERO)
			_hp = state.get("hp", 0.0)
			_max_hp = state.get("max_hp", 0.0)
			_is_dead = state.get("is_dead", false)
			position = _curr_pos - Vector2(0.0, _render_height)
	# 颜色 / label 在 _ready 之后再 update (此时 _polygon / _hp_label 可能还为 null)
	if _polygon != null:
		_polygon.color = _team_color(_team_id)
	_update_hp_label()


## 由 WorldView (router) 把 director.actor_render_state_updated 信号路由到本 visualizer 时调用.
func update_render_state(
	prev_pos: Vector2,
	curr_pos: Vector2,
	hp: float,
	max_hp: float,
	is_dead: bool,
) -> void:
	_prev_pos = prev_pos
	_curr_pos = curr_pos
	_hp = hp
	_max_hp = max_hp
	_is_dead = is_dead
	_update_hp_label()


## 由 WorldView 把 director.actor_died 信号路由到本 visualizer 时调用.
##
## 默认实现: 调暗 + label "DEAD". 子类可 override 加死亡动画.
func on_died() -> void:
	_is_dead = true
	if _polygon != null:
		_polygon.modulate = Color(0.4, 0.4, 0.4, 0.5)
	_update_hp_label()


# ========== 查询 (smoke / debug 用; 不在 sim 主路径) ==========

func get_render_position() -> Vector2:
	return position


func get_render_hp() -> float:
	return _hp


func get_render_is_dead() -> bool:
	return _is_dead


# ========== 内部 ==========

func _team_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(0.85, 0.25, 0.25, 1.0)  # 红
	if team_id == 1:
		return Color(0.25, 0.45, 0.85, 1.0)  # 蓝
	return Color(0.6, 0.6, 0.6, 1.0)         # neutral / unknown


func _update_hp_label() -> void:
	if _hp_label == null:
		return
	if _is_dead:
		_hp_label.text = "DEAD"
		_hp_label.modulate = Color(0.5, 0.5, 0.5, 1.0)
	else:
		_hp_label.text = "%.0f" % _hp
		_hp_label.modulate = Color.WHITE


func _get_director() -> RtsBattleDirector:
	if _director_ref == null:
		return null
	return _director_ref.get_ref() as RtsBattleDirector
