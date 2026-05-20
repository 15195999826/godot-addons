## TagComponentConfig - TagComponent 的正式 AbilityComponentConfig
##
## §0.1: 把 example 内 ad-hoc 的 `StatusTagConfig` 收回 core 层，让 component tag
## 配置语义统一。Component tag 跟随 Ability 实例 grant/remove 自动添加/清理；不需要
## 在 NoInstanceConfig.on_apply_actions 里手写 loose tag mutation 表达"Ability 存在期间
## 持有一组标签"。
##
## 用法:
##     TagComponentConfig.builder()
##         .tag("action_locked")
##         .tag("cant_act")
##         .optional_tag(reason_tag)  # reason_tag 可能为空字符串
##         .build()
##
## 边界:
## - 不用于 Stance: 切换姿态依赖 loose tag 与 LooseTagAction;
##   Stance 切换的不是 ability 生命周期。
## - 不用于 status_action_lock 的 cant_act 替代 loose tag: 多个 action lock
##   实例重叠时 loose remove 会误删其它实例的状态。Component tag 不存在这种污染。
class_name TagComponentConfig
extends AbilityComponentConfig


## tag → stacks (默认 1)
var _tags: Dictionary = {}


func _init(tags_value: Dictionary = {}) -> void:
	_tags = tags_value.duplicate(true)


func create_component() -> AbilityComponent:
	return TagComponent.new({ "tags": _tags })


func tags_dict() -> Dictionary:
	return _tags.duplicate(true)


static func builder() -> TagComponentConfigBuilder:
	return TagComponentConfigBuilder.new()


class TagComponentConfigBuilder:
	extends RefCounted

	var _tags: Dictionary = {}

	## 添加单个 tag (默认 1 stack)
	func tag(tag_name: String, stacks: int = 1) -> TagComponentConfigBuilder:
		Log.assert_crash(not tag_name.is_empty(),
			"TagComponentConfig", "tag name must not be empty")
		_tags[tag_name] = stacks
		return self

	## tag_name 可能为空时使用 (例: status reason tag 是可选的)
	func optional_tag(tag_name: String, stacks: int = 1) -> TagComponentConfigBuilder:
		if not tag_name.is_empty():
			_tags[tag_name] = stacks
		return self

	## 一次性批量添加
	func tags(tags_dict: Dictionary) -> TagComponentConfigBuilder:
		for k in tags_dict.keys():
			_tags[k] = tags_dict[k]
		return self

	func build() -> TagComponentConfig:
		Log.assert_crash(not _tags.is_empty(),
			"TagComponentConfig", "at least one tag is required")
		return TagComponentConfig.new(_tags)
