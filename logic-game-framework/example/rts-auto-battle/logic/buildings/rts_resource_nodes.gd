## RtsResourceNodes - RTS 资源节点工厂 (M2.1 Phase B)
##
## 与 RtsBuildings 同构: create_<kind>() 返回已配齐字段的 RtsResourceNode 实例。调方 set
## team_id (推荐 -1 中立) + position_2d + world.add_actor 即可 (不需 grid.place_building, 因 D2
## 不阻挡决策 — worker 可踩 ResourceNode 简化 Phase C 寻路)。
##
## 例 (smoke_resource_nodes 调用):
##
##   var gold := RtsResourceNodes.create_gold_node()
##   gold.set_team_id(-1)
##   gold.position_2d = Vector2(250, 200)
##   world.add_actor(gold)
##
## 决策来源: phase-b-resource-nodes.md §AC3
class_name RtsResourceNodes


# ========== 工厂方法 ==========

## 金矿: 起手 amount=1500, Phase B 不消减; Phase C HarvestActivity 减 amount。
static func create_gold_node() -> RtsResourceNode:
	return RtsResourceNode.new(RtsResourceNodeConfig.FieldKind.GOLD)


## 木材: 起手 amount=1500, 同上。
static func create_wood_node() -> RtsResourceNode:
	return RtsResourceNode.new(RtsResourceNodeConfig.FieldKind.WOOD)
