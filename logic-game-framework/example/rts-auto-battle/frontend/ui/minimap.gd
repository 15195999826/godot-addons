## RtsMinimap - 屏幕右下角全图 minimap (双向交互).
##
## 实时画 BattleMap 边框 + 各 actor 点 (team color) + 主 camera 当前 visible_rect 框.
## 玩家点 minimap 任意位置 → emit `world_position_clicked(world_pos: Vector2)`,
## 调方平移主 camera 到该位置 (Camera2D limit_* 自动 clamp).
##
## 渲染走 `_draw` 自定义批量画 (优于 N 个 ColorRect 子节点); 由调方每帧 queue_redraw().
## 不读 actor 直接状态 — actor 点 / team color 走 director.get_actor_ids + get_render_state
## (含 team_id 字段, director._seed_render_state 写入).
class_name RtsMinimap
extends Control


signal world_position_clicked(world_pos: Vector2)


const _BG_COLOR: Color = Color(0.05, 0.05, 0.08, 0.85)
const _BORDER_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)
const _VIEWPORT_FRAME_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const _UNIT_DOT_HALF: float = 1.0
const _BUILDING_DOT_HALF: float = 2.0

const _TEAM_COLORS: Dictionary[int, Color] = {
	0: Color(0.20, 0.55, 1.00, 1.0),    # 蓝 = team 0 / human
	1: Color(1.00, 0.30, 0.30, 1.0),    # 红 = team 1 / ai
	-1: Color(1.00, 0.85, 0.30, 1.0),   # 黄 = neutral (resource node)
}
const _UNKNOWN_TEAM_COLOR: Color = Color(0.6, 0.6, 0.6, 1.0)


var _world_size: Vector2 = Vector2(500.0, 500.0)
var _director: RtsBattleDirector = null
var _camera: Camera2D = null


func bind(p_world_size: Vector2, p_director: RtsBattleDirector, p_camera: Camera2D) -> void:
	_world_size = p_world_size
	_director = p_director
	_camera = p_camera
	queue_redraw()


func _draw() -> void:
	var minimap_rect := Rect2(Vector2.ZERO, size)
	draw_rect(minimap_rect, _BG_COLOR, true)
	draw_rect(minimap_rect, _BORDER_COLOR, false, 1.0)

	if _director != null:
		_draw_actors()

	if _camera != null:
		_draw_viewport_frame()


func _draw_actors() -> void:
	for actor_id in _director.get_actor_ids():
		var state: Dictionary = _director.get_render_state(actor_id)
		if state.is_empty() or state.get("is_dead", false):
			continue
		var pos: Vector2 = state.get("curr_pos", Vector2.ZERO)
		var team_id: int = int(state.get("team_id", -999))
		var color: Color = _TEAM_COLORS.get(team_id, _UNKNOWN_TEAM_COLOR)
		var minimap_pos: Vector2 = _world_to_minimap(pos)
		# building 通常 hp > 500 (ct 2000 / barracks 800 / archer_tower 600); unit 上限 ~150 → 简单按 max_hp 区分.
		var half: float = _BUILDING_DOT_HALF if float(state.get("max_hp", 0.0)) >= 400.0 else _UNIT_DOT_HALF
		draw_rect(Rect2(minimap_pos - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), color, true)


func _draw_viewport_frame() -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var half_view: Vector2 = view_size * 0.5 / _camera.zoom
	var top_left: Vector2 = _camera.global_position - half_view
	var bottom_right: Vector2 = _camera.global_position + half_view
	var mm_tl: Vector2 = _world_to_minimap(top_left)
	var mm_br: Vector2 = _world_to_minimap(bottom_right)
	draw_rect(Rect2(mm_tl, mm_br - mm_tl), _VIEWPORT_FRAME_COLOR, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var world_pos: Vector2 = _minimap_to_world(mb.position)
	world_position_clicked.emit(world_pos)
	accept_event()


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	return Vector2(
		world_pos.x / _world_size.x * size.x,
		world_pos.y / _world_size.y * size.y,
	)


func _minimap_to_world(minimap_pos: Vector2) -> Vector2:
	return Vector2(
		minimap_pos.x / size.x * _world_size.x,
		minimap_pos.y / size.y * _world_size.y,
	)
