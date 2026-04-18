class_name Actor
extends RefCounted

var _id: String = ""
var _instance_id: String = ""
var type: String = "actor"
var _team: String = ""
var _display_name: String = ""
var _on_spawn_callbacks: Array[Callable] = []
var _on_despawn_callbacks: Array[Callable] = []


## 获取 Actor ID
## 如果 ID 未初始化，返回空字符串
func get_id() -> String:
	return _id


## 检查 ID 是否有效（已初始化）
func is_id_valid() -> bool:
	return _id != ""


## 设置 Actor ID（由 GameplayInstance.add_actor 调用）
func set_id(id_value: String) -> void:
	_id = id_value


## ID 被 add_actor 分配后的回调（子类可覆盖）
## 用于同步内部引用了旧 ID 的组件（如 AbilitySet.owner_actor_id）
func _on_id_assigned() -> void:
	pass


## 获取所属 GameplayInstance 的 ID
func get_gameplay_instance_id() -> String:
	return _instance_id


## 获取所属 GameplayInstance
## 通过 GameWorld 查询，避免循环引用
func get_owner_gameplay_instance() -> GameplayInstance:
	if _instance_id.is_empty():
		return null
	return GameWorld.get_instance_by_id(_instance_id)


## 是否响应 PreEvent handler 分发
##
## 由于 PreEvent handler 注册在 EventProcessor 全局表，事件触发时框架
## 会自动遍历所有已注册 handler。此函数给子类一个机会说"我此刻不响应"，
## 避免状态异常的 actor（如死亡、沉默、眩晕）意外触发被动。
##
## 其它触发路径（POST event / tick / receive_event）由项目层自行决定
## 何时调用、传哪些 actor，不受此函数影响。
##
## 默认返回 true。子类按游戏规则覆盖。
func is_pre_event_responsive() -> bool:
	return true


func get_team() -> String:
	return _team

func set_team(value: String) -> void:
	_team = value

func get_display_name() -> String:
	if _display_name != "":
		return _display_name
	return "%s_%s" % [type, get_id()]

func set_display_name(value: String) -> void:
	_display_name = value

func on_spawn() -> void:
	for callback in _on_spawn_callbacks:
		if callback.is_valid():
			callback.call()

func on_despawn() -> void:
	for callback in _on_despawn_callbacks:
		if callback.is_valid():
			callback.call()

func add_spawn_listener(callback: Callable) -> Callable:
	_on_spawn_callbacks.append(callback)
	return func() -> void:
		var index := _on_spawn_callbacks.find(callback)
		if index != -1:
			_on_spawn_callbacks.remove_at(index)

func add_despawn_listener(callback: Callable) -> Callable:
	_on_despawn_callbacks.append(callback)
	return func() -> void:
		var index := _on_despawn_callbacks.find(callback)
		if index != -1:
			_on_despawn_callbacks.remove_at(index)

func serialize_base() -> Dictionary:
	return {
		"id": get_id(),
		"type": type,
		"team": _team,
		"displayName": _display_name,
	}


# ========== 录像支持（BattleRecorder 接口） ==========

## Actor ID（BattleRecorder 兼容属性）
var id: String:
	get:
		return get_id()

## 配置 ID（子类应覆盖 _get_config_id 方法）
var config_id: String:
	get:
		return _get_config_id()

## 显示名称（BattleRecorder 兼容属性）
var display_name: String:
	get:
		return get_display_name()
	set(value):
		set_display_name(value)

## 队伍（BattleRecorder 兼容属性，子类应覆盖 _get_team_int 方法）
var team: int:
	get:
		return _get_team_int()

## 位置（子类应覆盖 _get_position 方法）
var position: Vector3:
	get:
		return _get_position()


## 获取配置 ID（子类可覆盖）
func _get_config_id() -> String:
	return type


## 获取队伍 ID（子类可覆盖）
func _get_team_int() -> int:
	return int(_team) if _team.is_valid_int() else 0


## 获取位置（子类可覆盖）
func _get_position() -> Vector3:
	return Vector3.ZERO


## 获取位置快照
## 返回 [x, y, z] 格式的数组，用于录像存储
## 具体含义（hex/world/tile）由 configs.positionFormats 声明，渲染层解释
func get_position_snapshot() -> Array[float]:
	var pos := _get_position()
	return [pos.x, pos.y, pos.z]


## 设置录像回调（BattleRecorder 调用）
## 子类可覆盖此方法以订阅事件并返回取消订阅的回调数组
func setup_recording(_ctx: RecordingContext) -> Array[Callable]:
	return []


## 获取属性快照（子类应覆盖）
func get_attribute_snapshot() -> Dictionary:
	return {}


## 获取 Ability 快照（子类应覆盖）
func get_ability_snapshot() -> Array[Dictionary]:
	return []


## 获取 Tag 快照（子类应覆盖）
func get_tag_snapshot() -> Dictionary:
	return {}
