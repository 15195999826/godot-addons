## VisualizerRegistry - Visualizer 注册表
##
## 管理所有 Visualizer 的注册和事件分发。
## 支持多个 Visualizer 协作处理同一事件。
##
## 设计决策：收集所有匹配的 Visualizer 结果
## 原因：一个事件可能需要多个 Visualizer 协作
## 例如：DamageEvent 同时触发 DamageVisualizer（飘字）+ ScreenShakeVisualizer（震屏）
class_name FrontendVisualizerRegistry
extends RefCounted


# ========== 属性 ==========

## 已注册的 Visualizer 列表
var _visualizers: Array[FrontendBaseVisualizer] = []

## 是否启用调试模式
var _debug_mode: bool = false


# ========== 注册方法 ==========

## 注册 Visualizer
func register(visualizer: FrontendBaseVisualizer) -> FrontendVisualizerRegistry:
	_visualizers.append(visualizer)
	return self


## 批量注册 Visualizer
func register_all(visualizers: Array[FrontendBaseVisualizer]) -> FrontendVisualizerRegistry:
	for v: FrontendBaseVisualizer in visualizers:
		register(v)
	return self


## 启用/禁用调试模式
func set_debug_mode(enabled: bool) -> FrontendVisualizerRegistry:
	_debug_mode = enabled
	return self


# ========== 翻译方法 ==========

## 翻译事件为视觉动作
## 遍历所有注册的 Visualizer，收集能处理该事件的所有结果
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var actions: Array[FrontendVisualAction] = []
	var event_kind: String = event.get("kind", "unknown")
	
	for visualizer: FrontendBaseVisualizer in _visualizers:
		if visualizer.can_handle(event):
			var result: Array[FrontendVisualAction] = visualizer.translate(event, context)
			actions.append_array(result)
			if _debug_mode:
				Log.debug("VisualizerRegistry", "%s -> %s 生成 %d 个动作" % [
					event_kind, visualizer.visualizer_name, result.size()
				])
	
	return actions


## 批量翻译事件
func translate_all(events: Array[Dictionary], context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var actions: Array[FrontendVisualAction] = []
	for event: Dictionary in events:
		actions.append_array(translate(event, context))
	return actions


# ========== 查询方法 ==========

## 检查是否有 Visualizer 能处理指定事件类型
func has_visualizer_for(event_kind: String) -> bool:
	var test_event := { "kind": event_kind }
	for visualizer: FrontendBaseVisualizer in _visualizers:
		if visualizer.can_handle(test_event):
			return true
	return false


## 获取能处理指定事件类型的 Visualizer 名称列表
func get_visualizers_for(event_kind: String) -> Array[String]:
	var test_event := { "kind": event_kind }
	var names: Array[String] = []
	for visualizer: FrontendBaseVisualizer in _visualizers:
		if visualizer.can_handle(test_event):
			names.append(visualizer.visualizer_name)
	return names


## 获取已注册的 Visualizer 数量
func get_count() -> int:
	return _visualizers.size()


## 获取所有已注册的 Visualizer 名称
func get_registered_names() -> Array[String]:
	var names: Array[String] = []
	for visualizer: FrontendBaseVisualizer in _visualizers:
		names.append(visualizer.visualizer_name)
	return names
