## VisualEffectPayload - 一次性效果的信号 payload 数据类
##
## VisualState 的 effect_spawned / effect_updated 信号带的就是这里的对象（内置种类）；
## 项目私有效果种类自定义 Effect 子类即可，框架信号不用改。
## 位置一律是逻辑平面坐标（Vector2），方向 / 距离这类欧氏量不在 payload 里，由 view 投影后自己算。
class_name VisualEffectPayload


## 一次性效果在账本里的共同底座：id / 入账时间 / 寿命。
## 账本在 duration 到期后静默忘记它（view 自管节点寿命）；由 progress 驱动、需要 removed 通知的效果
## （攻击特效 / 投射物）由 handler 在完成时显式 remove_effect。
class Effect extends RefCounted:
	## 效果 ID（= 产生它的卡片在步进器里的 id）
	var id: String = ""
	## 入账时的账本时间（毫秒）
	var start_time: int = 0
	## 持续时间（毫秒）
	var duration: float = 0.0


## 飘字创建数据
class FloatingText extends Effect:
	## 关联的 Actor ID
	var actor_id: String = ""
	## 显示文本
	var text: String = ""
	## 文本颜色
	var color: Color = Color.WHITE
	## 显示位置（逻辑平面坐标）
	var position: Vector2 = Vector2.ZERO
	## 文本样式
	var style: int = 0


## 攻击特效数据（spawn 时建，每次 apply 更新 scale_factor / alpha 后随 effect_updated 带出）
class AttackVfx extends Effect:
	## 施法者 Actor ID
	var source_actor_id: String = ""
	## 目标 Actor ID
	var target_actor_id: String = ""
	## 施法者位置（逻辑平面坐标）
	var source_position: Vector2 = Vector2.ZERO
	## 目标位置（逻辑平面坐标）
	var target_position: Vector2 = Vector2.ZERO
	## 特效类型
	var vfx_type: int = 0
	## 特效颜色
	var vfx_color: Color = Color.WHITE
	## 是否暴击
	var is_critical: bool = false
	## 当前缩放（随进度更新）
	var scale_factor: float = 0.0
	## 当前透明度（随进度更新）
	var alpha: float = 1.0


## 投射物数据（spawn 时建，每次 apply 更新 position 后随 effect_updated 带出）
class Projectile extends Effect:
	## 投射物逻辑 ID
	var projectile_id: String = ""
	## 施法者 Actor ID
	var source_actor_id: String = ""
	## 目标 Actor ID
	var target_actor_id: String = ""
	## 起始位置（逻辑平面坐标）
	var start_position: Vector2 = Vector2.ZERO
	## 目标位置（逻辑平面坐标）
	var target_position: Vector2 = Vector2.ZERO
	## 投射物类型
	var projectile_type: int = 0
	## 投射物颜色
	var projectile_color: Color = Color(0.3, 0.7, 1.0)
	## 投射物大小
	var projectile_size: float = 0.5
	## 当前位置（逻辑平面坐标，随进度更新；直线飞行方向由 view 从起止位置投影后算）
	var position: Vector2 = Vector2.ZERO


## 程序化特效数据（账本内部：闪白 / 震屏 / 染色的寿命簿，不发信号）
class ProceduralEffect extends Effect:
	## 特效类型（VisualProceduralVfxAction.EffectType）
	var effect: int = 0
	## 关联的 Actor ID
	var actor_id: String = ""
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
