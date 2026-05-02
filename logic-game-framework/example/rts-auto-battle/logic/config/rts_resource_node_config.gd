## RtsResourceNodeConfig - RTS 资源节点数值表 (M2.1 Phase B)
##
## 与 RtsBuildingConfig 同构: 提供 FieldKind enum → StatBlock (max_amount / harvest_per_tick /
## footprint_size / actor_tags) 的查表方法。
##
## M2.1 Phase B 落地 2 种节点:
##   - GOLD : 金矿 (max_amount=1500; Phase B amount 始终 = max_amount, Phase C harvest 时减)
##   - WOOD : 木材 (同上)
##
## D1 决策: int enum 与 RTS 既有 UnitClass / Layer 风格一致; cost dict key 用 String 是因为
## Dictionary key 用 enum 不能 type 化; runtime field_kind ↔ team_resources key 映射用
## field_kind_to_resource_key(kind) helper 转换。
##
## 决策来源:
##   - phase-b-resource-nodes.md §AC1 + §设计决策 D1
class_name RtsResourceNodeConfig
extends RefCounted


## 资源种类枚举 (与 RtsBuildingConfig.cost dict key "gold" / "wood" 通过
## field_kind_to_resource_key 映射)。
enum FieldKind { GOLD = 0, WOOD = 1 }


## 单节点数值条目
class StatBlock:
	extends RefCounted
	var name: String = ""
	## 节点种类 (FieldKind)
	var field_kind: int = -1
	## 节点最大资源量 (起手 amount = max_amount, Phase C harvest 时减)
	var max_amount: int = 0
	## 每 tick harvest 时减少的资源量 (Phase B 不用, 占位 Phase C HarvestActivity)
	var harvest_per_tick: int = 0
	## footprint 尺寸 (D2 决策: ResourceNode 不阻挡 — 不调 grid.place_building 注册 footprint cells;
	## 字段供 Phase C HarvestActivity 路径辅助 / 渲染 / debug)
	var footprint_size: Vector2i = Vector2i(1, 1)
	## actor 归类 tag (供 debug / Phase C HarvestStrategy 通过 unit_tags.has("resource_node") 过滤)
	var actor_tags: Array[String] = []


const _GOLD_NODE_STATS := {
	"name": "Gold Field",
	"field_kind": FieldKind.GOLD,
	"max_amount": 1500,
	"harvest_per_tick": 0,
	"footprint_size": Vector2i(1, 1),
	"actor_tags": ["resource_node", "gold"],
}

const _WOOD_NODE_STATS := {
	"name": "Wood Field",
	"field_kind": FieldKind.WOOD,
	"max_amount": 1500,
	"harvest_per_tick": 0,
	"footprint_size": Vector2i(1, 1),
	"actor_tags": ["resource_node", "wood"],
}


## 取节点数值。返回 StatBlock (每次新建副本, 调方可改 amount / harvest_per_tick 不影响 const)。
## 未知 field_kind → Log.assert_crash, 与 RtsBuildingConfig.get_stats 一致。
static func get_stats(field_kind: int) -> StatBlock:
	var raw: Dictionary = {}
	match field_kind:
		FieldKind.GOLD:
			raw = _GOLD_NODE_STATS
		FieldKind.WOOD:
			raw = _WOOD_NODE_STATS
		_:
			Log.assert_crash(false, "RtsResourceNodeConfig", "Unknown FieldKind: %d" % field_kind)
	var block := StatBlock.new()
	block.name = raw["name"]
	block.field_kind = raw["field_kind"]
	block.max_amount = raw["max_amount"]
	block.harvest_per_tick = raw["harvest_per_tick"]
	block.footprint_size = raw["footprint_size"]
	var raw_tags: Array = raw.get("actor_tags", []) as Array
	var tags: Array[String] = []
	for tag in raw_tags:
		tags.append(str(tag))
	block.actor_tags = tags
	return block


## field_kind ↔ team_resources key 映射 (Phase C drop-off 时调:
## team_resources[field_kind_to_resource_key(node.field_kind)] += dropped_amount)。
##
## 未知 field_kind → Log.assert_crash, 与 cost dict key "gold" / "wood" 同口径。
static func field_kind_to_resource_key(field_kind: int) -> String:
	match field_kind:
		FieldKind.GOLD:
			return "gold"
		FieldKind.WOOD:
			return "wood"
		_:
			Log.assert_crash(false, "RtsResourceNodeConfig", "Unknown FieldKind: %d" % field_kind)
			return ""
