## BumpAction - 临时位移弹回动作
##
## 用于撞墙 / 撞单位时的"冲出 → 卡住 → 弹回"表演。actor 不真的离开当前格,
## 只是 view 层在世界坐标上叠一段瞬时偏移 + 挤压压扁,逻辑层 hex_position
## 完全不动。push_blocked 事件的视觉表现入口。
##
## 时间曲线 (progress 0~1):
##   [0,    0.30]: 冲出阶段 — offset 从 0 → max_offset (ease_out),squish 还没起
##   [0.30, 0.50]: 撞击峰值 — offset 维持峰值附近,squish 达最大(Y 压扁、XZ 略胀)
##   [0.50, 1.00]: 弹回阶段 — offset 朝 0 收 (ease_out_back 略带回弹),squish 缓慢恢复
class_name FrontendBumpAction
extends FrontendVisualAction


# ========== 属性 ==========

## bump 方向(单位向量,XZ 平面;Y 通常为 0)
var direction: Vector3

## 峰值偏移幅度(世界坐标,常用 hex_size * 0.30 左右)
var max_offset: float

## 是否做挤压压扁(撞硬物时打开;空气墙之类不打开可只做位移)
var squish_enabled: bool


# ========== 构造函数 ==========

func _init(
	p_actor_id: String,
	p_direction: Vector3,
	p_max_offset: float,
	p_duration: float,
	p_squish_enabled: bool = true,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.BUMP, p_duration, p_delay)
	actor_id = p_actor_id
	direction = p_direction.normalized() if p_direction.length() > 0.0 else Vector3.ZERO
	max_offset = p_max_offset
	squish_enabled = p_squish_enabled


# ========== 工具方法 ==========

## 根据 progress 算当前应叠加的世界偏移
func get_offset(progress: float) -> Vector3:
	if direction == Vector3.ZERO or max_offset <= 0.0:
		return Vector3.ZERO

	var t := clampf(progress, 0.0, 1.0)
	var amplitude: float

	if t <= 0.30:
		# ease_out 冲出
		var sub := t / 0.30
		amplitude = 1.0 - pow(1.0 - sub, 3.0)
	elif t <= 0.50:
		# 峰值附近,轻微下挫(略 push 进墙)
		var sub := (t - 0.30) / 0.20
		amplitude = 1.0 + 0.05 * sin(sub * PI)
	else:
		# 弹回 + 轻微 overshoot
		var sub := (t - 0.50) / 0.50
		# ease_out_back: 1 → 0,中途 -0.10 反向回弹
		var inv := 1.0 - sub
		amplitude = inv * inv * (2.7 * inv - 1.7) + sub * 0.0
		# 上式在 sub=1 时落到 0,sub=0 时为 1;中途略带 overshoot

	return direction * max_offset * amplitude


## 根据 progress 算当前 mesh 挤压(Vector3 scale,1.0 = 无形变)
## 仅在 squish_enabled = true 时使用;否则返回 Vector3.ONE
func get_squish(progress: float) -> Vector3:
	if not squish_enabled:
		return Vector3.ONE

	var t := clampf(progress, 0.0, 1.0)

	# squish 在撞击峰值 [0.30, 0.50] 段拉满,然后线性恢复
	var intensity: float
	if t < 0.30:
		intensity = t / 0.30 * 0.6  # 冲出阶段已经开始有少量预挤
	elif t < 0.50:
		intensity = 1.0
	else:
		intensity = 1.0 - (t - 0.50) / 0.50

	intensity = clampf(intensity, 0.0, 1.0)

	# Y 压扁 (max -0.18) + XZ 略胀 (max +0.12)
	var sy := 1.0 - 0.18 * intensity
	var sxz := 1.0 + 0.12 * intensity
	return Vector3(sxz, sy, sxz)
