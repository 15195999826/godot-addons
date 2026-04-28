## FrontendShieldSummary - frontend 渲染层的护盾摘要数据
##
## ActorRenderState.shields 数组的元素。来源:ShieldBarVisualizer 翻译事件流
## (AbilityGranted / AbilityRemoved / DamageEvent.consumption_records)产生
## ApplyShieldStateAction,RenderWorld 应用到 actor.shields 数组。
##
## 与 BuffSummary 互补:BuffSummary 是头顶 chip 的视觉摘要;ShieldSummary 是
## 血条上方独立护盾条的数据,保留多盾粒度(current/capacity/priority)给将来
## 分段显示 / 按来源分色用。
##
## id 取 ability 实例 id,支持同一 actor 多个独立 shield 实例(stacking_policy
## = "independent" 的 ward 重复施放)。
class_name FrontendShieldSummary
extends RefCounted


var id: String = ""
var config_id: String = ""
var current: float = 0.0
var capacity: float = 0.0
var color: Color = Color.WHITE
var priority: int = 0


func duplicate() -> FrontendShieldSummary:
	var copy := FrontendShieldSummary.new()
	copy.id = id
	copy.config_id = config_id
	copy.current = current
	copy.capacity = capacity
	copy.color = color
	copy.priority = priority
	return copy


## 从 ability.serialize() payload 里找出 ShieldComponent 的 data dict。
## 找不到返回空 dict;不抛错(不是所有 ability 都带 ShieldComponent)。
##
## 共享 helper:BuffVisualizer 的 SHIELD_REMAINING primary_source 解析也走这条。
static func find_shield_component_data(payload: Dictionary) -> Dictionary:
	var components: Array = payload.get("components", [])
	for comp_variant in components:
		var comp: Dictionary = comp_variant
		if comp.get("type", "") == "ShieldComponent":
			return comp.get("data", {})
	return {}
