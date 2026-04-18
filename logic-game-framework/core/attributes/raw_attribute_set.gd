class_name RawAttributeSet
extends RefCounted
## 属性集合：管理属性的基础值、修改器、缓存和变化通知。
##
## 【属性变化规范】
##
## 所有属性修改必须通过以下 5 个入口方法之一：
##   - set_base(attr_name, value)
##   - add_modifier(modifier)
##   - remove_modifier(modifier_id)
##   - remove_modifiers_by_source(source)
##   - update_modifier(modifier_id, new_value)
##
## 每个入口方法内部统一处理所有 modifier（含动态依赖的自动求解），
## 外部无感知，仅会收到最终结果通知：哪些属性发生了变化以及变化后的值。
## 在入口方法返回后，任何时刻调用 get_breakdown() 对相同状态都返回相同数据。
## 绝对不允许通过其它方式修改属性值。
##
## 【动态依赖：两轮快照迭代机制】
##
## 当属性之间存在动态依赖时（如被动技能让 atk 随 max_hp 变化），
## 通过 register_dynamic_dep() 声明式注册依赖关系，而非 Listener 回调。
##
## 动态依赖的求解在每个入口方法内部自动完成（两轮快照迭代），
## 保证以下语义：
##   - 精确可逆：add_modifier 再 remove_modifier 同一个 modifier，属性值严格回到原状态
##   - 路径无关：不管操作顺序如何，同一组 base + modifier 产出同一组最终值
##   - 无需外部 Listener 参与动态依赖计算
##
## 两轮快照求解算法（_solve_dynamic_deps）：
##   第 1 轮：所有动态 modifier 置零 → 计算纯静态快照 → 基于快照算出动态值 → 写入
##   第 2 轮：基于第 1 轮结果重新计算动态值 → 写入最终值
##   统一两轮，无条件，无需动态判断轮数。无交叉依赖时两轮结果与一轮严格相等。
##
## 【示例：穿戴装备 + 被动技能（动态依赖）】
##
## 前置条件：
##   初始属性：max_hp = 100, atk = 20
##   装备（静态 modifier）：max_hp +20 (ADD_BASE), atk +20 (ADD_BASE)
##   被动技能（动态依赖，通过 register_dynamic_dep 注册）：
##     技能 a：max_hp += atk × 0.1  (ADD_BASE)
##     技能 b：atk += max_hp × 0.01 (ADD_BASE)
##     技能 c：max_hp += atk × 0.2  (ADD_BASE)
##     技能 d：atk += max_hp × 0.02 (ADD_BASE)
##
## 穿戴装备后（两轮快照求解）：
##
##   第 1 轮：动态 modifier 清零 → 纯静态值：max_hp = 120, atk = 40
##     技能 a: 40 × 0.1 = 4.0  → max_hp 动态 modifier = 4.0
##     技能 b: 120 × 0.01 = 1.2 → atk 动态 modifier = 1.2
##     技能 c: 40 × 0.2 = 8.0  → max_hp 动态 modifier = 8.0
##     技能 d: 120 × 0.02 = 2.4 → atk 动态 modifier = 2.4
##     写入后：max_hp = 132.0, atk = 43.6
##
##   第 2 轮：基于第 1 轮结果重新计算
##     技能 a: 43.6 × 0.1 = 4.36  → max_hp 动态 modifier = 4.36
##     技能 b: 132.0 × 0.01 = 1.32 → atk 动态 modifier = 1.32
##     技能 c: 43.6 × 0.2 = 8.72  → max_hp 动态 modifier = 8.72
##     技能 d: 132.0 × 0.02 = 2.64 → atk 动态 modifier = 2.64
##     最终：max_hp = 133.08, atk = 43.96
##
## 可逆性验证：
##   获得 atk +10 buff 后：max_hp = 136.08, atk = 54.05
##   移除同一 buff 后：max_hp = 133.08, atk = 43.96（严格等于 buff 前 ✅）

const _CHANGE_TYPE_BASE := "base"
const _CHANGE_TYPE_MODIFIER := "modifier"
const _CHANGE_TYPE_CURRENT := "current"

var _base_values: Dictionary = {}
## { String -> Array[AttributeModifier] } 按属性名索引
var _modifiers: Dictionary = {}
## { String -> Array[AttributeModifier] } 按 source 索引，用于快速移除
var _source_index: Dictionary = {}
## { String -> AttributeBreakdown }
var _cache: Dictionary = {}
var _dirty_set: Dictionary = {}
var _computing_set: Dictionary = {}
var _constraints: Dictionary = {}
var _listeners: Array[Callable] = []
## current 值变化前的回调，签名: func(attr_name: String, inout_value: Dictionary) -> void
## inout_value = { "value": float }，可直接修改 inout_value["value"] 来调整最终值
var _pre_change_callback: Callable = Callable()
## 动态依赖注册表
## 每项: { modifier_id: String, source_attribute: String, target_attribute: String,
##         modifier_type: AttributeModifier.Type, coefficient: float }
var _dynamic_deps: Array[Dictionary] = []

func _init(attributes: Array[Dictionary] = []) -> void:
	for attr in attributes:
		var min_val := -INF if attr.get("minValue") == null else float(attr.get("minValue"))
		var max_val := INF if attr.get("maxValue") == null else float(attr.get("maxValue"))
		define_attribute(str(attr.get("name", "")), float(attr.get("baseValue", 0.0)), min_val, max_val)

func define_attribute(attr_name: String, base_value: float, min_value: float = -INF, max_value: float = INF) -> void:
	if attr_name == "":
		return
	_base_values[attr_name] = base_value
	var empty_mods: Array[AttributeModifier] = []
	_modifiers[attr_name] = empty_mods
	_dirty_set[attr_name] = true
	if min_value != -INF or max_value != INF:
		_constraints[attr_name] = {"min": min_value, "max": max_value}

func has_attribute(attr_name: String) -> bool:
	return _base_values.has(attr_name)


func get_base(attr_name: String) -> float:
	if not _base_values.has(attr_name):
		Log.warning("AttributeSet", "Attribute not found: %s" % attr_name)
		return 0.0
	return float(_base_values[attr_name])


func set_base(attr_name: String, value: float) -> void:
	if not _base_values.has(attr_name):
		Log.warning("AttributeSet", "Attribute not found: %s" % attr_name)
		return

	var old_value := float(_base_values[attr_name])
	var clamped_value := _clamp_value(attr_name, value)
	if old_value == clamped_value:
		return

	# 记录所有属性 before 值
	var before := _snapshot_all_values()

	_base_values[attr_name] = clamped_value
	_mark_dirty(attr_name)

	# 求解动态依赖 + 批量通知
	_solve_dynamic_deps()
	_notify_changes(before, _CHANGE_TYPE_BASE)


func get_body_value(attr_name: String) -> float:
	return get_breakdown(attr_name).body_value


func get_current_value(attr_name: String) -> float:
	return get_breakdown(attr_name).current_value


## 获取属性的完整计算结果（含循环依赖检测）
##
## _computing_set 记录当前正在计算的属性。如果在计算 A 的过程中又要计算 A，说明形成了循环。
##
## 动态属性依赖通过 register_dynamic_dep + 两轮快照求解器处理，不会触发循环。
## 此处的循环检测用于防御 pre_change_callback 等外部回调导致的意外循环。
##
## 示例：pre_change_callback 中 hp ≤ max_hp 约束，计算 hp 时读取 max_hp，
## 若 max_hp 的计算又回到 hp → 触发循环检测。
##
## 循环触发后：有缓存返回缓存值，无缓存返回 base 值（并输出警告日志）。
func get_breakdown(attr_name: String) -> AttributeBreakdown:
	if _computing_set.has(attr_name):
		var computing_chain := ", ".join(_computing_set.keys())
		if _cache.has(attr_name):
			Log.warning("AttributeSet",
				"[循环依赖] 属性 '%s' 在计算过程中被再次访问，形成循环。当前计算链: [%s]。已返回缓存值以中断循环。" % [attr_name, computing_chain])
			return _cache[attr_name] as AttributeBreakdown
		var fallback_base := float(_base_values.get(attr_name, 0.0))
		Log.warning("AttributeSet",
			"[循环依赖] 属性 '%s' 在计算过程中被再次访问，形成循环。当前计算链: [%s]。无缓存可用，已返回基础值 %.2f 以中断循环。" % [attr_name, computing_chain, fallback_base])
		return AttributeBreakdown.from_base(fallback_base)

	if not _dirty_set.has(attr_name) and _cache.has(attr_name):
		return _cache[attr_name] as AttributeBreakdown

	_computing_set[attr_name] = true
	var base_value := float(_base_values.get(attr_name, 0.0))
	var mods := _get_modifiers_typed(attr_name)
	var breakdown := AttributeCalculator.calculate(base_value, mods)

	# 1. 先应用 minValue/maxValue 约束
	var clamped_current := _clamp_value(attr_name, breakdown.current_value)
	if clamped_current != breakdown.current_value:
		breakdown = breakdown.with_clamped_value(clamped_current)

	# 2. 再调用 pre_change 回调（允许跨属性约束，如 hp ≤ max_hp）
	if _pre_change_callback.is_valid():
		var inout_value := { "value": breakdown.current_value }
		_pre_change_callback.call(attr_name, inout_value)
		var callback_value: float = inout_value["value"]
		if callback_value != breakdown.current_value:
			breakdown = breakdown.with_clamped_value(callback_value)

	_computing_set.erase(attr_name)

	_cache[attr_name] = breakdown
	_dirty_set.erase(attr_name)
	return breakdown


func get_add_base_sum(attr_name: String) -> float:
	return get_breakdown(attr_name).add_base_sum


func get_mul_base_product(attr_name: String) -> float:
	return get_breakdown(attr_name).mul_base_product


func get_add_final_sum(attr_name: String) -> float:
	return get_breakdown(attr_name).add_final_sum


func get_mul_final_product(attr_name: String) -> float:
	return get_breakdown(attr_name).mul_final_product


func add_modifier(modifier: AttributeModifier) -> void:
	if not _modifiers.has(modifier.attribute_name):
		Log.warning("AttributeSet", "Attribute not found for modifier: %s" % modifier.attribute_name)
		return

	var mods := _get_modifiers_typed(modifier.attribute_name)
	for existing in mods:
		if existing.id == modifier.id:
			Log.warning("AttributeSet", "Modifier already exists: %s" % modifier.id)
			return

	var before := _snapshot_all_values()
	mods.append(modifier)
	_add_to_source_index(modifier)
	_mark_dirty(modifier.attribute_name)

	_solve_dynamic_deps()
	_notify_changes(before, _CHANGE_TYPE_MODIFIER)


func remove_modifier(modifier_id: String) -> bool:
	for attr_name in _modifiers.keys():
		var mods := _get_modifiers_typed(attr_name)
		var index := -1
		for i in range(mods.size()):
			if mods[i].id == modifier_id:
				index = i
				break
		if index != -1:
			var before := _snapshot_all_values()
			var removed_mod := mods[index]
			mods.remove_at(index)
			_remove_from_source_index(removed_mod)
			_mark_dirty(attr_name)

			_solve_dynamic_deps()
			_notify_changes(before, _CHANGE_TYPE_MODIFIER)
			return true
	return false


func remove_modifiers_by_source(source: String) -> int:
	if not _source_index.has(source):
		return 0

	var source_mods := _get_source_index_typed(source)
	if source_mods.is_empty():
		return 0

	# 按属性分组，记录需要移除的修改器
	var affected_attrs: Dictionary = {}  # { attr_name -> Array[AttributeModifier] }
	for mod in source_mods:
		if not affected_attrs.has(mod.attribute_name):
			affected_attrs[mod.attribute_name] = []
		affected_attrs[mod.attribute_name].append(mod)

	var count := source_mods.size()
	var before := _snapshot_all_values()

	# 从各属性的修改器列表中移除
	for attr_name in affected_attrs.keys():
		var mods := _get_modifiers_typed(attr_name)
		var filtered: Array[AttributeModifier] = []
		for mod in mods:
			if mod.source != source:
				filtered.append(mod)
		_modifiers[attr_name] = filtered
		_mark_dirty(attr_name)

	# 清空 source 索引
	_source_index.erase(source)

	# 求解动态依赖 + 批量通知
	_solve_dynamic_deps()
	_notify_changes(before, _CHANGE_TYPE_MODIFIER)

	return count


## 原子更新修改器的值（不触发 remove+add 两次通知，只触发一次）
## 用于外部需要更新 modifier 值的场景。
## 返回 true 表示找到并更新了修改器，false 表示未找到。
func update_modifier(modifier_id: String, new_value: float) -> bool:
	for attr_name in _modifiers.keys():
		var mods := _get_modifiers_typed(attr_name)
		for mod in mods:
			if mod.id == modifier_id:
				var before := _snapshot_all_values()
				mod.value = new_value
				_mark_dirty(attr_name)
				_solve_dynamic_deps()
				_notify_changes(before, _CHANGE_TYPE_MODIFIER)
				return true
	return false


func get_modifiers(attr_name: String) -> Array[AttributeModifier]:
	return _get_modifiers_typed(attr_name)


func has_modifier(modifier_id: String) -> bool:
	for attr_name in _modifiers.keys():
		var mods := _get_modifiers_typed(attr_name)
		for mod in mods:
			if mod.id == modifier_id:
				return true
	return false


func add_change_listener(listener: Callable) -> void:
	_listeners.append(listener)


func remove_change_listener(listener: Callable) -> void:
	_listeners.erase(listener)


func remove_all_change_listeners() -> void:
	_listeners.clear()


## 设置 current 值变化前的回调
## 签名: func(attr_name: String, inout_value: Dictionary) -> void
## inout_value = { "value": float }，可直接修改 inout_value["value"] 来调整最终值
##
## 示例：hp 不超过 max_hp
##   attr_set.set_pre_change(func(attr_name: String, inout_value: Dictionary) -> void:
##       if attr_name == "hp":
##           var max_hp := attr_set.get_current_value("max_hp")
##           if inout_value["value"] > max_hp:
##               inout_value["value"] = max_hp
##   )
func set_pre_change(callback: Callable) -> void:
	_pre_change_callback = callback


func clear_pre_change() -> void:
	_pre_change_callback = Callable()


func apply_config(config: Dictionary) -> void:
	for attr_name in config.keys():
		var cfg: Dictionary = config[attr_name]
		var min_val := -INF if cfg.get("minValue") == null else float(cfg.get("minValue"))
		var max_val := INF if cfg.get("maxValue") == null else float(cfg.get("maxValue"))
		define_attribute(str(attr_name), float(cfg.get("baseValue", 0.0)), min_val, max_val)

func on_attribute_changed(attr_name: String, callback: Callable) -> Callable:
	var filtered_listener := func(event: Dictionary) -> void:
		if event.get("attributeName", "") == attr_name:
			callback.call(event)
	add_change_listener(filtered_listener)
	return func() -> void:
		remove_change_listener(filtered_listener)


## 注册动态依赖：source_attribute 变化时，自动重算 modifier_id 的值
## modifier_value = get_current_value(source_attribute) * coefficient
## 注册前必须已通过 add_modifier 添加对应的 modifier
func register_dynamic_dep(
	modifier_id: String,
	source_attribute: String,
	target_attribute: String,
	modifier_type: AttributeModifier.Type,
	coefficient: float,
) -> void:
	# 防止重复注册
	for dep in _dynamic_deps:
		if dep["modifier_id"] == modifier_id:
			return
	_dynamic_deps.append({
		"modifier_id": modifier_id,
		"source_attribute": source_attribute,
		"target_attribute": target_attribute,
		"modifier_type": modifier_type,
		"coefficient": coefficient,
	})
	# 立即求解：否则新增的 dep 要等到下一次 add/remove/update modifier 才会生效，
	# 典型场景（先 add_modifier 再 register_dynamic_dep 再 get_current_value）会读到未求解的 0 值。
	_solve_dynamic_deps()


## 取消注册动态依赖
func unregister_dynamic_dep(modifier_id: String) -> void:
	for i in range(_dynamic_deps.size() - 1, -1, -1):
		if _dynamic_deps[i]["modifier_id"] == modifier_id:
			_dynamic_deps.remove_at(i)
			return


static func from_config(config: Dictionary) -> RawAttributeSet:
	var attr_set := RawAttributeSet.new()
	attr_set.apply_config(config)
	return attr_set


static func restore_attributes(data: Dictionary) -> RawAttributeSet:
	return RawAttributeSet.deserialize(data)


func serialize() -> Dictionary:
	var result := {}
	for attr_name in _base_values.keys():
		var mods := _get_modifiers_typed(attr_name)
		var serialized_mods: Array[Dictionary] = []
		for mod in mods:
			serialized_mods.append(mod.serialize())
		result[attr_name] = {
			"base": float(_base_values[attr_name]),
			"modifiers": serialized_mods,
		}
	return result


static func deserialize(data: Dictionary) -> RawAttributeSet:
	var attr_set := RawAttributeSet.new()
	for attr_name in data.keys():
		var attr_data: Dictionary = data[attr_name]
		attr_set.define_attribute(str(attr_name), float(attr_data.get("base", 0.0)))
		for mod_data in attr_data.get("modifiers", []):
			var mod := AttributeModifier.deserialize(mod_data)
			attr_set.add_modifier(mod)
	return attr_set


func _mark_dirty(attr_name: String) -> void:
	_dirty_set[attr_name] = true


func _clamp_value(attr_name: String, value: float) -> float:
	if not _constraints.has(attr_name):
		return value
	var constraint: Dictionary = _constraints[attr_name]
	return clampf(value, constraint.get("min", -INF) as float, constraint.get("max", INF) as float)


func _dispatch_event(event: Dictionary) -> void:
	for listener in _listeners:
		if listener.is_valid():
			listener.call(event)
		else:
			Log.error("AttributeSet", "Error in attribute change listener")


## 内部辅助：从 _modifiers Dictionary 取出类型化数组
func _get_modifiers_typed(attr_name: String) -> Array[AttributeModifier]:
	var raw_array: Variant = _modifiers.get(attr_name, [])
	if raw_array is Array[AttributeModifier]:
		return raw_array
	# 兜底：空数组情况
	var typed: Array[AttributeModifier] = []
	for item in raw_array:
		if item is AttributeModifier:
			typed.append(item)
	return typed


## 内部辅助：从 _source_index Dictionary 取出类型化数组
func _get_source_index_typed(source: String) -> Array[AttributeModifier]:
	var raw_array: Variant = _source_index.get(source, [])
	if raw_array is Array[AttributeModifier]:
		return raw_array
	var typed: Array[AttributeModifier] = []
	for item in raw_array:
		if item is AttributeModifier:
			typed.append(item)
	return typed


## 内部辅助：添加修改器到 source 索引
func _add_to_source_index(modifier: AttributeModifier) -> void:
	if modifier.source == "":
		return
	if not _source_index.has(modifier.source):
		var empty_mods: Array[AttributeModifier] = []
		_source_index[modifier.source] = empty_mods
	var source_mods := _get_source_index_typed(modifier.source)
	source_mods.append(modifier)


## 内部辅助：从 source 索引移除修改器
func _remove_from_source_index(modifier: AttributeModifier) -> void:
	if modifier.source == "":
		return
	if not _source_index.has(modifier.source):
		return
	var source_mods := _get_source_index_typed(modifier.source)
	source_mods.erase(modifier)
	if source_mods.is_empty():
		_source_index.erase(modifier.source)


## 两轮快照求解器：重算所有动态依赖的 modifier 值
##
## 流程：
##   第一轮：所有动态 modifier 视为 0 → 计算快照值 → 基于快照算出第一轮动态值
##   第二轮：将第一轮动态值写入 → 计算第二轮快照值 → 基于第二轮快照算出最终动态值
##
## 两轮让互相依赖的动态 modifier 能"看到彼此一次"，精度损失约 0.08%。
## 无交叉依赖时，第二轮结果与第一轮完全相同（严格相等，非近似）。
## 可逆性：同一组 {base + 静态 modifier} → 同一最终值，路径无关。
func _solve_dynamic_deps() -> void:
	if _dynamic_deps.is_empty():
		return

	# 收集所有动态 modifier 的引用，用于静默写入
	var dep_modifiers: Array[Dictionary] = []  # { dep, modifier_ref }
	for dep in _dynamic_deps:
		var mod_ref := _find_modifier_by_id(dep["modifier_id"] as String)
		if mod_ref == null:
			continue
		dep_modifiers.append({ "dep": dep, "mod": mod_ref })

	if dep_modifiers.is_empty():
		return

	# === 第一轮 ===
	# 1a. 所有动态 modifier 值清零
	for item in dep_modifiers:
		var mod: AttributeModifier = item["mod"]
		mod.value = 0.0

	# 1b. 标记所有涉及的属性为脏
	_mark_all_dynamic_dirty(dep_modifiers)

	# 1c. 基于快照（动态=0）计算第一轮动态值
	var round1_values: Array[float] = []
	for item in dep_modifiers:
		var dep: Dictionary = item["dep"]
		var source_value := _compute_current_value(dep["source_attribute"] as String)
		round1_values.append(source_value * (dep["coefficient"] as float))

	# 1d. 将第一轮动态值写入
	for i in range(dep_modifiers.size()):
		var mod: AttributeModifier = dep_modifiers[i]["mod"]
		mod.value = round1_values[i]

	# === 第二轮 ===
	# 2a. 标记脏
	_mark_all_dynamic_dirty(dep_modifiers)

	# 2b. 基于第一轮结果计算第二轮动态值
	for item in dep_modifiers:
		var dep: Dictionary = item["dep"]
		var mod: AttributeModifier = item["mod"]
		var source_value := _compute_current_value(dep["source_attribute"] as String)
		mod.value = source_value * (dep["coefficient"] as float)

	# 2c. 最终标记脏，确保后续 get_breakdown 重算
	_mark_all_dynamic_dirty(dep_modifiers)


## 内部辅助：计算属性的 currentValue（不触发通知，不走 pre_change 回调）
func _compute_current_value(attr_name: String) -> float:
	var base_value := float(_base_values.get(attr_name, 0.0))
	var mods := _get_modifiers_typed(attr_name)
	var breakdown := AttributeCalculator.calculate(base_value, mods)
	var clamped := _clamp_value(attr_name, breakdown.current_value)
	return clamped


## 内部辅助：标记所有动态依赖涉及的属性为脏
func _mark_all_dynamic_dirty(dep_modifiers: Array[Dictionary]) -> void:
	for item in dep_modifiers:
		var dep: Dictionary = item["dep"]
		_mark_dirty(dep["target_attribute"] as String)
		_mark_dirty(dep["source_attribute"] as String)


## 内部辅助：按 ID 查找 modifier 引用（返回 null 表示未找到）
func _find_modifier_by_id(modifier_id: String) -> AttributeModifier:
	for attr_name in _modifiers.keys():
		var mods := _get_modifiers_typed(attr_name)
		for mod in mods:
			if mod.id == modifier_id:
				return mod
	return null


## 内部辅助：记录所有属性的当前值快照（用于 before/after 对比）
func _snapshot_all_values() -> Dictionary:
	var snapshot: Dictionary = {}
	for attr_name in _base_values.keys():
		snapshot[attr_name] = get_current_value(attr_name)
	return snapshot


## 内部辅助：对比 before/after 快照，批量通知变化的属性
## change_type: 通知事件中的 changeType 字段
func _notify_changes(before: Dictionary, change_type: String) -> void:
	for attr_name in before.keys():
		var old_value: float = before[attr_name]
		var new_value := get_current_value(attr_name)
		if new_value != old_value:
			_dispatch_event({
				"attributeName": attr_name,
				"oldValue": old_value,
				"newValue": new_value,
				"changeType": change_type,
			})
