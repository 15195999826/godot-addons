## ProjectileAction - 投射物飞行动作
##
## 描述投射物从起点飞向目标的动画
## 支持追踪目标或飞向固定位置
class_name FrontendProjectileAction
extends FrontendVisualAction


# ========== 投射物类型枚举 ==========

enum ProjectileType {
	ARROW,        # 箭矢（细长，指向飞行方向）
	FIREBALL,     # 火球（球形，带拖尾）
	ENERGY,       # 能量弹（发光球体）
}


# ========== 属性 ==========

## 投射物 ID（用于跟踪）
var projectile_id: String

## 发射者 ID
var source_actor_id: String

## 目标 ID（可选，用于追踪）
var target_actor_id: String

## 起始位置（世界坐标）
var start_position: Vector3

## 目标位置（世界坐标，如果无追踪目标则使用此位置）
var target_position: Vector3

## 投射物类型
var projectile_type: ProjectileType

## 投射物颜色
var projectile_color: Color

## 投射物大小
var projectile_size: float

## 飞行速度（单位/秒，用于计算持续时间）
var speed: float


# ========== 构造函数 ==========

func _init(
	p_projectile_id: String,
	p_source_actor_id: String,
	p_start_position: Vector3,
	p_target_position: Vector3,
	p_duration: float,
	p_target_actor_id: String = "",
	p_projectile_type: ProjectileType = ProjectileType.ENERGY,
	p_projectile_color: Color = Color(0.3, 0.7, 1.0),
	p_projectile_size: float = 0.5,
	p_speed: float = 20.0,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.PROJECTILE, p_duration, p_delay)
	projectile_id = p_projectile_id
	source_actor_id = p_source_actor_id
	target_actor_id = p_target_actor_id
	start_position = p_start_position
	target_position = p_target_position
	projectile_type = p_projectile_type
	projectile_color = p_projectile_color
	projectile_size = p_projectile_size
	speed = p_speed
	actor_id = p_projectile_id  # 关联到投射物自身


## 获取当前位置（基于进度插值）
func get_current_position(progress: float) -> Vector3:
	return FrontendVisualAction.lerp_vector3(start_position, target_position, progress)


## 获取飞行方向（单位向量）
func get_direction() -> Vector3:
	var dir := target_position - start_position
	return dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD


## 获取飞行距离
func get_distance() -> float:
	return (target_position - start_position).length()


## 根据速度计算持续时间（毫秒）
static func calculate_duration(start_pos: Vector3, target_pos: Vector3, fly_speed: float) -> float:
	var distance := (target_pos - start_pos).length()
	if fly_speed <= 0.0:
		return 500.0  # 默认 500ms
	return (distance / fly_speed) * 1000.0


## 获取拖尾长度（基于速度）
func get_trail_length() -> float:
	return speed * 0.1  # 拖尾长度与速度成正比
