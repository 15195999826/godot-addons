extends RefCounted
class_name ActivationError

var code: String
var message: String

func _init(code_value: String, message_value: String) -> void:
	code = code_value
	message = message_value

static func create(code_value: String, message_value: String) -> ActivationError:
	return ActivationError.new(code_value, message_value)
