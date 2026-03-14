extends Node

static var _counter: int = 0

static func generate_id(prefix: String) -> String:
	var value := "%s_%d" % [prefix, _counter]
	_counter += 1
	return value

static func reset_id_counter() -> void:
	_counter = 0

var _prefix: String

func _init(prefix: String = "") -> void:
	_prefix = prefix

func generate_with_prefix() -> String:
	return IdGenerator.generate_id(_prefix)

static func generate(prefix: String = "") -> String:
	return IdGenerator.generate_id(prefix)
