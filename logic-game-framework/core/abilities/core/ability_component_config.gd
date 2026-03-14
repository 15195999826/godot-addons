class_name AbilityComponentConfig
## AbilityComponent 配置基类
##
## 所有 AbilityComponent 的配置类都应继承此类，并实现 create_component()。
## Ability._resolve_components() 通过多态调用 create_component() 创建组件实例，
## 无需类型分发。


## 创建对应的 AbilityComponent 实例。子类必须覆盖。
func create_component() -> AbilityComponent:
	Log.assert_crash(false, "AbilityComponentConfig", "create_component() must be overridden by " + get_script().get_global_name())
	return null
