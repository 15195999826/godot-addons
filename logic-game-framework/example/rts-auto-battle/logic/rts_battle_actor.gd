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


# ========== P2.8: 攻击 / 目标 共享字段(单位 + 建筑 都用) ==========

## 当前正在打的目标 actor id; 空表示没目标。
## P1.5 起 unit 的 RtsUnitController 维护; P2.8 起 building 的 procedure 攻击循环也写。
##
## TargetSelector (RtsTargetSelectors.CurrentUnitTarget) 读此字段定位攻击目标 — 故 attacker 必须
## 在调 BasicAttackAction 之前把 cached target 写进 current_target_id。
var current_target_id: String = ""

## P2.8 — 攻击者武器的 layer mask: bit i = 1 表示能命中 movement_layer = i 的目标。
## 详见 MovementLayer.MASK_* 与 RtsWeaponConfig。
##
## 默认 0 = 不攻击 (兵营 / 水晶塔 / 不持武器的 actor); 子类按 unit_class / building_kind 覆盖。
var target_layer_mask: int = MovementLayer.MASK_NONE

## P2.4 — 单位归类 tag, 供敌方 target_priorities 匹配 / debug 用。
##
## 默认 [] (无 tag, AutoTargetSystem 退化按距离选最近)。子类按 unit_class / building_kind 覆盖:
##   - melee unit → ["melee", "ground"]
##   - flying unit → ["flying", "air"]
##   - barracks → ["building", "barracks"]
##   - crystal_tower → ["building", "crystal_tower", "priority_target"]
var unit_tags: Array[String] = []

## P2.4 — 目标优先级表 [{tag: String, weight: float}, ...]; AutoTargetSystem 用此评分。
##
## 默认 [] = 仅按距离选最近 (Phase 1 行为兼容); 特定单位类型可在 actor 上 override。
var target_priorities: Array[Dictionary] = []

## P2.4 — AutoTargetSystem 写入的目标缓存 actor id (空=暂无目标)。
## 每 RESCAN_INTERVAL_TICKS (20) tick 全量重算; 目标死亡当 tick 立即重算 (不等下个 scan)。
##
## P2.8: 单位 + 建筑 都用此字段。
##   - 单位: RtsBasicAttackStrategy.decide 读, 决定 AttackActivity target_id
##   - 建筑: procedure 攻击循环直接读 (建筑没 strategy / activity, 直接 attack 范围内目标)
var _cached_target_id: String = ""


# ========== P2.8: 攻击协议 (子类按需 override) ==========

## 攻击力。子类按数据源 override:
##   - RtsUnitActor → return attribute_set.atk
##   - RtsBuildingActor → return atk_value (从 RtsBuildingConfig 注入的 plain float 字段)
##
## 默认 0 (基类不参战)。
func get_atk() -> float:
	return 0.0


## 防御力。同上。
func get_def() -> float:
	return 0.0


## 攻击距离 (像素, 平方比较)。同上。
func get_attack_range() -> float:
	return 0.0


## 攻击频率 (次/秒, basic attack cooldown = 1 / attack_speed)。同上。
func get_attack_speed() -> float:
	return 0.0


## 共享 cooldown tag id (与 P1.6 一致, 单位 + 建筑都用同一 tag string)。
const ATTACK_COOLDOWN_TAG: String = "rts_attack_cooldown"


## 是否冷却中 (查 ability_set.tag_container 上的 attack_cooldown tag)。
##
## 单位/建筑 共用此实现 — 都靠 ability_set.add_auto_duration_tag 计冷却时长。
func is_attack_on_cooldown() -> bool:
	if ability_set == null:
		return false
	return ability_set.has_tag(ATTACK_COOLDOWN_TAG)


## 是否冷却完毕、可发起 basic attack (and not dead, and 持武器)。
##
## P2.8: 加 target_layer_mask != 0 — mask=0 的 actor (兵营 / 水晶塔) 不参战。
func can_attack() -> bool:
	if is_dead():
		return false
	if target_layer_mask == MovementLayer.MASK_NONE:
		return false
	return not is_attack_on_cooldown()


## 启动 attack cooldown — 走 LGF tag-duration 机制。
##
## 单位/建筑 共用此实现; 时长 = 1000 / attack_speed (ms)。
func start_attack_cooldown() -> void:
	if ability_set == null:
		return
	var atk_speed: float = get_attack_speed()
	var duration_ms: float = 1000.0 / atk_speed if atk_speed > 0.0 else 99999000.0
	ability_set.add_auto_duration_tag(ATTACK_COOLDOWN_TAG, duration_ms)


# ========== 队伍 ==========

func set_team_id(p_team_id: int) -> void:
	team_id = p_team_id
	set_team(str(p_team_id))


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
