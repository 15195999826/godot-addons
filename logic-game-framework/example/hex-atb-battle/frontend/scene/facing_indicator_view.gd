## Phase F · FacingIndicatorView - 朝向箭头 attached visual
##
## 显示 CharacterActor 当前 6 向朝向. EnvironmentActor 等无 facing 语义的 actor 由 UnitView
## 跳过 attach (per spec: "只对 CharacterActor 显示").
##
## 实现: Label3D "▶" billboard 在 unit mesh 外圈一定距离, 随 facing_direction 旋转 (Y 轴).
## 不引入 turn-speed / lerp 动画 — 每次 update_from_state 都瞬时 snap 到新方向 (per spec).
class_name FrontendFacingIndicatorView
extends Node3D


## 箭头距 unit 中心的水平偏移 (世界单位; flat-top hex_size=1 时 0.45 落在 unit mesh 外圈附近).
const ARROW_DISTANCE := 0.65
## 箭头 Y 轴抬升 (与 unit mesh 同高).
const ARROW_HEIGHT := 0.55


var _label: Label3D
## 缓存上一次 facing, 避免每帧重设节省 redraw.
var _cached_facing: int = -1


func _ready() -> void:
	_label = Label3D.new()
	_label.text = "▶"
	_label.pixel_size = 0.012
	_label.font_size = 48
	_label.modulate = Color(1.0, 0.9, 0.2)  # 黄色, 视觉对比强
	_label.outline_size = 6
	_label.outline_modulate = Color(0.05, 0.05, 0.1, 1.0)
	_label.no_depth_test = false
	# Y-billboard: 文字朝相机但 Y 轴朝向保持 (让"指向感"由位置而非旋转传达).
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(_label)
	position = Vector3(0.0, ARROW_HEIGHT, 0.0)


## 接收 FrontendActorRenderState; 仅当 type == "Character" 才可见; 同 facing 不重绘.
func update_from_state(state: FrontendActorRenderState) -> void:
	if state == null:
		visible = false
		return
	if state.type != "Character":
		# EnvironmentActor 等不显示 facing 箭头 (per spec).
		visible = false
		return
	visible = true
	if state.facing_direction == _cached_facing:
		return
	_cached_facing = state.facing_direction
	# direction 0..5 → 角度 (degrees, X-Z 平面;
	#   DIR_EAST=0 → 朝 +X (画面右), HexCoord 方向定义).
	# 在 flat-top hex 中, 6 个方向均匀分布 (每 60°).
	# Godot 3D 中 (X, Z 平面 top-down 时), Y 轴旋转: 0° = +X 方向.
	# 我们移动 label 到该方向 ARROW_DISTANCE 距离的点;
	# 不旋转 label (BILLBOARD_FIXED_Y 让它面相机).
	var angle_rad: float = state.facing_direction * PI / 3.0
	# 注: Godot 3D 中 -Z 是 forward, +X 右. coord_to_world 把 (q,r) 映射到 (x, z).
	#   DIR_EAST (0) 在 hex 中是 +X; sin(0)=0, cos(0)=1 → offset (cos*d, h, sin*d)
	#   下一格 NE (1, -1) coord_to_world → (1.5, -.87) 大致 angle = atan2(-.87, 1.5) ≈ -30°
	#   但 HexCoord.DIRECTIONS 与 HexFacing 6 方向严格按 60° 等分, 这里直接用 0..5*60°.
	# 经验值: 选 (cos, h, sin) 配合 BILLBOARD_FIXED_Y 看起来正确.
	position = Vector3(cos(angle_rad) * ARROW_DISTANCE, ARROW_HEIGHT, sin(angle_rad) * ARROW_DISTANCE)
