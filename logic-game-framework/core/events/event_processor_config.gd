## EventProcessorConfig - 事件处理器配置
##
## EventProcessor 的初始化配置。
##
## ========== 配置项 ==========
##
## - max_depth: 最大递归深度（防止无限循环），默认 10
## - trace_level: 追踪级别，默认 1
##   - 0: 不记录追踪
##   - 1: 记录基本追踪（事件、结果）
##   - 2: 记录详细追踪（包括每个处理器的意图）
##
## ========== 使用示例 ==========
##
## @example 创建配置
## ```gdscript
## var config := EventProcessorConfig.new(10, 2)
## var processor := EventProcessor.new(config)
## ```
class_name EventProcessorConfig
extends RefCounted


const DEFAULT_MAX_DEPTH := 10
const DEFAULT_TRACE_LEVEL := 1


## 最大递归深度
var max_depth: int

## 追踪级别
var trace_level: int


func _init(p_max_depth: int = DEFAULT_MAX_DEPTH, p_trace_level: int = DEFAULT_TRACE_LEVEL) -> void:
	max_depth = p_max_depth
	trace_level = p_trace_level


## 转换为 Dictionary
func to_dict() -> Dictionary:
	return {
		"maxDepth": max_depth,
		"traceLevel": trace_level,
	}
