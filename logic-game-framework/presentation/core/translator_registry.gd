## TranslatorRegistry - 翻译员注册表
##
## 管理所有翻译员的注册和事件分发。
## 支持多个翻译员协作处理同一事件。
##
## 设计决策：收集所有能处理的翻译员结果
## 原因：一个事件可能需要多个翻译员协作
## 例如：伤害事件同时触发飘字翻译员（飘字）+ buff 翻译员（护盾余量）
class_name TranslatorRegistry
extends RefCounted


# ========== 属性 ==========

## 已注册的翻译员列表
var _translators: Array[Translator] = []

## 是否启用调试模式
var _debug_mode: bool = false


# ========== 注册方法 ==========

## 注册翻译员
func register(translator: Translator) -> TranslatorRegistry:
	_translators.append(translator)
	return self


## 批量注册翻译员
func register_all(translators: Array[Translator]) -> TranslatorRegistry:
	for t: Translator in translators:
		register(t)
	return self


## 启用/禁用调试模式
func set_debug_mode(enabled: bool) -> TranslatorRegistry:
	_debug_mode = enabled
	return self


# ========== 翻译方法 ==========

## 翻译事件为卡片
## 遍历所有注册的翻译员，收集能处理该事件的所有结果
func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]:
	var actions: Array[VisualAction] = []
	var event_kind: String = event.get("kind", "unknown")

	for translator: Translator in _translators:
		if translator.can_handle(event):
			var result: Array[VisualAction] = translator.translate(event, query)
			actions.append_array(result)
			if _debug_mode:
				Log.debug("TranslatorRegistry", "%s -> %s 生成 %d 张卡片" % [
					event_kind, translator.translator_name, result.size()
				])

	return actions


## 批量翻译事件
func translate_all(events: Array[Dictionary], query: VisualStateQuery) -> Array[VisualAction]:
	var actions: Array[VisualAction] = []
	for event: Dictionary in events:
		actions.append_array(translate(event, query))
	return actions


# ========== 查询方法 ==========

## 检查是否有翻译员能处理指定事件类型
func has_translator_for(event_kind: String) -> bool:
	var test_event := { "kind": event_kind }
	for translator: Translator in _translators:
		if translator.can_handle(test_event):
			return true
	return false


## 获取能处理指定事件类型的翻译员名称列表
func get_translators_for(event_kind: String) -> Array[String]:
	var test_event := { "kind": event_kind }
	var names: Array[String] = []
	for translator: Translator in _translators:
		if translator.can_handle(test_event):
			names.append(translator.translator_name)
	return names


## 获取已注册的翻译员数量
func get_count() -> int:
	return _translators.size()


## 获取所有已注册的翻译员名称
func get_registered_names() -> Array[String]:
	var names: Array[String] = []
	for translator: Translator in _translators:
		names.append(translator.translator_name)
	return names
