## InventoryKit - 物品移动结果
##
## ItemSystem.move_item() 的返回值。
## 语义:
## - success == false 时 UI / DevAgent 直接读 error_message 展示或断言失败原因
## - source_location / target_location 用于 UI 刷新和 DevAgent 验收;
##   失败时 target_location 表示尝试移动的目标位置
## - V1 不做 swap; 目标槽被占用时返回失败 result
class_name ItemMoveResult
extends RefCounted


var success: bool = false
var error_message: String = ""
var source_location: ItemLocation
var target_location: ItemLocation


static func ok(source: ItemLocation, target: ItemLocation) -> ItemMoveResult:
	var r := ItemMoveResult.new()
	r.success = true
	r.source_location = source.duplicate() if source != null else null
	r.target_location = target.duplicate() if target != null else null
	return r


static func fail(error: String, source: ItemLocation = null, target: ItemLocation = null) -> ItemMoveResult:
	var r := ItemMoveResult.new()
	r.success = false
	r.error_message = error
	r.source_location = source.duplicate() if source != null else null
	r.target_location = target.duplicate() if target != null else null
	return r
