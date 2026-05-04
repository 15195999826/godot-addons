## FloatingTextView - 飘字视图
##
## 显示伤害/治疗数字的飘字效果。绽开模式 + XZ 平面 pairwise 排斥力(Hades 风格):
## 同帧多条飘字会互相推开,即使初始 random 偏移撞到一起,几帧内就会自动散开。
##
## 排斥实现:静态 _alive_views 注册表,每帧 O(N²) 算 XZ 平面距离 < REPEL_RADIUS
## 的 pair,把 self 朝远离 peer 的方向推一下。力进入 _repel_offset 累加然后衰减,
## 形成弹性的"弹开-回稳"行为而不是僵硬瞬移。
class_name FrontendFloatingTextView
extends Node3D


# ========== 信号 ==========

## 动画完成
signal animation_finished()


# ========== 常量 ==========

const _BURST_RADIUS_MIN: float = 0.55
const _BURST_RADIUS_MAX: float = 1.10
## 字号抖动:基准下移(标准值变小),区间放大让暴击 / 大数仍然显眼
const _SIZE_JITTER_MIN: float = 0.65
const _SIZE_JITTER_MAX: float = 1.10
## pop-in 入场占总时长比例(0~POP_IN_PCT 是从小→放大→回正)
const _POP_IN_PCT: float = 0.18
const _POP_PEAK: float = 1.20
## 抛物线峰值高度(世界单位,在 progress=0.5 处达到)
const _ARC_PEAK_HEIGHT: float = 1.10

## XZ 平面 pairwise 排斥半径(<= 此距离内 peer 互相推);世界单位
const _REPEL_RADIUS: float = 0.55
## 排斥力强度(单位 1/秒;越大越快推开)
const _REPEL_STRENGTH: float = 14.0
## 排斥力位移衰减率(每秒衰减比;无 peer 时 _repel_offset 朝 0 收敛)
const _REPEL_DECAY_PER_SEC: float = 6.0
## 排斥位移上限(避免极端拥挤时飞太远)
const _REPEL_MAX_OFFSET: float = 1.20


# ========== 静态注册表 ==========

## 所有活跃飘字的弱注册(直接持引用 — Node 自己 _exit_tree 时移除)
static var _alive_views: Array[FrontendFloatingTextView] = []


# ========== 属性 ==========

var _label: Label3D
var _start_position: Vector3
var _burst_offset: Vector3 = Vector3.ZERO  # XZ 平面随机偏移(终点)
var _size_jitter: float = 1.0
var _duration: float = 1000.0
var _elapsed: float = 0.0
var _style: int = 0  # FloatingTextStyle
var _base_font_size: int = 48
## 排斥力累积位移(XZ 平面;Y=0)。每帧增量来自 peer 推力,衰减回 0
var _repel_offset: Vector3 = Vector3.ZERO


# ========== 初始化 ==========

func _ready() -> void:
	_create_label()
	_alive_views.append(self)


func _exit_tree() -> void:
	_alive_views.erase(self)


func _create_label() -> void:
	_label = Label3D.new()
	_label.pixel_size = 0.015
	_label.font_size = 48
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 4

	add_child(_label)


# ========== 公共方法 ==========

## 初始化飘字
func initialize(p_text: String, p_color: Color, world_position: Vector3, p_style: int, p_duration: float) -> void:
	_start_position = world_position
	_duration = p_duration
	_style = p_style
	_elapsed = 0.0

	# 随机绽开方向 + 半径(XZ 平面;Y 留给抛物线)
	var angle := randf() * TAU
	var radius := randf_range(_BURST_RADIUS_MIN, _BURST_RADIUS_MAX)
	_burst_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_size_jitter = randf_range(_SIZE_JITTER_MIN, _SIZE_JITTER_MAX)

	position = world_position
	scale = Vector3.ZERO  # _process 第一帧再 pop 起来

	if _label:
		_label.text = p_text
		_label.modulate = p_color

		# 根据样式 base size,再叠抖动
		match p_style:
			FrontendFloatingTextAction.FloatingTextStyle.CRITICAL:
				_base_font_size = 64
			FrontendFloatingTextAction.FloatingTextStyle.HEAL:
				_base_font_size = 48
			_:
				_base_font_size = 48
		_label.font_size = roundi(_base_font_size * _size_jitter)


func _process(delta: float) -> void:
	_elapsed += delta * 1000.0

	var progress := _elapsed / _duration

	if progress >= 1.0:
		animation_finished.emit()
		queue_free()
		return

	# ===== 基础动画位置 =====
	# XZ 偏移 ease_out(快出慢落)
	var xz_t := 1.0 - pow(1.0 - progress, 2.0)
	# Y 抛物线:0 → peak → 略下,sin 曲线最直观
	var y_arc := sin(progress * PI) * _ARC_PEAK_HEIGHT
	# 上升基线(整体往上飘一点点),配合 arc 让落点高于起点
	var rise := 0.4 * progress

	var base_pos := _start_position + _burst_offset * xz_t + Vector3(0.0, y_arc + rise, 0.0)

	# ===== Pairwise repulsion (XZ only) =====
	# 用 self.position 当前帧的"已落地"坐标对比 peer 同上;一帧延迟无所谓,
	# 系统稳定即可。Y 不参与,避免抛物线被强行扯回中点。
	var self_xz := Vector2(position.x, position.z)
	var force_xz := Vector2.ZERO
	for peer: FrontendFloatingTextView in _alive_views:
		if peer == self or peer == null or not is_instance_valid(peer):
			continue
		var peer_xz := Vector2(peer.position.x, peer.position.z)
		var diff := self_xz - peer_xz
		var dist := diff.length()
		if dist < _REPEL_RADIUS and dist > 0.0001:
			# 重叠量越大,推力越大;normalize 拿方向
			var overlap := _REPEL_RADIUS - dist
			force_xz += (diff / dist) * overlap

	# 累积位移 + 指数衰减(无 peer 时朝 0 收敛,有 peer 时与推力达成平衡)
	var force_3d := Vector3(force_xz.x, 0.0, force_xz.y)
	_repel_offset += force_3d * _REPEL_STRENGTH * delta
	var decay_factor := exp(-_REPEL_DECAY_PER_SEC * delta)
	_repel_offset *= decay_factor

	# 上限钳制(防止极端拥挤时飞出屏)
	var ro_xz := Vector2(_repel_offset.x, _repel_offset.z)
	if ro_xz.length() > _REPEL_MAX_OFFSET:
		ro_xz = ro_xz.normalized() * _REPEL_MAX_OFFSET
		_repel_offset = Vector3(ro_xz.x, 0.0, ro_xz.y)

	position = base_pos + _repel_offset

	# ===== Scale (pop-in / crit pulse) =====
	var pop_scale: float
	if progress < _POP_IN_PCT:
		var pop_t := progress / _POP_IN_PCT
		# 三角形曲线:前半冲到 PEAK,后半回 1
		if pop_t < 0.5:
			pop_scale = lerp(0.0, _POP_PEAK, pop_t / 0.5)
		else:
			pop_scale = lerp(_POP_PEAK, 1.0, (pop_t - 0.5) / 0.5)
	else:
		pop_scale = 1.0

	# 暴击在落点段持续轻微脉动
	var crit_pulse := 1.0
	if _style == FrontendFloatingTextAction.FloatingTextStyle.CRITICAL and progress >= _POP_IN_PCT:
		crit_pulse = 1.0 + 0.12 * sin(progress * PI * 2.0)

	scale = Vector3.ONE * pop_scale * crit_pulse

	# ===== 淡出:后 35% 才开始 =====
	if _label:
		var fade_start := 0.65
		var alpha: float
		if progress < fade_start:
			alpha = 1.0
		else:
			alpha = 1.0 - (progress - fade_start) / (1.0 - fade_start)
		_label.modulate.a = alpha
