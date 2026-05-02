## RtsBaseVisualizer - RTS visualizer 抽象基类 (push 模式)
##
## 与 hex example 的 FrontendBaseVisualizer 不同 paradigm:
##   - hex: RefCounted, 把 GameEvent 翻译为声明式 VisualAction (replay-driven, 离线)
##   - RTS: Node2D, 接 director.actor_render_state_updated signal 后 push 写本地字段 (实时 sim)
##
## 本基类只 hoist Unit / Building visualizer 真正共用的部分:
##   - render-state push 字段 (_curr_pos / _hp / _max_hp / _is_dead)
##   - actor_id / _team_id / _director_ref 绑定
##   - _bind_base() helper: 子类 bind 时调一次, 完成"持 director weakref + 起手 hydrate"
##   - _get_director() helper
##   - get_render_hp() / get_render_is_dead() query (smoke/debug)
##
## 子类各自负责的差异:
##   - _team_color (Unit 用亮色, Building 用暗 alpha)
##   - bind() 签名 (Unit 含 render_height, Building 含 footprint_size + is_crystal_tower)
##   - update_render_state() 实现 (Unit 走 _process lerp, Building 走 _draw redraw)
##   - 视觉成员 (Unit: _polygon + _hp_label + _SelectionRing; Building: _draw 画 footprint+hp bar)
##   - _prev_pos / 插值 (仅 Unit 需要; 建筑不移动)
class_name RtsBaseVisualizer
extends Node2D


# ========== Push 模式字段 (director signal 写) ==========

var actor_id: String = ""
var _team_id: int = -1
var _director_ref: WeakRef = null

var _curr_pos: Vector2 = Vector2.ZERO
var _hp: float = 0.0
var _max_hp: float = 0.0
var _is_dead: bool = false


# ========== Director 引用 ==========

func _get_director() -> RtsBattleDirector:
	if _director_ref == null:
		return null
	return _director_ref.get_ref() as RtsBattleDirector


## 子类 bind() 调一次完成基础 hydrate: 持 director weakref + 从 director.get_render_state
## 拉起手 state (visualizer 接 signal 前 director 可能已 emit 过, 起手要补一次).
##
## 子类负责把额外字段 (render_height / footprint_size / 视觉子节点) 在调此 helper 之后初始化.
func _bind_base(p_actor_id: String, p_team_id: int, p_director: RtsBattleDirector) -> void:
	actor_id = p_actor_id
	_team_id = p_team_id
	if p_director != null:
		_director_ref = weakref(p_director)
		var state: Dictionary = p_director.get_render_state(p_actor_id)
		if not state.is_empty():
			_curr_pos = state.get("curr_pos", Vector2.ZERO)
			_hp = state.get("hp", 0.0)
			_max_hp = state.get("max_hp", 0.0)
			_is_dead = state.get("is_dead", false)


# ========== 查询 (smoke / debug 用) ==========

func get_render_hp() -> float:
	return _hp


func get_render_is_dead() -> bool:
	return _is_dead
