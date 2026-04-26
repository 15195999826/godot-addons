## FrontendBuffSummary - frontend 渲染层的 buff 摘要数据
##
## 跟 HP / position 一样,是 ActorRenderState 的一部分,纯 frontend 状态。
## 来源:BuffVisualizer 翻译事件流(AbilityGranted / AbilityStacksChanged /
## AbilityRemoved / DamageEvent.consumption_records)产生 ApplyBuffStateAction,
## RenderWorld 应用到 actor.buffs 数组上。
##
## id 取 ability 实例 id(不是 config_id),支持同一 actor 多个独立 buff 实例。
class_name FrontendBuffSummary
extends RefCounted


## ability 实例 id(用于 update / remove 时定位)
var id: String = ""

## ability config_id(用于查 BuffVisualizer 白名单决定 short / color)
var config_id: String = ""

## 显示名(预留 tooltip 用,第一版不画)
var display_name: String = ""

## 单字母缩写,例 "P" "S" "V" "T" "G"
var short: String = ""

## 色块颜色
var color: Color = Color.WHITE

## 关键数字:Poison=stacks,Ward=current shield,纯被动=0
var primary: float = 0.0


func duplicate() -> FrontendBuffSummary:
	var copy := FrontendBuffSummary.new()
	copy.id = id
	copy.config_id = config_id
	copy.display_name = display_name
	copy.short = short
	copy.color = color
	copy.primary = primary
	return copy
