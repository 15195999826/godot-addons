## ActorVisualState - 每个进入过表演的逻辑 actor 在账本上的一条
##
## 包含 actor 在表演层的全部可视状态字段，提供编译期类型检查。
class_name ActorVisualState
extends RefCounted


# ========== 基础信息 ==========

## Actor 唯一标识
var id: String = ""

## Actor 类型（如 "Character"）
var type: String = ""

## Actor 配置 ID（如 "Totem" / "fire_tile"）
var config_id: String = ""

## 显示名称
var display_name: String = ""

## 所属队伍
var team: int = 0


# ========== 位置 ==========

## 已落定的逻辑平面坐标（移动中的在飞插值见 VisualState.get_actor_position）
var position: Vector2 = Vector2.ZERO


# ========== 战斗状态 ==========

## 当前视觉 HP(每 tick 朝 target_hp 收敛 lerp,见 VisualUpdater.tick_time)
var visual_hp: float = 0.0

## 目标 HP(damage / heal event apply 后立即累到这里;visual_hp 异步追赶)
var target_hp: float = 0.0

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

## bump 临时偏移(撞墙 / 撞单位时叠在位置上的逻辑平面位移,不动逻辑位置;view 投影后叠加)
var bump_offset: Vector2 = Vector2.ZERO

## bump 临时挤压(x = 水平缩放, y = 竖直缩放;Vector2.ONE = 无形变)
var bump_squish: Vector2 = Vector2.ONE

## 朝向编号，含义由项目定（hex 项目是六个方向 0..5）：
##   - 台面重建时由 VisualState 读 actor_init.attributes["facing_direction"] 填入
##   - 战斗中由项目翻译员翻成 VisualFacingStateAction，VisualUpdater 瞬时写入
var facing_direction: int = 0


# ========== Buff 状态 ==========

## 当前挂在该 actor 上的 buff 摘要列表(顺序 = 首次 ADD 顺序,稳定不重排)。
## 由项目翻译员翻成 VisualBuffStateAction，VisualUpdater 维护。
var buffs: Array[BuffSummary] = []


# ========== 护盾状态 ==========

## 当前挂在该 actor 上的护盾实例列表(顺序 = 首次 ADD 顺序,稳定不重排)。
## 由项目翻译员翻成 VisualShieldStateAction，VisualUpdater 维护。
##
## 与 buffs 数组互补:buffs 提供头顶 chip 的视觉摘要,shields 提供血条上方独立
## 护盾条的数据,保留多盾粒度(current/capacity/priority)。
var shields: Array[ShieldSummary] = []


# ========== 工具方法 ==========

## 创建深拷贝
func duplicate() -> ActorVisualState:
	var copy := ActorVisualState.new()
	copy.id = id
	copy.type = type
	copy.config_id = config_id
	copy.display_name = display_name
	copy.team = team
	copy.position = position
	copy.visual_hp = visual_hp
	copy.target_hp = target_hp
	copy.max_hp = max_hp
	copy.is_alive = is_alive
	copy.flash_progress = flash_progress
	copy.tint_color = tint_color
	copy.death_progress = death_progress
	copy.bump_offset = bump_offset
	copy.bump_squish = bump_squish
	copy.facing_direction = facing_direction
	for b in buffs:
		copy.buffs.append(b.duplicate())
	for s in shields:
		copy.shields.append(s.duplicate())
	return copy
