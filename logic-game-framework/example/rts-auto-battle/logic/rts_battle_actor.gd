## RtsBattleActor - RTS 战斗 Actor 基类(Unit / Building 共用)
##
## 提供 RTS 例子中 Unit + Building 共有的字段与契约: 连续坐标 position_2d、collision_radius、
## movement_layer、ability_set、is_dead 标志、record-friendly _get_position 实现。
##
## 子类:
##   - RtsUnitActor (单位; 持兵种 unit_class + RtsUnitAttributeSet)
##   - RtsBuildingActor (建筑骨架; Phase 2 P2.5 填工厂 + production_state)
##
## 与 hex_battle_actor 同构:
##   - get_attribute_set() 由子类按强类型返回; 公共代码读 hp/max_hp 走基类视图
##   - _on_id_assigned 同步 ability_set.owner_actor_id + attribute_set.actor_id
##   - check_death 由数据驱动(hp <= 0)
##   - 死亡 actor 不再响应 PreEvent handler
##
## 决策来源: architecture-baseline.md §4 (RtsBattleActor 基类骨架)
class_name RtsBattleActor
extends Actor


# ========== 公共字段 ==========

## 连续逻辑坐标(像素), 替代 hex_position; 与 hex 一样为"事实", 直接被 nav agent 写。
var position_2d: Vector2 = Vector2.ZERO

## 当前帧速度(像素/秒); steering / nav 推路径时由组件写入, 仅信息性。
var velocity: Vector2 = Vector2.ZERO

## 圆形碰撞半径(像素), WC3 风连续 float (决策 F)。
## 标准单位 14, 小型 10-12, 大型 32-40 (architecture-baseline.md §7)。
var collision_radius: float = 14.0

## 移动层(GROUND / AIR); 决定 pathing is_passable 与武器 target_layer_mask。
## Phase 1 全 GROUND; Phase 2 P2.8 加飞行单位时用到 AIR。
var movement_layer: int = MovementLayer.Layer.GROUND

## 队伍 ID (0=left, 1=right; -1=未分配)
var team_id: int = -1

## AbilitySet — 战斗管线平权: cooldown / buff / passive 都挂这里。
## 子类负责实例化(Unit 用 actor.get_id() + RtsUnitAttributeSet; Building 在 P2.5 填)。
var ability_set: AbilitySet = null

## 碰撞 / 被推时的结算数据(占位; M1 暂不用, 留着与 hex 接口对齐)。
var collision_profile: CollisionProfile = null

## 死亡标志(数据驱动: hp <= 0 时 check_death 设置)
var _is_dead: bool = false


# ========== 队伍 ==========

func set_team_id(p_team_id: int) -> void:
	team_id = p_team_id
	_team = str(p_team_id)


func get_team_id() -> int:
	return team_id


# ========== Actor 合同 ==========

## ID 被 add_actor 分配后, 同步 ability_set / attribute_set 内引用的 owner_id。
## 子类若额外字段需绑定, override 后调 super._on_id_assigned()。
func _on_id_assigned() -> void:
	if ability_set != null:
		ability_set.owner_actor_id = get_id()
	var attrs := get_attribute_set()
	if attrs != null:
		attrs.actor_id = get_id()


# ========== AbilitySet 协议 ==========

## RtsBattleProcedure / event 系统通过 has_method("get_ability_set") 探测; 显式提供。
func get_ability_set() -> AbilitySet:
	return ability_set


# ========== 公共合同(子类必须实现) ==========

## 获取 attribute_set 的基类视图。子类返回自己的强类型字段。
## Phase 1 RTS 没有跨子类共享的 attribute_set 基类(hex 走 HexBattleActorAttributeSet);
## 子类 override 时返回各自的强类型即可, 调方读 hp/max_hp 走 BaseGeneratedAttributeSet 公共接口。
func get_attribute_set() -> BaseGeneratedAttributeSet:
	return null


# ========== 死亡 ==========

## 数据驱动死亡判定 — 子类 override 以接入自己的 attribute_set。
## 默认实现: hp <= 0 且未死 → 标记死亡, 返回 true (首次)。
func check_death() -> bool:
	var attrs := get_attribute_set()
	if attrs == null:
		return false
	if attrs.get_current_value("hp") <= 0.0 and not _is_dead:
		_is_dead = true
		return true
	return false


func is_dead() -> bool:
	return _is_dead


## 标记为死亡(由 attack action 在伤害结算后调用)。
func mark_dead() -> void:
	_is_dead = true


## 死亡 actor 不再响应 PreEvent handler, 与 hex 例子一致。
func is_pre_event_responsive() -> bool:
	return not _is_dead


# ========== Footprint / Pathing 写入 ==========

## 占用的格子列表(子类按 footprint 大小 override)。
## 默认: 中心位置所在的单 cell(适合 1×1 单位)。
##
## Building 的多 cell footprint 在 Phase 2 P2.5 填具体实现; Phase 1 留契约。
func get_footprint_cells(grid) -> Array:
	if grid == null:
		return []
	var coord = grid.world_to_coord(position_2d)
	return [coord]


## 是否写入 pathing map(WC3 风: 单位不写, 建筑写)。
## RtsUnitActor 默认 false, RtsBuildingActor override 为 true。
func writes_to_pathing_map() -> bool:
	return false


# ========== 录像支持 ==========

## 渲染高度(D3-D 视觉提示; AIR 单位画在 8px 上空)。
## 仅 frontend 渲染消费; logic 不读。
func get_render_height() -> float:
	if movement_layer == MovementLayer.Layer.AIR:
		return 8.0
	return 0.0


## 用 Vector2 (x, y) 当 Vector3 (x, y, 0) 暴露给 BattleRecorder。
## configs.positionFormats["Character"] = "rts2d" 让渲染层正确解释。
##
## 注: M1 Phase 1 保留 M0 的 (x, y, 0) lift 格式; Phase 2 P2.7 接通流式 recorder 时
## 可切到 baseline §4 推荐的 (x, render_height, y) 格式。
func _get_position() -> Vector3:
	return Vector3(position_2d.x, position_2d.y, 0.0)


func _get_team_int() -> int:
	return team_id
