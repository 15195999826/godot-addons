class_name Action
extends RefCounted


class BaseAction:
	extends RefCounted

	var type: String = "base"
	var _target_selector: TargetSelector
	var _frozen_hash: int = 0

	## 子类必须调用 super._init(target_selector)
	func _init(target_selector: TargetSelector) -> void:
		_target_selector = target_selector

	func execute(_ctx: ExecutionContext) -> ActionResult:
		return ActionResult.create_success_result([])

	func get_targets(ctx: ExecutionContext) -> Array[String]:
		return _target_selector.select(ctx)

	## 冻结 Action，记录当前状态 hash
	func _freeze() -> void:
		_frozen_hash = StateCheck.freeze(self)

	## 验证状态未被修改
	func _verify_unchanged() -> void:
		StateCheck.verify(self, _frozen_hash, "Action")


class NoopAction:
	extends BaseAction

	func _init(target_selector: TargetSelector) -> void:
		super._init(target_selector)
		type = "noop"

	func execute(_ctx: ExecutionContext) -> ActionResult:
		return ActionResult.create_success_result([])
