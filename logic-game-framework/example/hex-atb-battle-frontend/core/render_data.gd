## RenderData - 渲染层信号 payload 数据类
##
## 替代 RenderWorld 中通过信号传递的 Dictionary payload，
## 提供编译期类型检查。
class_name FrontendRenderData


## 飘字创建数据
class FloatingText extends RefCounted:
	## 动作 ID
	var id: String = ""
	## 关联的 Actor ID
	var actor_id: String = ""
	## 显示文本
	var text: String = ""
	## 文本颜色
	var color: Color = Color.WHITE
	## 世界坐标位置
	var position: Vector3 = Vector3.ZERO
	## 创建时的世界时间（毫秒）
	var start_time: int = 0
	## 持续时间（毫秒）
	var duration: float = 0.0
	## 文本样式
	var style: int = 0


## 攻击特效创建数据
class AttackVfx extends RefCounted:
	## 特效 ID
	var id: String = ""
	## 施法者 Actor ID
	var source_actor_id: String = ""
	## 目标 Actor ID
	var target_actor_id: String = ""
	## 施法者位置
	var source_position: Vector3 = Vector3.ZERO
	## 目标位置
	var target_position: Vector3 = Vector3.ZERO
	## 特效类型
	var vfx_type: int = 0
	## 特效颜色
	var vfx_color: Color = Color.WHITE
	## 是否暴击
	var is_critical: bool = false
	## 攻击方向
	var direction: Vector3 = Vector3.FORWARD
	## 攻击距离
	var distance: float = 0.0
	## 创建时的世界时间（毫秒）
	var start_time: int = 0
	## 持续时间（毫秒）
	var duration: float = 0.0


## 投射物创建数据
class Projectile extends RefCounted:
	## 动作 ID
	var id: String = ""
	## 投射物逻辑 ID
	var projectile_id: String = ""
	## 施法者 Actor ID
	var source_actor_id: String = ""
	## 目标 Actor ID
	var target_actor_id: String = ""
	## 起始位置
	var start_position: Vector3 = Vector3.ZERO
	## 目标位置
	var target_position: Vector3 = Vector3.ZERO
	## 投射物类型
	var projectile_type: int = 0
	## 投射物颜色
	var projectile_color: Color = Color(0.3, 0.7, 1.0)
	## 投射物大小
	var projectile_size: float = 0.5
	## 飞行方向
	var direction: Vector3 = Vector3.FORWARD
	## 创建时的世界时间（毫秒）
	var start_time: int = 0
	## 持续时间（毫秒）
	var duration: float = 0.0


## 程序化特效数据
class ProceduralEffect extends RefCounted:
	## 特效 ID
	var id: String = ""
	## 特效类型（FrontendProceduralVFXAction.EffectType）
	var effect: int = 0
	## 关联的 Actor ID
	var actor_id: String = ""
	## 创建时的世界时间（毫秒）
	var start_time: int = 0
	## 持续时间（毫秒）
	var duration: float = 0.0
	## 强度
	var intensity: float = 1.0
	## 颜色
	var color: Color = Color.WHITE


## 震屏状态数据
class ScreenShake extends RefCounted:
	## X 轴偏移
	var offset_x: float = 0.0
	## Y 轴偏移
	var offset_y: float = 0.0
	
	## 转换为 Vector2
	func to_vector2() -> Vector2:
		return Vector2(offset_x, offset_y)
	
	## 是否有效（非零偏移）
	func is_active() -> bool:
		return offset_x != 0.0 or offset_y != 0.0
