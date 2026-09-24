## Cone debug overlay action - 检查区域格子 + 区域外沿 + 逻辑层引导线（hex 私有卡片）。
##
## cells / boundary_segments 是逻辑平面 axial（整数格 / 浮点端点），view 端用棋盘几何建多边形与投影；
## guide_segments 是逻辑层 angle cone 给的两条边界线，点在逻辑层棋盘的 2D 平面坐标里（不是 axial），
## 原样透传、view 端把 y 落到 Z 轴——翻译员没有棋盘几何换算不了，这是本卡片自己的约定。
class_name FrontendConeDebugOverlayAction
extends FrontendVisualAction


var cue_id: String = ""
## 检查区域的格子（axial，整数值）
var cells: Array[Vector2] = []
## 区域外沿线段，每段两个 axial 浮点端点
var boundary_segments: Array[PackedVector2Array] = []
## 逻辑层引导线，每段两个逻辑层 2D 平面点
var guide_segments: Array[PackedVector2Array] = []
var fill_color: Color = Color.WHITE
var boundary_color: Color = Color.WHITE


func _init(
	p_cue_id: String,
	p_cells: Array[Vector2],
	p_boundary_segments: Array[PackedVector2Array],
	p_guide_segments: Array[PackedVector2Array],
	p_fill_color: Color,
	p_boundary_color: Color,
	p_duration: float,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.CONE_DEBUG_OVERLAY, p_duration, p_delay)
	cue_id = p_cue_id
	cells = p_cells
	boundary_segments = p_boundary_segments
	guide_segments = p_guide_segments
	fill_color = p_fill_color
	boundary_color = p_boundary_color
