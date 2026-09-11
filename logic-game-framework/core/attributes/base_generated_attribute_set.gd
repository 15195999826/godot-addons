class_name BaseGeneratedAttributeSet
extends RefCounted
## 生成的 AttributeSet 基类
##
## 所有由 AttributeSetGeneratorScript 生成的类都继承此基类。
## 提供统一的变化监听接口，供 RecordingUtils 使用。
## 对外抛出 GameEvent.AttributeChanged 事件（内部 RawAttributeSet 仍使用 Dictionary）。

## 底层属性集（子类在 _init 中通过 _raw.apply_config() 配置）
var _raw: RawAttributeSet

## 所属 Actor 的 ID，用于构造 GameEvent.AttributeChanged
var actor_id: String


func _init(p_actor_id: String = "") -> void:
	_raw = RawAttributeSet.new()
	actor_id = p_actor_id


## 添加变化监听器
## @param listener 监听回调，接收 GameEvent.AttributeChanged 参数
## @return 取消订阅函数
func add_change_listener(listener: Callable) -> Callable:
	var wrapper := func(raw_event: Dictionary) -> void:
		listener.call(GameEvent.AttributeChanged.create(
			actor_id,
			raw_event.get("attribute_name", ""),
			raw_event.get("old_value", 0.0),
			raw_event.get("new_value", 0.0),
		))
	_raw.add_change_listener(wrapper)
	return func() -> void:
		_raw.remove_change_listener(wrapper)


## 获取底层 RawAttributeSet（供高级用法）
func get_raw() -> RawAttributeSet:
	return _raw
