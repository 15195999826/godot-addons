@tool
class_name AttributeSetGeneratorScript
extends EditorScript
## 属性集生成器：从 attributes config（暴露 `const SETS := {...}` 的 GDScript）
## 生成强类型 AttributeSet 类（BaseGeneratedAttributeSet 子类）。
##
## Config 发现约定（加新 example 无需改本脚本）：
##   1. 项目级固定路径 PROJECT_CONFIG_PATH
##   2. example 共享 demo 区 SHARED_EXAMPLE_CONFIG_PATH（仅 generator 演示 set，
##      新 example 不再往里加 set，一律走第 3 条 example-local 路径）
##   3. 每个 example 的 example/<name>/logic/attributes/attributes_config.gd
## 产物统一写到 config 同目录下的 generated/。
##
## 入口：
##   - 编辑器菜单 Tools > LGFramework > 生成属性集（plugin.gd 调 _run()）
##   - Headless：godot --headless --path . \
##       addons/logic-game-framework/scripts/generate_attribute_sets.tscn

const PROJECT_CONFIG_PATH := "res://logic-game-framework-config/attributes/attributes_config.gd"
const SHARED_EXAMPLE_CONFIG_PATH := "res://addons/logic-game-framework/example/attributes/attributes_config.gd"
const EXAMPLE_ROOT := "res://addons/logic-game-framework/example"
const EXAMPLE_LOCAL_CONFIG_RELPATH := "logic/attributes/attributes_config.gd"
const GENERATED_DIR_NAME := "generated"
const _SHADOWED_GLOBAL_IDENTIFIERS := ["range", "min", "max", "clamp"]

## Set 级元字段：声明继承自哪个 set。生成时父属性由父 set 拥有，子 set 不重复生成访问器。
const META_EXTENDS := "_extends"


func _run() -> void:
	generate_all()


## 主入口：发现全部 config → 跨 config set 名预检 → 逐 config 生成。
## 单个 config 失败（缺失/加载失败/内部校验失败）不中断其余 config，但整体返回 false；
## 跨 config set 名冲突除外——那会生成重复 class_name，整体中止且不写任何文件。
static func generate_all() -> bool:
	print("[LGF] Attribute generation started")
	var scan_status := {}
	var config_paths := discover_config_paths(scan_status)
	var entries := _load_config_entries(config_paths)
	if not _validate_unique_set_names(entries):
		return false

	var all_ok: bool = scan_status["ok"] and entries.size() == config_paths.size()
	var generated_from: Array[String] = []
	for entry in entries:
		var config_path: String = entry["path"]
		var sets: Dictionary = entry["sets"]
		var output_dir := config_path.get_base_dir().path_join(GENERATED_DIR_NAME)
		if _generate_from_config(config_path, sets, output_dir):
			generated_from.append(config_path)
		else:
			all_ok = false

	if generated_from.is_empty():
		push_error("No attribute sets were generated")
		return false
	print("[LGF] Attribute sets generated from:")
	for config_path in generated_from:
		print("  - %s" % config_path)
	return all_ok


## 发现所有 attributes config 路径：固定两处 + 扫描 example/*/logic/attributes/。
## p_scan_status（可选 out 参数）：扫描 example 根目录失败时置 { "ok": false }——
## 此时返回的固定路径仍有效，但调用方不得把结果当完整清单（headless 退出码须如实报失败）。
static func discover_config_paths(p_scan_status: Dictionary = {}) -> Array[String]:
	p_scan_status["ok"] = true
	var paths: Array[String] = [PROJECT_CONFIG_PATH, SHARED_EXAMPLE_CONFIG_PATH]
	var example_root := DirAccess.open(EXAMPLE_ROOT)
	if example_root == null:
		push_error("Failed to open example root: %s" % EXAMPLE_ROOT)
		p_scan_status["ok"] = false
		return paths
	for sub_dir in example_root.get_directories():
		var candidate := EXAMPLE_ROOT.path_join(sub_dir).path_join(EXAMPLE_LOCAL_CONFIG_RELPATH)
		if FileAccess.file_exists(candidate):
			paths.append(candidate)
	return paths


## 加载各 config 的 SETS。加载/形状校验失败的 config 不入列（已 push_error）。
## 返回 [{ "path": String, "sets": Dictionary }]。
static func _load_config_entries(config_paths: Array[String]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for config_path in config_paths:
		if not ResourceLoader.exists(config_path):
			push_error("AttributesConfig not found: %s" % config_path)
			continue
		var config: GDScript = load(config_path) as GDScript
		if config == null:
			push_error("AttributesConfig not found: %s" % config_path)
			continue
		var sets: Variant = config.get_script_constant_map().get("SETS")
		if typeof(sets) != TYPE_DICTIONARY:
			push_error("AttributesConfig.SETS must be Dictionary: %s" % config_path)
			continue
		entries.append({ "path": config_path, "sets": sets })
	return entries


## 跨 config 预检：set 名决定生成的 class_name（<SetName>AttributeSet 全局符号），
## 任意两份 config 撞 set 名都会产出重复 class_name，必须整体拒绝。
static func _validate_unique_set_names(entries: Array[Dictionary]) -> bool:
	var owner_by_set_name: Dictionary = {}
	var ok := true
	for entry in entries:
		var config_path: String = entry["path"]
		var sets: Dictionary = entry["sets"]
		for set_name: String in sets.keys():
			if owner_by_set_name.has(set_name):
				push_error(
					"Attribute set '%s' defined in both %s and %s (generated class_name would collide)" %
					[set_name, owner_by_set_name[set_name], config_path]
				)
				ok = false
			else:
				owner_by_set_name[set_name] = config_path
	return ok


static func _generate_from_config(config_path: String, sets: Dictionary, output_dir: String) -> bool:
	print("[LGF] Generating from %s -> %s" % [config_path, output_dir])
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Failed to create output dir: %s" % output_dir)
		return false

	# 1) 验证：检查 _extends 引用存在 + 检测继承环
	if not _validate_inheritance(sets):
		return false

	# 2) Topological sort：父 set 必须先生成
	var ordered_set_names := _topo_sort(sets)
	if ordered_set_names.is_empty():
		return false

	# 3) 验证父子重复属性 + clamp 方向
	if not _validate_no_duplicate_attrs(sets, ordered_set_names):
		return false
	if not _validate_clamp_direction(sets, ordered_set_names):
		return false

	# 4) 按拓扑序生成。单 set 失败不中断其余 set（能写多少写多少），但整体如实报失败。
	var generated_count := 0
	var sets_ok := true
	for set_name in ordered_set_names:
		var attr_defs: Variant = sets[set_name]
		if typeof(attr_defs) != TYPE_DICTIONARY:
			push_error("Attribute set %s must be Dictionary" % set_name)
			sets_ok = false
			continue
		if _generate_set(set_name, attr_defs as Dictionary, sets, output_dir):
			generated_count += 1
		else:
			sets_ok = false

	print("Generated %d/%d sets from %s" % [generated_count, ordered_set_names.size(), config_path])
	return sets_ok


# ========== Inheritance helpers ==========

## set_name -> parent set name (or "" if no parent)
static func _get_parent(sets: Dictionary, set_name: String) -> String:
	var attr_defs: Dictionary = sets[set_name]
	return str(attr_defs.get(META_EXTENDS, ""))


## 递归收集 set 的所有祖先（不含自己），父在前。
static func _get_ancestor_chain(sets: Dictionary, set_name: String) -> Array[String]:
	var chain: Array[String] = []
	var current := _get_parent(sets, set_name)
	while current != "":
		chain.push_front(current)
		current = _get_parent(sets, current)
	return chain


## 收集 set 自身定义的属性（不含继承）。剥掉 META_EXTENDS。
static func _get_own_attrs(attr_defs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for k: String in attr_defs.keys():
		if k == META_EXTENDS:
			continue
		result[k] = attr_defs[k]
	return result


## 收集 set 自身 + 所有祖先的属性（用于 clamp 方向校验、属性可见性判断）。
static func _collect_visible_attrs(sets: Dictionary, set_name: String) -> Dictionary:
	var result: Dictionary = {}
	for ancestor in _get_ancestor_chain(sets, set_name):
		var ancestor_defs: Dictionary = sets[ancestor]
		for k: String in ancestor_defs.keys():
			if k == META_EXTENDS:
				continue
			result[k] = ancestor_defs[k]
	for k: String in (sets[set_name] as Dictionary).keys():
		if k == META_EXTENDS:
			continue
		result[k] = (sets[set_name] as Dictionary)[k]
	return result


# ========== Validation ==========

## 检查 _extends 引用存在 + 继承环 + 仅单父类。
static func _validate_inheritance(sets: Dictionary) -> bool:
	var ok := true
	for set_name: String in sets.keys():
		var attr_defs: Variant = sets[set_name]
		if typeof(attr_defs) != TYPE_DICTIONARY:
			continue
		var defs: Dictionary = attr_defs
		if not defs.has(META_EXTENDS):
			continue
		var parent: String = str(defs[META_EXTENDS])
		if parent == "":
			push_error("Set '%s' has empty %s" % [set_name, META_EXTENDS])
			ok = false
			continue
		if not sets.has(parent):
			push_error("Set '%s' extends unknown set '%s'" % [set_name, parent])
			ok = false
			continue
		if parent == set_name:
			push_error("Set '%s' extends itself" % set_name)
			ok = false
			continue

	# 环检测
	for set_name: String in sets.keys():
		if not _check_no_cycle(sets, set_name):
			ok = false
	return ok


## 沿 _extends 走，若回到自己则是环。
static func _check_no_cycle(sets: Dictionary, start: String) -> bool:
	var visited: Dictionary = {}
	var current := start
	while current != "":
		if visited.has(current):
			push_error("Inheritance cycle detected at set '%s' (starting from '%s')" % [current, start])
			return false
		visited[current] = true
		var defs: Variant = sets.get(current, null)
		if typeof(defs) != TYPE_DICTIONARY:
			break
		current = str((defs as Dictionary).get(META_EXTENDS, ""))
	return true


## DFS topological sort，父先于子。返回排序后的 set 名。失败返回空。
static func _topo_sort(sets: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var visited: Dictionary = {}
	var visiting: Dictionary = {}

	var set_names: Array[String] = []
	for k: String in sets.keys():
		set_names.append(k)
	set_names.sort()

	for set_name in set_names:
		if not _topo_visit(sets, set_name, visited, visiting, result):
			return []
	return result


static func _topo_visit(
	sets: Dictionary,
	set_name: String,
	visited: Dictionary,
	visiting: Dictionary,
	result: Array[String],
) -> bool:
	if visited.has(set_name):
		return true
	if visiting.has(set_name):
		push_error("Topological sort detected cycle at '%s'" % set_name)
		return false
	visiting[set_name] = true

	var parent := _get_parent(sets, set_name)
	if parent != "" and sets.has(parent):
		if not _topo_visit(sets, parent, visited, visiting, result):
			return false

	visiting.erase(set_name)
	visited[set_name] = true
	result.append(set_name)
	return true


## 子 set 不允许重新声明已经存在于祖先链的属性。
static func _validate_no_duplicate_attrs(sets: Dictionary, ordered: Array[String]) -> bool:
	var ok := true
	for set_name in ordered:
		var attr_defs: Dictionary = sets[set_name]
		var own := _get_own_attrs(attr_defs)
		var ancestors := _get_ancestor_chain(sets, set_name)
		for ancestor in ancestors:
			var ancestor_attrs := _get_own_attrs(sets[ancestor] as Dictionary)
			for attr_name: String in own.keys():
				if ancestor_attrs.has(attr_name):
					push_error(
						"Set '%s' redefines attribute '%s' already defined in ancestor '%s' (override forbidden)" %
						[set_name, attr_name, ancestor]
					)
					ok = false
	return ok


## 父 set 的 maxRef/minRef 不允许引用子层属性。
## 子 set 可引父 + 子。
static func _validate_clamp_direction(sets: Dictionary, ordered: Array[String]) -> bool:
	var ok := true
	for set_name in ordered:
		var attr_defs: Dictionary = sets[set_name]
		var own := _get_own_attrs(attr_defs)
		# 该 set 在自身 + 祖先视角下可见的属性
		var visible := _collect_visible_attrs(sets, set_name)
		for attr_name: String in own.keys():
			var cfg: Variant = own[attr_name]
			if typeof(cfg) != TYPE_DICTIONARY:
				continue
			var cfg_dict: Dictionary = cfg
			for field_name in ["maxRef", "minRef"]:
				if not cfg_dict.has(field_name) or cfg_dict[field_name] == null:
					continue
				var source_attr: String = str(cfg_dict[field_name])
				if not visible.has(source_attr):
					push_error(
						"Set '%s' attr '%s' has %s='%s' but source not visible from this set (would require child→parent reverse reference)" %
						[set_name, attr_name, field_name, source_attr]
					)
					ok = false
	return ok


# ========== Generation ==========

## 生成单个 set 的产物文件。任一属性生成失败或文件写不出返回 false（能写出的内容仍写出）。
static func _generate_set(set_name: String, attr_defs: Dictionary, sets: Dictionary, output_dir: String) -> bool:
	var set_ok := true
	var set_class_name := "%sAttributeSet" % set_name
	var file_name := _to_snake_case(set_class_name)
	var file_path := "%s/%s.gd" % [output_dir, file_name]
	var lines: Array[String] = []

	# 父 set
	var parent_set_name: String = str(attr_defs.get(META_EXTENDS, ""))
	var parent_class_name: String = ""
	if parent_set_name != "":
		parent_class_name = "%sAttributeSet" % parent_set_name

	# 该 set 自身定义的属性（剥 _extends），分基础/派生
	var own_attrs := _get_own_attrs(attr_defs)
	var base_attrs: Dictionary = {}
	var derived_attrs: Dictionary = {}
	for attr_name: String in own_attrs.keys():
		var cfg: Dictionary = own_attrs[attr_name]
		if cfg.has("derived"):
			derived_attrs[attr_name] = cfg
		else:
			base_attrs[attr_name] = cfg

	# 文件头
	lines.append("## ⚠️ AUTO-GENERATED FILE - DO NOT MODIFY")
	lines.append("## Generated by AttributeSetGeneratorScript")
	lines.append("")
	if parent_class_name != "":
		lines.append("extends %s" % parent_class_name)
	else:
		lines.append("extends BaseGeneratedAttributeSet")
	lines.append("class_name %s" % set_class_name)
	lines.append("")
	lines.append("")
	lines.append("func _init(p_actor_id: String = \"\") -> void:")
	lines.append("\tsuper(p_actor_id)")

	# 基础属性配置（仅本 set 新增的）
	var base_attr_names: Array[String] = []
	for key: String in base_attrs.keys():
		base_attr_names.append(key)
	base_attr_names.sort()

	if not base_attr_names.is_empty():
		lines.append("\t_raw.apply_config({")
		for attr_name in base_attr_names:
			var attr_key := attr_name
			var cfg: Dictionary = base_attrs[attr_name]
			var line := "\t\t\"%s\": { \"baseValue\": %s" % [attr_key, _value_to_string(cfg.get("baseValue", 0.0))]
			if cfg.has("minValue") and cfg["minValue"] != null:
				line += ", \"minValue\": %s" % _value_to_string(cfg["minValue"])
			if cfg.has("maxValue") and cfg["maxValue"] != null:
				line += ", \"maxValue\": %s" % _value_to_string(cfg["maxValue"])
			line += " },"
			lines.append(line)
		lines.append("\t})")

	# Cross-attr clamps：仅本 set 新增属性的 maxRef/minRef
	# source 可在本 set 或祖先链；validate 阶段已过滤。
	var visible_attrs := _collect_visible_attrs(sets, set_name)
	var clamp_lines: Array[String] = []
	for attr_name in base_attr_names:
		var cfg: Dictionary = base_attrs[attr_name]
		for field_name in ["maxRef", "minRef"]:
			if not cfg.has(field_name) or cfg[field_name] == null:
				continue
			var source_attr: String = str(cfg[field_name])
			if not visible_attrs.has(source_attr):
				push_error("Attribute '%s' in set '%s' references %s='%s' but source attribute not defined" % [
					attr_name, set_name, field_name, source_attr
				])
				set_ok = false
				continue
			var bound := "max" if field_name == "maxRef" else "min"
			clamp_lines.append("\t_raw.register_cross_attr_clamp(\"%s\", \"%s\", \"%s\")" % [attr_name, bound, source_attr])

	for clamp_line in clamp_lines:
		lines.append(clamp_line)

	lines.append("")

	# 基础属性访问器（仅本 set 新增；父属性继承自父类，不再生成）
	for attr_name in base_attr_names:
		var attr_key := attr_name
		var safe_key: String = _escape_identifier(attr_key)
		var snake_case_key: String = _to_snake_case(attr_key)
		lines.append("")
		lines.append("var %s: float:" % safe_key)
		lines.append("\tget:")
		lines.append("\t\treturn _raw.get_current_value(\"%s\")" % attr_key)
		lines.append("var %s_breakdown: AttributeBreakdown:" % safe_key)
		lines.append("\tget:")
		lines.append("\t\treturn _raw.get_breakdown(\"%s\")" % attr_key)
		lines.append("func get_%s_breakdown() -> AttributeBreakdown:" % snake_case_key)
		lines.append("\treturn _raw.get_breakdown(\"%s\")" % attr_key)
		lines.append("const %s_attribute := \"%s\"" % [safe_key, attr_key])

		lines.append("func set_%s_base(value: float) -> void:" % snake_case_key)
		lines.append("\t_raw.set_base(\"%s\", value)" % attr_key)
		lines.append("func on_%s_changed(callback: Callable) -> Callable:" % snake_case_key)
		lines.append("\tvar wrapper := func(raw_event: Dictionary) -> void:")
		lines.append("\t\tif raw_event.get(\"attributeName\", \"\") == \"%s\":" % attr_key)
		lines.append("\t\t\tcallback.call(GameEvent.AttributeChanged.create(")
		lines.append("\t\t\t\tactor_id,")
		lines.append("\t\t\t\traw_event.get(\"attributeName\", \"\"),")
		lines.append("\t\t\t\traw_event.get(\"oldValue\", 0.0),")
		lines.append("\t\t\t\traw_event.get(\"newValue\", 0.0),")
		lines.append("\t\t\t))")
		lines.append("\t_raw.add_change_listener(wrapper)")
		lines.append("\treturn func() -> void:")
		lines.append("\t\t_raw.remove_change_listener(wrapper)")

	# 派生属性（仅本 set 新增；可引父属性，generator 不验证表达式合法性，留给运行时）
	var derived_attr_names: Array[String] = []
	for key: String in derived_attrs.keys():
		derived_attr_names.append(key)
	derived_attr_names.sort()
	if not derived_attr_names.is_empty():
		lines.append("")
		lines.append("# ========== Derived Attributes (read-only) ==========")

	for attr_name in derived_attr_names:
		var attr_key := attr_name
		var safe_key: String = _escape_identifier(attr_key)
		var snake_case_key: String = _to_snake_case(attr_key)
		var cfg: Dictionary = derived_attrs[attr_name]
		var derived_cfg: Dictionary = cfg["derived"]
		var expr := _build_derived_expression(derived_cfg)

		if expr.is_empty():
			push_error("Invalid derived config for '%s'" % attr_key)
			set_ok = false
			continue

		lines.append("")
		lines.append("## Derived: %s" % _derived_config_to_comment(derived_cfg))
		lines.append("var %s: float:" % safe_key)
		lines.append("\tget:")
		lines.append("\t\treturn %s" % expr)
		lines.append("func get_%s() -> float:" % snake_case_key)
		lines.append("\treturn %s" % expr)

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write file: %s" % file_path)
		return false
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return set_ok


## 构建派生属性的表达式
## 支持: { "op": "sub", "left": "max_hp", "right": "damage" }
## 支持: { "op": "mul", "left": "strength", "right": 2.5 }
static func _build_derived_expression(cfg: Dictionary) -> String:
	if not cfg.has("op") or not cfg.has("left") or not cfg.has("right"):
		push_error("Derived config must have 'op', 'left', 'right': %s" % str(cfg))
		return ""

	var op: String = cfg["op"]
	var left: Variant = cfg["left"]
	var right: Variant = cfg["right"]

	var left_expr := _operand_to_expression(left)
	var right_expr := _operand_to_expression(right)

	if left_expr.is_empty() or right_expr.is_empty():
		return ""

	match op:
		"sub":
			return "%s - %s" % [left_expr, right_expr]
		"mul":
			return "%s * %s" % [left_expr, right_expr]
		_:
			push_error("Unsupported derived op: %s" % op)
			return ""


## 将操作数转换为表达式
## 字符串 -> 属性引用 (self.xxx)
## 数字 -> 常量
static func _operand_to_expression(operand: Variant) -> String:
	match typeof(operand):
		TYPE_STRING:
			# 属性引用
			var safe_key := _escape_identifier(operand)
			return safe_key
		TYPE_INT, TYPE_FLOAT:
			# 常量
			return str(operand)
		_:
			push_error("Invalid operand type: %s" % str(operand))
			return ""


## 将派生配置转换为注释字符串
static func _derived_config_to_comment(cfg: Dictionary) -> String:
	var op: String = cfg.get("op", "?")
	var left: Variant = cfg.get("left", "?")
	var right: Variant = cfg.get("right", "?")

	var op_symbol := "?"
	match op:
		"sub": op_symbol = "-"
		"mul": op_symbol = "*"

	return "%s %s %s" % [str(left), op_symbol, str(right)]


static func _escape_identifier(name: String) -> String:
	if _SHADOWED_GLOBAL_IDENTIFIERS.has(name):
		return "%s_" % name
	return name


static func _to_snake_case(pascal_case: String) -> String:
	# 如果已经包含下划线，假定已经是 snake_case
	if "_" in pascal_case:
		return pascal_case.to_lower()

	var result := ""
	for i in range(pascal_case.length()):
		var c := pascal_case[i]
		# 在大写字母前添加下划线（除了第一个字符）
		if c == c.to_upper() and c.to_lower() != c and i > 0:
			result += "_"
		result += c.to_lower()
	return result


static func _value_to_string(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING:
			return "\"%s\"" % value.c_escape()
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT, TYPE_FLOAT:
			return str(value)
		TYPE_NIL:
			return "null"
		_:
			return str(value)
