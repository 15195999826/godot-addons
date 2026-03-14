class_name IGameStateProvider
## 静态接口检测工具类
##
## 用于检测对象是否实现 "GameStateProvider" 协议：
## - get_logic_time() -> float
##
## 使用示例：
##   var logic_time := IGameStateProvider.get_logic_time(game_state_provider)
##
## 注意：框架层只依赖 get_logic_time()，其他方法（如 get_actor）
## 应通过 GameWorld.get_actor() 或项目层的 Utils 类访问。


## 安全获取逻辑时间
## 如果对象未实现协议，返回当前系统时间（毫秒）
static func get_logic_time(provider: Variant) -> float:
	if provider != null and provider is Object and provider.has_method("get_logic_time"):
		return float(provider.get_logic_time())
	return float(Time.get_ticks_msec())


## 检查对象是否实现协议
static func is_implemented(provider: Variant) -> bool:
	return provider != null and provider is Object and provider.has_method("get_logic_time")
