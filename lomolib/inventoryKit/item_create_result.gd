## InventoryKit - 物品创建结果
##
## ItemSystem.create_item() 的返回值。
## 语义:
## - created_item_ids: 本次新建的 item ids
## - updated_item_ids: 本次 stack merge 修改过 count 的已有 item ids
## - remaining_count: 因容量或规则限制未创建 / 未合并的数量 (V1 测试背包容量足够,正常 = 0)
class_name ItemCreateResult
extends RefCounted


var success: bool = false
var error_message: String = ""
var created_item_ids: Array[int] = []
var updated_item_ids: Array[int] = []
var remaining_count: int = 0


static func ok(created: Array[int], updated: Array[int] = [], remaining: int = 0) -> ItemCreateResult:
	var r := ItemCreateResult.new()
	r.success = true
	r.created_item_ids = created.duplicate()
	r.updated_item_ids = updated.duplicate()
	r.remaining_count = remaining
	return r


static func fail(error: String, remaining: int = 0) -> ItemCreateResult:
	var r := ItemCreateResult.new()
	r.success = false
	r.error_message = error
	r.remaining_count = remaining
	return r
