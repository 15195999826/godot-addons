## RtsBuildingVisualizer - 建筑最简识别 stub (P2.7 新增)
##
## Node2D, 按 team_id 染色 + 显示 footprint 矩形 + hp bar.
##
## 与 unit visualizer 的区别:
##   - 不需要插值 — 建筑不移动, prev_pos == curr_pos 永远相等
##   - 用 _draw() 画 AABB outline (footprint_size × cell_size = 32 像素)
##   - hp bar 由 _draw 走当前 hp / max_hp 比例画出来
##   - 水晶塔加一圈高亮边框 (可选; 让玩家肉眼区分主基地)
##
## 与 unit visualizer 一样不持 actor 引用 — 通过 update_render_state push 模式更新.
class_name RtsBuildingVisualizer
extends Node2D


# ========== 视觉常量 ==========

const CELL_SIZE: float = 32.0  # 与 RtsBattleGrid.DEFAULT_CELL_SIZE 对齐
const HP_BAR_HEIGHT: float = 4.0
const HP_BAR_OFFSET_Y: float = -6.0  # 在 footprint 上方 6 px
const CRYSTAL_BORDER_COLOR := Color(1.0, 0.95, 0.6, 1.0)  # 金色边框


# ========== 字段 ==========

var actor_id: String = ""
var _team_id: int = -1
var _footprint_size: Vector2i = Vector2i(1, 1)
var _is_crystal_tower: bool = false
var _director_ref: WeakRef = null

var _curr_pos: Vector2 = Vector2.ZERO  # 建筑不移动, prev == curr
var _hp: float = 0.0
var _max_hp: float = 0.0
var _is_dead: bool = false


# ========== 生命周期 ==========

func _ready() -> void:
	queue_redraw()


# ========== 公共 API ==========

## 由 WorldView._spawn_visualizer 调用.
##
## footprint_size 来自 RtsBuildingActor.footprint_size (Vector2i, 单位: cells).
## director 用于起手 hydrate (不参与 _process — 建筑不需要插值).
func bind(
	p_actor_id: String,
	p_team_id: int,
	p_footprint_size: Vector2i,
	p_is_crystal_tower: bool,
	p_director: RtsBattleDirector,
) -> void:
	actor_id = p_actor_id
	_team_id = p_team_id
	_footprint_size = p_footprint_size
	_is_crystal_tower = p_is_crystal_tower
	if p_director != null:
		_director_ref = weakref(p_director)
		var state: Dictionary = p_director.get_render_state(p_actor_id)
		if not state.is_empty():
			_curr_pos = state.get("curr_pos", Vector2.ZERO)
			_hp = state.get("hp", 0.0)
			_max_hp = state.get("max_hp", 0.0)
			_is_dead = state.get("is_dead", false)
	position = _curr_pos
	queue_redraw()


## 由 WorldView 路由 director.actor_render_state_updated → visualizer.
##
## 建筑 prev_pos / curr_pos 默认相等 (建筑不动); 只读 curr_pos. hp 变化触发 redraw 重画 hp bar.
func update_render_state(
	_prev_pos: Vector2,
	curr_pos: Vector2,
	hp: float,
	max_hp: float,
	is_dead: bool,
) -> void:
	# 建筑不移动 — curr_pos 一旦 set 不变 (除非建筑被推, 但 P2.5+ 不发生), 仍同步以容错
	_curr_pos = curr_pos
	position = _curr_pos
	_hp = hp
	_max_hp = max_hp
	_is_dead = is_dead
	queue_redraw()


func on_died() -> void:
	_is_dead = true
	queue_redraw()


# ========== 查询 (smoke / debug 用) ==========

func get_render_hp() -> float:
	return _hp


func get_render_is_dead() -> bool:
	return _is_dead


# ========== 渲染 ==========

func _draw() -> void:
	var w: float = _footprint_size.x * CELL_SIZE
	var h: float = _footprint_size.y * CELL_SIZE
	var rect_origin: Vector2 = Vector2(-w * 0.5, -h * 0.5)
	var rect: Rect2 = Rect2(rect_origin, Vector2(w, h))

	# Body
	var body_color: Color = _team_color(_team_id)
	if _is_dead:
		body_color = Color(0.3, 0.3, 0.3, 0.5)
	draw_rect(rect, body_color, true)

	# Border (水晶塔金色, 其它白色细边)
	var border_color: Color = CRYSTAL_BORDER_COLOR if _is_crystal_tower else Color(1, 1, 1, 0.8)
	draw_rect(rect, border_color, false, 2.0)

	# HP bar (alive 才画)
	if not _is_dead and _max_hp > 0.0:
		var ratio: float = clamp(_hp / _max_hp, 0.0, 1.0)
		var bar_origin: Vector2 = Vector2(rect_origin.x, rect_origin.y + HP_BAR_OFFSET_Y - HP_BAR_HEIGHT)
		var bar_full: Rect2 = Rect2(bar_origin, Vector2(w, HP_BAR_HEIGHT))
		# 背景
		draw_rect(bar_full, Color(0.1, 0.1, 0.1, 0.7), true)
		# 前景
		var bar_fill: Rect2 = Rect2(bar_origin, Vector2(w * ratio, HP_BAR_HEIGHT))
		draw_rect(bar_fill, _hp_bar_color(ratio), true)


# ========== 内部 ==========

func _team_color(team_id: int) -> Color:
	if team_id == 0:
		return Color(0.65, 0.20, 0.20, 0.9)  # 暗红
	if team_id == 1:
		return Color(0.20, 0.35, 0.65, 0.9)  # 暗蓝
	return Color(0.5, 0.5, 0.5, 0.9)         # neutral


func _hp_bar_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.30, 0.85, 0.30, 1.0)
	if ratio > 0.3:
		return Color(0.95, 0.85, 0.20, 1.0)
	return Color(0.95, 0.30, 0.30, 1.0)
