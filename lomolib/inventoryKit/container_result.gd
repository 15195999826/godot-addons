## InventoryKit - 容器操作结果
##
## 用于表示容器操作的返回状态
class_name ContainerResult
extends RefCounted

## 是否成功
var success: bool = false

## 错误消息（失败时）
var error_message: String = ""

## 额外数据（可选）
var data: Variant = null


func _init(success_flag: bool = false, error: String = "", extra_data: Variant = null) -> void:
	success = success_flag
	error_message = error
	data = extra_data


## 创建成功结果
static func ok(extra_data: Variant = null) -> ContainerResult:
	return ContainerResult.new(true, "", extra_data)


## 创建失败结果
static func fail(error: String) -> ContainerResult:
	return ContainerResult.new(false, error, null)
