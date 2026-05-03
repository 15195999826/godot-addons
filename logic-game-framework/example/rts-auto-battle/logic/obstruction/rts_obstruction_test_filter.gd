## RtsObstructionTestFilter - 障碍判定 filter 抽象 (M2 引入)
##
## 0 A.D. `helpers/Pathfinding.h` `IObstructionTestFilter` 的 GDScript 复刻 — predicate 风格 closure,
## 给 ObstructionManager.test_*_shape / get_obstructions_in_range 用,决定"哪些 shape 算障碍"。
##
## **M2 落地范围**:
##   - 抽象基类 + 默认 predicate (返 true = 一律算障碍)
##   - 3 个静态工厂返回具体子类 (skip_control_group / only_blocking_movement / combined)
##
## **同文件 class_name 冲突 mitigation** (M2.md §6 R6):
##   GDScript 同一文件只能有一个 class_name, 所以 3 个具体 filter 用 **inner class** 实现 (`_SkipControlGroup`
##   / `_OnlyBlockingMovement` / `_Combined`), 外部访问只需通过静态工厂 — 跟 0 A.D. C++ inner namespace
##   风格一致, 文件数 / 命名占用都更省.
##
## **决策来源**:
##   - data-structures.md §2.5 (RtsObstructionTestFilter)
##   - milestones/M2-obstruction-manager.md §M2.1 步骤 2-3 + §6 R6
class_name RtsObstructionTestFilter
extends RefCounted


## Predicate: 给定一个 RtsObstructionShape, 返回 true = 把它算作障碍 / false = 跳过。
##
## 默认实现一律算障碍 (子类 override)。
##
## **签名**: `shape` 是 RtsObstructionShape (基类引用); 子类内部按需 cast 到 Unit / Static。
##
## **0 A.D. 对照**: `IObstructionTestFilter::Allowed(tag, flags, group)` — 我们按 shape 引用传, 直接
##                  访问 shape.flags / shape.control_group, 等价。
func predicate(_shape) -> bool:
	return true


# ========== 静态工厂 ==========

## 跳过 control_group (同 group 不算障碍)。M6/M7 短寻路 + motion obstruction filter 主用。
##
## **行为**: shape.control_group == group  OR  shape.control_group_2 == group → 不算障碍 (return false)。
static func skip_control_group(group: String) -> RtsObstructionTestFilter:
	return _SkipControlGroup.new(group)


## 只看 BLOCK_MOVEMENT flag (单位之间互避用)。
##
## **行为**: (shape.flags & BLOCK_MOVEMENT) != 0 → 算障碍。
static func only_blocking_movement() -> RtsObstructionTestFilter:
	return _OnlyBlockingMovement.new()


## 复合两个 filter — A AND B (两边都通过才算障碍)。
##
## **行为**: a.predicate(s) AND b.predicate(s)
static func combined(a: RtsObstructionTestFilter, b: RtsObstructionTestFilter) -> RtsObstructionTestFilter:
	return _Combined.new(a, b)


# ========== Inner classes (具体 filter 实现) ==========

## skip_control_group 工厂返回的具体 filter; 同 group (control_group / control_group_2 任一) 不算障碍。
class _SkipControlGroup:
	extends RtsObstructionTestFilter

	var _group: String

	func _init(g: String) -> void:
		_group = g

	func predicate(shape) -> bool:
		if shape.control_group == _group or shape.control_group_2 == _group:
			return false
		return true


## only_blocking_movement 工厂返回的具体 filter; 仅 BLOCK_MOVEMENT bit 置位的 shape 算障碍。
class _OnlyBlockingMovement:
	extends RtsObstructionTestFilter

	func predicate(shape) -> bool:
		return (shape.flags & RtsObstructionFlags.BLOCK_MOVEMENT) != 0


## combined 工厂返回的具体 filter; AND 复合两个 sub-filter。
class _Combined:
	extends RtsObstructionTestFilter

	var _a: RtsObstructionTestFilter
	var _b: RtsObstructionTestFilter

	func _init(a: RtsObstructionTestFilter, b: RtsObstructionTestFilter) -> void:
		_a = a
		_b = b

	func predicate(shape) -> bool:
		return _a.predicate(shape) and _b.predicate(shape)
