class_name TimeDurationConfig
extends AbilityComponentConfig
## TimeDuration 组件配置
##
## 定义持续时间的配置数据，由 Ability._resolve_components() 解析为 TimeDurationComponent 实例。
## 每个 Ability 实例独立创建 Component，避免共享状态污染。
##
## 使用示例：
## [codeblock]
## .component_config(TimeDurationConfig.new(2000.0))  # 持续 2 秒
## [/codeblock]


## 持续时间（毫秒）
var duration_ms: float


func _init(duration_ms: float = 0.0) -> void:
	self.duration_ms = duration_ms


## 创建对应的 TimeDurationComponent 实例
func create_component() -> AbilityComponent:
	return TimeDurationComponent.new(duration_ms)
