class_name IAbilitySetOwner
## 静态接口检测工具类
##
## 用于检测对象是否实现 "AbilitySetOwner" 协议：
## - get_ability_set() -> AbilitySet
##
## 使用示例：
##   var ability_set := IAbilitySetOwner.get_ability_set(actor)
##   if ability_set != null:
##       ability_set.apply_tag(...)


## 安全获取 AbilitySet
## 如果对象未实现协议，返回 null（不记录错误）
static func get_ability_set(owner: Object) -> AbilitySet:
	if owner == null:
		return null
	if not owner.has_method("get_ability_set"):
		return null
	return owner.get_ability_set()


## 检查对象是否实现协议
static func is_implemented(owner: Object) -> bool:
	return owner != null and owner.has_method("get_ability_set")
