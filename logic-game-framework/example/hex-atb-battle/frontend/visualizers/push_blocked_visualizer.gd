## PushBlockedVisualizer - 撞墙 / 撞单位 弹回事件转换器
##
## 将 push_blocked 翻译为 BumpAction:target 朝 attempted_to_hex 方向冲出
## 一小段再弹回原位,view 层叠加位移 + 挤压压扁,逻辑层 hex_position 全程不动。
##
## 注意:撞击碰撞伤害是 PushAction 单独 push 的 DamageEvent,会被 DamageVisualizer
## 处理(飘字 + 闪白 + 血条),本 visualizer 只补"位移+挤压"的反弹手感。
##
## N=1 撞正前方:仅 push_blocked → BumpAction(target 不动)
## N>1 移动后撞: ActorDisplacedEvent + push_blocked → DisplacementVisualizer 走完
##              MoveAction(到 stopped_at_hex)后,本 visualizer 在原地再叠 BumpAction
class_name FrontendPushBlockedVisualizer
extends FrontendBaseVisualizer


const _BUMP_DURATION_MS: float = 280.0
## bump 峰值 = 一步格距的比例(view 投影后就是 hex 中心间距 × 比例)
const _BUMP_OFFSET_RATIO: float = 0.30


func _init() -> void:
	visualizer_name = "PushBlockedVisualizer"


func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == BattleEvents.PUSH_BLOCKED_EVENT


func translate(event: Dictionary, _context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var e := BattleEvents.PushBlockedEvent.from_dict(event)
	var stopped_at := HexCoord.from_dict(e.stopped_at_hex)
	var attempted_to := HexCoord.from_dict(e.attempted_to_hex)

	if not stopped_at.is_valid() or not attempted_to.is_valid():
		return []

	# 逻辑平面位移:从停住格指向撞向格的 axial 一步(不归一化,见 FrontendBumpAction 文件头)
	var step := Vector2(attempted_to.q - stopped_at.q, attempted_to.r - stopped_at.r)
	if step == Vector2.ZERO:
		return []

	# 撞 actor / 撞 edge 都启用挤压(效果更明显;空气墙之类目前还没有)
	var squish_enabled := true

	var bump := FrontendBumpAction.new(
		e.actor_id,
		step,
		_BUMP_OFFSET_RATIO,
		_BUMP_DURATION_MS,
		squish_enabled
	)
	return [bump]
