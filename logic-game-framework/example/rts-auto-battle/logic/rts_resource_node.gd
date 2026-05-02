## RtsResourceNode - RTS 资源节点 actor (M2.1 Phase B)
##
## 与 RtsBuildingActor 平级 (都继承 RtsBattleActor, 不是 RtsUnitActor); 表示金矿 / 木材
## 等可被 worker 采集的中立资源点。Phase B 仅承载位置 + 数值占位 + idle 不被攻击; harvest 行为
## 在 Phase C 引入 RtsHarvestActivity 时实际消费 amount。
##
## 关键不变量 (D2 + D5):
##   - 不参战 — target_layer_mask = MASK_NONE, atk=0, attack_range=0
##   - 不阻挡 footprint (worker 可踩简化 path) — 不调 grid.place_building 注册 footprint cells
##   - team_id 默认 -1 (中立, 不入 left_team / right_team), 不影响 _check_battle_end
##   - is_dead 由 amount <= 0 驱动 (耗尽 = 死亡), 不依赖 attribute_set.hp
##   - 没 attribute_set / ability_set (不 tick cooldown / buff)
##
## 决策来源: phase-b-resource-nodes.md §AC2 + §设计决策 D2 / D5
class_name RtsResourceNode
extends RtsBattleActor


# ========== 字段 ==========

## 资源种类 (RtsResourceNodeConfig.FieldKind enum)
var field_kind: int = -1

## 起手最大资源量 (来自 config; Phase C harvest 时减)
var max_amount: int = 0

## 当前剩余资源量 (起手 = max_amount; Phase C HarvestActivity 每 tick 减 harvest_per_tick)
var amount: int = 0

## cache field_kind ↔ "gold"/"wood" key (Phase C drop-off 时直接读, 避免重复转换)
var field_kind_key: String = ""


# ========== 初始化 ==========

func _init(p_field_kind: int) -> void:
	field_kind = p_field_kind
	type = "ResourceNode"

	var stats := RtsResourceNodeConfig.get_stats(p_field_kind)
	_display_name = stats.name
	max_amount = stats.max_amount
	amount = stats.max_amount
	field_kind_key = RtsResourceNodeConfig.field_kind_to_resource_key(p_field_kind)

	# 不参战 (mask=NONE, layer=GROUND — worker 在地面采集)
	target_layer_mask = MovementLayer.MASK_NONE
	movement_layer = MovementLayer.Layer.GROUND
	# 与 melee unit 同, worker 距离判断走此值 (Phase C HarvestActivity 用)
	collision_radius = 12.0

	# tag: 供 debug / Phase C HarvestStrategy 过滤 (unit_tags.has("resource_node"))
	unit_tags = stats.actor_tags.duplicate()


# ========== RtsBattleActor 合同 override ==========

## ResourceNode 不参战 — 永远不能攻击。基类 mask=NONE 也返 false, 显式 override 让意图清晰。
func can_attack() -> bool:
	return false


## ResourceNode 死亡 = 耗尽 (与 unit/building 走 hp <= 0 不同)。Phase B amount 始终 = max_amount,
## 永远不死; Phase C harvest 减到 0 后 is_dead → AutoTarget / Activity 自然清理 (不需要 hp /
## attack action 路径)。`_is_dead` 字段保留供未来 Phase 强行 mark_dead 路径。
func is_dead() -> bool:
	return _is_dead or is_depleted()


## ResourceNode 没 attribute_set, check_death 永远 false (耗尽走 is_depleted 路径,
## 不走 hp <= 0 + check_death)。
func check_death() -> bool:
	return false


# ========== 查询 ==========

## 是否耗尽 (Phase C harvest 减到 0 → 节点消失)
func is_depleted() -> bool:
	return amount <= 0


# ========== 录像支持 ==========

func _get_config_id() -> String:
	if field_kind == RtsResourceNodeConfig.FieldKind.GOLD:
		return "resource_node_gold"
	if field_kind == RtsResourceNodeConfig.FieldKind.WOOD:
		return "resource_node_wood"
	return "resource_node"
