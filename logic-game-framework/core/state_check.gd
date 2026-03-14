## 共享实例（Action/Condition/Cost）的状态检测工具
##
## 用于验证共享实例在 execute()/check()/pay() 执行前后状态未发生变化。
## 通过项目设置 logic_game_framework/debug/action_state_check 启用。
##
## 使用方式：
## [codeblock]
## # 在共享实例基类中：
## var _frozen_hash: int = 0
##
## func _freeze() -> void:
##     _frozen_hash = StateCheck.freeze(self)
##
## func _verify_unchanged() -> void:
##     StateCheck.verify(self, _frozen_hash, "Action")
## [/codeblock]
class_name StateCheck


## 检查是否启用状态检测（通过项目设置控制）
static func is_enabled() -> bool:
	return ProjectSettings.get_setting("logic_game_framework/debug/action_state_check", false)


## 冻结对象，返回状态 hash（未启用时返回 0）
static func freeze(obj: Object) -> int:
	if not is_enabled():
		return 0
	return compute_hash(obj)


## 验证对象状态未被修改（frozen_hash 为 0 表示未启用，跳过）
static func verify(obj: Object, frozen_hash: int, label: String) -> void:
	if frozen_hash == 0:
		return
	var current := compute_hash(obj)
	Log.assert_crash(current == frozen_hash, "StateCheck", "%s state modified during execution! %s" % [label, obj.get_script().resource_path])


## 计算对象所有脚本变量的 hash（排除 _frozen 前缀变量）
static func compute_hash(obj: Object) -> int:
	var parts: Array[String] = []
	for prop in obj.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var prop_name: String = prop.name
			if not prop_name.begins_with("_frozen"):
				var value: Variant = obj.get(prop_name)
				parts.append("%s=%s" % [prop_name, str(value)])
	return hash(",".join(parts))
