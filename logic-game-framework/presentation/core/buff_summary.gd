## BuffSummary - 账本上的 buff 摘要
##
## 跟 HP / position 一样,是 ActorVisualState 的一部分,纯表演层状态。
## 来源:项目翻译员翻译事件流产生 VisualBuffStateAction,VisualUpdater 应用到 actor.buffs 数组上。
##
## id 取 ability 实例 id(不是 config_id),支持同一 actor 多个独立 buff 实例。
class_name BuffSummary
extends RefCounted


var id: String = ""
var config_id: String = ""
var display_name: String = ""
var short: String = ""
var color: Color = Color.WHITE
var primary: float = 0.0


func duplicate() -> BuffSummary:
	var copy := BuffSummary.new()
	copy.id = id
	copy.config_id = config_id
	copy.display_name = display_name
	copy.short = short
	copy.color = color
	copy.primary = primary
	return copy
