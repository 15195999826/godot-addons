class_name StackComponent
extends AbilityComponent
## 层数管理组件（设计阶段，尚未实际使用）
##
## 管理 Ability 的层数（stacks），支持三种溢出策略：
## - CAP: 达到上限后不再增加
## - REFRESH: 达到上限后不再增加，同时重置同 Ability 上 TimeDurationComponent 的剩余时间（TODO: 刷新逻辑未实现）
## - REJECT: 达到上限后拒绝添加

enum StackOverflowPolicy {
	CAP,
	REFRESH,
	REJECT,
}

var stacks: int
var max_stacks: int
var overflow_policy: StackOverflowPolicy

func _init(initial_stacks: int = 1, max_stacks_val: int = 1, policy: StackOverflowPolicy = StackOverflowPolicy.CAP) -> void:
	stacks = initial_stacks
	max_stacks = max_stacks_val
	overflow_policy = policy
	type = "StackComponent"

func get_stacks() -> int:
	return stacks

func get_max_stacks() -> int:
	return max_stacks

func is_full() -> bool:
	return stacks >= max_stacks

func add_stacks(count: int) -> int:
	var before := stacks
	var new_value := stacks + count

	match overflow_policy:
		StackOverflowPolicy.CAP:
			stacks = mini(new_value, max_stacks)
		StackOverflowPolicy.REFRESH:
			# TODO: REFRESH 应在叠加层数的同时重置 TimeDurationComponent 的 remaining
			# 当前行为与 CAP 相同，待实际使用时补充刷新逻辑
			stacks = mini(new_value, max_stacks)
		StackOverflowPolicy.REJECT:
			if new_value <= max_stacks:
				stacks = new_value

	return stacks - before

func remove_stacks(count: int) -> int:
	var before := stacks
	stacks = maxi(0, stacks - count)

	if stacks == 0:
		mark_expired()

	return before - stacks

func set_stacks(count: int) -> void:
	stacks = maxi(0, mini(count, max_stacks))
	if stacks == 0:
		mark_expired()

func reset() -> void:
	stacks = 1
	_state = "active"

func serialize() -> Dictionary:
	return {
		"stacks": stacks,
		"maxStacks": max_stacks,
		"overflowPolicy": overflow_policy,
	}

func deserialize(data: Dictionary) -> void:
	stacks = int(data.get("stacks", 1))
	max_stacks = int(data.get("maxStacks", 1))
	overflow_policy = data.get("overflowPolicy", StackOverflowPolicy.CAP) as StackOverflowPolicy
