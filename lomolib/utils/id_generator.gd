extends Node

## ID 生成器
## 提供全局唯一 ID 生成功能
## AutoLoad 名称: IdGenerator

static var _counter: int = 0

static func generate_id(prefix: String) -> String:
	var value := "%s_%d" % [prefix, _counter]
	_counter += 1
	return value

static func reset_id_counter() -> void:
	_counter = 0

var _prefix: String

func _init(prefix: String = ""):
	_prefix = prefix

func generate_with_prefix() -> String:
	return IdGenerator.generate_id(_prefix)

static func generate(prefix: String = "") -> String:
	return IdGenerator.generate_id(prefix)
