## Cone debug overlay 卡片 - 检查区域格子 + 区域外沿 + 逻辑层引导线（hex 私有卡片）。
##
## 「项目私有卡片」的范例：自定义 kind + 自带 Payload + 自带记账 handler（static apply），
## 由 FrontendBattleAnimator 建 Director 时 register_handler 挂进 VisualUpdater，框架一行不改。
##
## cells / boundary_segments 是逻辑平面 axial（整数格 / 浮点端点），view 端用棋盘几何建多边形与投影；
## guide_segments 是逻辑层 angle cone 给的两条边界线，点在逻辑层棋盘的 2D 平面坐标里（不是 axial），
## 原样透传、view 端把 y 落到 Z 轴——翻译员没有棋盘几何换算不了，这是本卡片自己的约定。
class_name FrontendConeDebugOverlayAction
extends VisualAction


const KIND: StringName = &"cone_debug_overlay"


## effect_spawned 带的 payload；view 自管寿命，账本到期静默忘记
class Payload extends VisualEffectPayload.Effect:
	## cue_id: grid_cone_cast / angle_cone_cast
	var cue_id: String = ""
	## 检查区域的格子（axial 整数值）
	var cells: Array[Vector2] = []
	## 区域外沿线段，每段两个 axial 浮点端点
	var boundary_segments: Array[PackedVector2Array] = []
	## 逻辑层引导线（angle cone 两条边），每段两个逻辑层 2D 平面点
	var guide_segments: Array[PackedVector2Array] = []
	## 填充颜色
	var fill_color: Color = Color.WHITE
	## 边界颜色
	var boundary_color: Color = Color.WHITE


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
	super._init(KIND, p_duration, p_delay)
	cue_id = p_cue_id
	cells = p_cells
	boundary_segments = p_boundary_segments
	guide_segments = p_guide_segments
	fill_color = p_fill_color
	boundary_color = p_boundary_color


## 记账规则：按卡片 id 只入账一次并广播 effect_spawned；overlay 节点自管寿命
static func apply(state: VisualState, action: VisualAction, _progress: float, action_id: String) -> void:
	if state.has_effect(KIND, action_id):
		return
	var overlay := action as FrontendConeDebugOverlayAction
	var payload := Payload.new()
	payload.id = action_id
	payload.cue_id = overlay.cue_id
	payload.cells = overlay.cells
	payload.boundary_segments = overlay.boundary_segments
	payload.guide_segments = overlay.guide_segments
	payload.fill_color = overlay.fill_color
	payload.boundary_color = overlay.boundary_color
	payload.duration = overlay.duration
	state.spawn_effect(KIND, payload)
