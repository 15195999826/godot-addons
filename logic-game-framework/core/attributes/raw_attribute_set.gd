class_name RawAttributeSet
extends RefCounted
## 属性集合：stat 属性的基础值 / 修改器 / 缓存，资源属性的当前值，以及变化通知。
##
## 【两种属性】
##
## - stat（默认）：base + modifier 四层公式算出 current value，带缓存与动态依赖求解。
## - resource（config `"kind": "resource"`，如 hp）：直接存当前值，写入时 clamp 到 [minValue, maxRef 当前值]，
##   不进 modifier 管线——add_modifier / set_base / 动态依赖的源指向资源一律 assert_crash。
##   写入走 set_resource / add_resource：只 clamp、只在读值变时通知，不跑全属性快照与动态求解。
##   读取按 maxRef 当前值封顶而不改存值（max_hp 下降拉低 hp；重穿装备 / Break 这类上限暂降回升后读值恢复），
##   由此产生的 hp 变化与同批 stat 变化一起、按属性定义顺序通知。
##   maxRef 只存属性名（String），不存 Callable——外部注入的 lambda 会捕获 owner，
##   在 RefCounted 下形成 actor ↔ attr_set ↔ Callable 的循环强引用。
##
## 【属性变化规范】
##
## 所有属性修改必须通过以下入口方法之一：
##   stat：set_base / add_modifier / remove_modifier / remove_modifiers_by_source / update_modifier / register_dynamic_dep
##   resource：set_resource / add_resource
##
## 每个 stat 入口方法内部统一处理所有 modifier（含动态依赖的自动求解），
## 外部无感知，仅会收到最终结果通知：哪些属性发生了变化以及变化后的值。
## 在入口方法返回后，任何时刻调用 get_breakdown() 对相同状态都返回相同数据。
## 绝对不允许通过其它方式修改属性值。
##
## 【动态依赖：两轮快照迭代机制】
##
## 当属性之间存在动态依赖时（如被动技能让 atk 随 max_hp 变化），
## 通过 register_dynamic_dep() 声明式注册依赖关系，而非 Listener 回调。
##
## 动态依赖的求解在每个 stat 入口方法内部自动完成（两轮快照迭代），
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

## attribute config 里声明资源属性的 kind 值：`"hp": { "kind": "resource", "baseValue": 100.0, "minValue": 0.0, "maxRef": "max_hp" }`
const RESOURCE_KIND := "resource"

const _CHANGE_TYPE_BASE := "base"
const _CHANGE_TYPE_MODIFIER := "modifier"
const _CHANGE_TYPE_CURRENT := "current"

## 全部属性名，按定义顺序（stat 与 resource 混排）：快照 / 通知 / 序列化都按这个序遍历
var _attribute_names: Array[String] = []
## { String -> float } stat 属性的 base 值
var _base_values: Dictionary = {}
## { String -> float } 资源属性的存值（写入时 clamp 到 [minValue, max_ref 当前值]，不进 modifier 管线）。
## 读取按 max_ref 当前值封顶而不改存值：上限暂降（重穿装备 / Break 撤销加成）只压低读值，回升后读值恢复。
var _resource_values: Dictionary = {}
## { String -> String } 资源上限来源属性名；"" = 无上限
var _resource_max_refs: Dictionary = {}
## { String -> Array[AttributeModifier] } 按属性名索引
var _modifiers: Dictionary = {}
## { String -> Array[AttributeModifier] } 按 source 索引，用于快速移除
var _source_index: Dictionary = {}
## { String -> AttributeBreakdown }
var _cache: Dictionary = {}
var _dirty_set: Dictionary = {}
## { String -> { "min": float, "max": float } } 静态约束；资源只用 min，max 恒为 INF
var _constraints: Dictionary = {}
var _listeners: Array[Callable] = []
## 动态依赖注册表
## 每项: { modifier_id: String, source_attribute: String, target_attribute: String,
##         modifier_type: AttributeModifier.Type, coefficient: float }
var _dynamic_deps: Array[Dictionary] = []

func _init(attributes: Array[Dictionary] = []) -> void:
	for attr in attributes:
		_define_from_config(str(attr.get("name", "")), attr)

func define_attribute(attr_name: String, base_value: float, min_value: float = -INF, max_value: float = INF) -> void:
	if attr_name == "":
		return
	if _resource_values.has(attr_name):
		Log.assert_crash(false, "AttributeSet",
			"define_attribute: '%s' is already defined as a resource" % attr_name)
		return
	_register_name(attr_name)
	_base_values[attr_name] = base_value
	var empty_mods: Array[AttributeModifier] = []
	_modifiers[attr_name] = empty_mods
	_dirty_set[attr_name] = true
	if min_value != -INF or max_value != INF:
		_constraints[attr_name] = {"min": min_value, "max": max_value}


## 定义资源属性：直接存值（写入时 clamp 到 [min_value, max_ref 当前值]，读取按 max_ref 当前值封顶），不进 modifier 管线。
## max_ref 允许晚于本资源定义（apply_config 按 key 顺序定义，hp 排在 max_hp 之前）：
## 上限在写入时才解析，届时仍未定义即 assert。初值这里只按 min_value 截，高于上限的部分由读取封顶。
func define_resource(attr_name: String, initial_value: float, min_value: float = -INF, max_ref: String = "") -> void:
	if attr_name == "":
		return
	if _base_values.has(attr_name):
		Log.assert_crash(false, "AttributeSet",
			"define_resource: '%s' is already defined as a stat attribute" % attr_name)
		return
	if max_ref == attr_name:
		Log.assert_crash(false, "AttributeSet", "define_resource: '%s' cannot cap itself" % attr_name)
		return
	_register_name(attr_name)
	if min_value != -INF:
		_constraints[attr_name] = {"min": min_value, "max": INF}
	else:
		_constraints.erase(attr_name)
	_resource_max_refs[attr_name] = max_ref
	_resource_values[attr_name] = _clamp_value(attr_name, initial_value)


func has_attribute(attr_name: String) -> bool:
	return _base_values.has(attr_name) or _resource_values.has(attr_name)


func is_resource(attr_name: String) -> bool:
	return _resource_values.has(attr_name)


func get_base(attr_name: String) -> float:
	if _resource_values.has(attr_name):
		Log.assert_crash(false, "AttributeSet",
			"get_base on resource '%s': resources have no base, read get_current_value" % attr_name)
		return _resource_current(attr_name)
	if not _base_values.has(attr_name):
		Log.warning("AttributeSet", "Attribute not found: %s" % attr_name)
		return 0.0
	return float(_base_values[attr_name])


func set_base(attr_name: String, value: float) -> void:
	if _resource_values.has(attr_name):
		Log.assert_crash(false, "AttributeSet",
			"set_base on resource '%s': write it with set_resource / add_resource" % attr_name)
		return
	if not _base_values.has(attr_name):
		Log.warning("AttributeSet", "Attribute not found: %s" % attr_name)
		return

	var old_value := float(_base_values[attr_name])
	var clamped_value := _clamp_value(attr_name, value)
	if old_value == clamped_value:
		return

	# 记录所有属性 before 值
	var before := snapshot_current_values()

	_base_values[attr_name] = clamped_value
	_mark_dirty(attr_name)

	# 求解动态依赖 + 批量通知（资源读值随上限变化，由快照对比发出通知）
	_solve_dynamic_deps()
	_notify_changes(before, _CHANGE_TYPE_BASE)


## 写资源当前值：clamp 到 [minValue, max_ref 当前值] 后存下，读值变化才通知；不跑快照 / 动态求解。
## 上限暂降中（存值高于当前上限）的写入同样落到新值：从封顶读值起算、按暂降上限截断并留下。
func set_resource(attr_name: String, value: float) -> void:
	if not _resource_values.has(attr_name):
		Log.assert_crash(false, "AttributeSet", "set_resource: '%s' is not a resource attribute" % attr_name)
		return
	var old_value := _resource_current(attr_name)
	var new_value := _clamp_resource(attr_name, value)
	if new_value != float(_resource_values[attr_name]):
		_resource_values[attr_name] = new_value
	if old_value == new_value:
		return
	_dispatch_event({
		"attribute_name": attr_name,
		"old_value": old_value,
		"new_value": new_value,
		"change_type": _CHANGE_TYPE_CURRENT,
	})


func add_resource(attr_name: String, delta: float) -> void:
	if not _resource_values.has(attr_name):
		Log.assert_crash(false, "AttributeSet", "add_resource: '%s' is not a resource attribute" % attr_name)
		return
	set_resource(attr_name, _resource_current(attr_name) + delta)


func get_body_value(attr_name: String) -> float:
	return get_breakdown(attr_name).body_value


func get_current_value(attr_name: String) -> float:
	if _resource_values.has(attr_name):
		return _resource_current(attr_name)
	return get_breakdown(attr_name).current_value


## 已定义的全部属性名（stat + resource），按定义顺序。
func get_attribute_names() -> Array[String]:
	return _attribute_names.duplicate()


## 获取属性的完整计算结果。资源没有分层：返回只有 base = current 的平 breakdown。
func get_breakdown(attr_name: String) -> AttributeBreakdown:
	if _resource_values.has(attr_name):
		return AttributeBreakdown.from_base(_resource_current(attr_name))

	if not _dirty_set.has(attr_name) and _cache.has(attr_name):
		return _cache[attr_name] as AttributeBreakdown

	var base_value := float(_base_values.get(attr_name, 0.0))
	var mods := _get_modifiers_typed(attr_name)
	var breakdown := AttributeCalculator.calculate(base_value, mods)

	var clamped_current := _clamp_value(attr_name, breakdown.current_value)
	if clamped_current != breakdown.current_value:
		breakdown = breakdown.with_clamped_value(clamped_current)

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
	if _resource_values.has(modifier.attribute_name):
		Log.assert_crash(false, "AttributeSet",
			"add_modifier: '%s' is a resource and takes no modifiers (write it with set_resource / add_resource)" % modifier.attribute_name)
		return
	if not _modifiers.has(modifier.attribute_name):
		Log.warning("AttributeSet", "Attribute not found for modifier: %s" % modifier.attribute_name)
		return

	var mods := _get_modifiers_typed(modifier.attribute_name)
	for existing in mods:
		if existing.id == modifier.id:
			Log.warning("AttributeSet", "Modifier already exists: %s" % modifier.id)
			return

	var before := snapshot_current_values()
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
			var before := snapshot_current_values()
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
	var before := snapshot_current_values()

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

	# 求解动态依赖 + 批量通知（资源读值随上限变化，由快照对比发出通知）
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
				var before := snapshot_current_values()
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


## 按 config 定义属性（生成 set 的 _init 走这里）。key 顺序即属性定义顺序。
## 每项：{ "baseValue", "minValue"?, "maxValue"? }，或资源 { "kind": "resource", "baseValue", "minValue"?, "maxRef"? }。
## config 里资源初值高于上限时由读取封顶（存值保留）。定义不发通知。
func apply_config(config: Dictionary) -> void:
	for attr_name in config.keys():
		_define_from_config(str(attr_name), config[attr_name] as Dictionary)

func on_attribute_changed(attr_name: String, callback: Callable) -> Callable:
	var filtered_listener := func(event: Dictionary) -> void:
		if event.get("attribute_name", "") == attr_name:
			callback.call(event)
	add_change_listener(filtered_listener)
	return func() -> void:
		remove_change_listener(filtered_listener)


## 注册动态依赖：source_attribute 变化时，自动重算 modifier_id 的值
## modifier_value = get_current_value(source_attribute) * coefficient
## 注册前必须已通过 add_modifier 添加对应的 modifier。注册即求解，并与其它 stat 入口一样通知被改到的属性
## （目标 stat，以及被它封顶的资源读值）。
## 源不能是资源：资源写入不跑求解，以资源为源的动态值会静默过期。
func register_dynamic_dep(
	modifier_id: String,
	source_attribute: String,
	target_attribute: String,
	modifier_type: AttributeModifier.Type,
	coefficient: float,
) -> void:
	if _resource_values.has(source_attribute):
		Log.assert_crash(false, "AttributeSet",
			"register_dynamic_dep: source '%s' is a resource; dynamic deps only read stat attributes" % source_attribute)
		return
	# 防止重复注册
	for dep in _dynamic_deps:
		if dep["modifier_id"] == modifier_id:
			return
	var before := snapshot_current_values()
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
	_notify_changes(before, _CHANGE_TYPE_MODIFIER)


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


## stat → { "base", "modifiers" }；resource → { "kind": "resource", "value" }（value 是封顶后的读值）。按定义顺序。
func serialize() -> Dictionary:
	var result := {}
	for attr_name in _attribute_names:
		if _resource_values.has(attr_name):
			result[attr_name] = {
				"kind": RESOURCE_KIND,
				"value": _resource_current(attr_name),
			}
			continue
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
		if str(attr_data.get("kind", "")) == RESOURCE_KIND:
			attr_set.define_resource(str(attr_name), float(attr_data.get("value", 0.0)))
			continue
		attr_set.define_attribute(str(attr_name), float(attr_data.get("base", 0.0)))
		for mod_data in attr_data.get("modifiers", []):
			var mod := AttributeModifier.deserialize(mod_data)
			attr_set.add_modifier(mod)
	return attr_set


func _register_name(attr_name: String) -> void:
	if not _attribute_names.has(attr_name):
		_attribute_names.append(attr_name)


## config 项 → define_attribute / define_resource。
## 资源不接受 maxValue（上限只能是 maxRef）；stat 不接受 maxRef；minRef 不在契约里。
func _define_from_config(attr_name: String, cfg: Dictionary) -> void:
	var min_val := -INF if cfg.get("minValue") == null else float(cfg.get("minValue"))
	Log.assert_crash(cfg.get("minRef") == null, "AttributeSet",
		"attribute '%s': minRef is not supported (resources clamp to a static minValue)" % attr_name)
	if str(cfg.get("kind", "")) == RESOURCE_KIND:
		Log.assert_crash(cfg.get("maxValue") == null, "AttributeSet",
			"resource '%s': maxValue is not allowed, its cap is maxRef" % attr_name)
		var max_ref := "" if cfg.get("maxRef") == null else str(cfg.get("maxRef"))
		define_resource(attr_name, float(cfg.get("baseValue", 0.0)), min_val, max_ref)
		return
	Log.assert_crash(cfg.get("maxRef") == null, "AttributeSet",
		"stat attribute '%s': maxRef only applies to resources (\"kind\": \"resource\")" % attr_name)
	var max_val := INF if cfg.get("maxValue") == null else float(cfg.get("maxValue"))
	define_attribute(attr_name, float(cfg.get("baseValue", 0.0)), min_val, max_val)


func _mark_dirty(attr_name: String) -> void:
	_dirty_set[attr_name] = true


func _clamp_value(attr_name: String, value: float) -> float:
	if not _constraints.has(attr_name):
		return value
	var constraint: Dictionary = _constraints[attr_name]
	return clampf(value, constraint.get("min", -INF) as float, constraint.get("max", INF) as float)


## 资源的完整 clamp：静态 minValue 之后再按 max_ref 当前值封顶。
## max_ref 指向未定义属性 → assert 并视为无上限（不能让缺失的上限把资源截成 0）。
func _clamp_resource(attr_name: String, value: float) -> float:
	var clamped := _clamp_value(attr_name, value)
	var max_ref: String = _resource_max_refs.get(attr_name, "")
	if max_ref == "":
		return clamped
	if not has_attribute(max_ref):
		Log.assert_crash(false, "AttributeSet",
			"resource '%s' caps by undefined attribute '%s'" % [attr_name, max_ref])
		return clamped
	return minf(clamped, get_current_value(max_ref))


## 资源读值：存值按 max_ref 当前值封顶，不改存值（max_hp 下降拉低 hp，回升后读值恢复）。
## stat 入口方法不碰资源存值：上限变化引起的 hp 通知由它们的 before / after 快照对比发出，顺序与 stat 一致。
func _resource_current(attr_name: String) -> float:
	var value := float(_resource_values[attr_name])
	var max_ref: String = _resource_max_refs.get(attr_name, "")
	if max_ref == "" or not has_attribute(max_ref):
		return value
	return minf(value, get_current_value(max_ref))


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


## 内部辅助：计算 stat 属性的 currentValue（只做静态 clamp，不走缓存，不触发通知）
## 用于动态依赖求解器的两轮快照。
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


## 全属性当前值快照 {name: current}，按定义顺序。内部用于 before/after 对比，
## 也是录像层「actor 属性快照」的唯一来源——两处必须是同一份定义。
func snapshot_current_values() -> Dictionary:
	var snapshot: Dictionary = {}
	for attr_name in _attribute_names:
		snapshot[attr_name] = get_current_value(attr_name)
	return snapshot


## 内部辅助：对比 before/after 快照，批量通知变化的属性
## change_type: 通知事件中的 change_type 字段
func _notify_changes(before: Dictionary, change_type: String) -> void:
	for attr_name in before.keys():
		var old_value: float = before[attr_name]
		var new_value := get_current_value(attr_name)
		if new_value != old_value:
			_dispatch_event({
				"attribute_name": attr_name,
				"old_value": old_value,
				"new_value": new_value,
				"change_type": change_type,
			})
