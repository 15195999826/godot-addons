## ActorRenderState - Actor 渲染状态
##
## 替代 RenderWorld 中的 Dictionary actor 状态，提供编译期类型检查。
## 包含 Actor 在表演层的所有可视状态字段。
class_name FrontendActorRenderState
extends RefCounted


# ========== 基础信息 ==========

## Actor 唯一标识
var id: String = ""

## Actor 类型（如 "Character"）
var type: String = ""

## 显示名称
var display_name: String = ""

## 所属队伍
var team: int = 0


# ========== 位置 ==========

## 六边形坐标位置
var position: HexCoord = HexCoord.zero()


# ========== 战斗状态 ==========

## 当前视觉 HP（用于动画插值）
var visual_hp: float = 0.0

## 最大 HP
var max_hp: float = 100.0

## 是否存活
var is_alive: bool = true


# ========== 视觉效果 ==========

## 受击闪白进度（0.0 = 无闪白，1.0 = 全白）
var flash_progress: float = 0.0

## 染色颜色
var tint_color: Color = Color.WHITE

## 死亡动画进度（0.0 = 开始，1.0 = 完成）
var death_progress: float = 0.0


# ========== 工具方法 ==========

## 创建深拷贝
func duplicate() -> FrontendActorRenderState:
	var copy := FrontendActorRenderState.new()
	copy.id = id
	copy.type = type
	copy.display_name = display_name
	copy.team = team
	copy.position = HexCoord.new(position.q, position.r)
	copy.visual_hp = visual_hp
	copy.max_hp = max_hp
	copy.is_alive = is_alive
	copy.flash_progress = flash_progress
	copy.tint_color = tint_color
	copy.death_progress = death_progress
	return copy
