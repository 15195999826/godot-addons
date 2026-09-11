extends Node

## AttributeSetGeneratorScript 的生成器自身逻辑测试：
##   1. config 自动发现（固定两处 + example/*/logic/attributes/ 扫描）
##   2. 跨 config set 名冲突预检（重名会生成重复 class_name，必须整体拒绝）
##   3. 生成主链路：给定 SETS 写出产物文件（输出到 user://，不污染 res:// 与全局 class_name）

const TEMP_OUTPUT_DIR := "user://test_attribute_set_generator_out"


func _init() -> void:
	TestFramework.register_test("Generator discovery includes fixed + example-local configs", _test_discovery)
	TestFramework.register_test("Generator rejects duplicate set name across configs", _test_duplicate_set_name_rejected)
	TestFramework.register_test("Generator accepts unique set names across configs", _test_unique_set_names_pass)
	TestFramework.register_test("Generator writes attribute set file from SETS", _test_generate_to_temp_dir)
	TestFramework.register_test("Generator reports failure on invalid derived config", _test_invalid_derived_fails)
	TestFramework.register_test("Generator rejects clamp fields outside the resource contract", _test_clamp_fields_only_on_resources)
	TestFramework.register_test("Generator reports failure on unwritable output dir", _test_unwritable_output_dir_fails)


func _test_discovery() -> void:
	var paths := AttributeSetGeneratorScript.discover_config_paths()
	# 断言"包含"而非"恰好"：未来加 example 不应打碎本测试
	var expected: Array[String] = [
		AttributeSetGeneratorScript.PROJECT_CONFIG_PATH,
		AttributeSetGeneratorScript.SHARED_EXAMPLE_CONFIG_PATH,
		"res://addons/logic-game-framework/example/dota2-auto-battle/logic/attributes/attributes_config.gd",
		"res://addons/logic-game-framework/example/hex-atb-battle/logic/attributes/attributes_config.gd",
	]
	for expected_path in expected:
		TestFramework.assert_true(paths.has(expected_path), "discovery includes %s" % expected_path)


func _test_duplicate_set_name_rejected() -> void:
	# 预期路径：冲突会 push_error（headless 输出可见），返回 false 即为正确行为
	var entries: Array[Dictionary] = [
		{ "path": "res://config_a.gd", "sets": { "SharedName": {} } },
		{ "path": "res://config_b.gd", "sets": { "SharedName": {} } },
	]
	TestFramework.assert_false(
		AttributeSetGeneratorScript._validate_unique_set_names(entries),
		"duplicate set name across configs must be rejected"
	)


func _test_unique_set_names_pass() -> void:
	var entries: Array[Dictionary] = [
		{ "path": "res://config_a.gd", "sets": { "AlphaActor": {}, "AlphaUnit": {} } },
		{ "path": "res://config_b.gd", "sets": { "BetaActor": {} } },
	]
	TestFramework.assert_true(
		AttributeSetGeneratorScript._validate_unique_set_names(entries),
		"unique set names across configs must pass"
	)


func _test_generate_to_temp_dir() -> void:
	var sets := {
		"GenSmokeActor": {
			"hp": { "kind": "resource", "baseValue": 10.0, "minValue": 0.0, "maxRef": "max_hp" },
			"max_hp": { "baseValue": 10.0, "minValue": 1.0 },
		},
		"GenSmokeUnit": {
			"_extends": "GenSmokeActor",
			"power": { "baseValue": 3.0 },
		},
	}
	var ok := AttributeSetGeneratorScript._generate_from_config(
		"res://in_memory_test_config.gd", sets, TEMP_OUTPUT_DIR
	)
	TestFramework.assert_true(ok, "generation from in-memory SETS succeeds")

	var actor_path := TEMP_OUTPUT_DIR + "/gen_smoke_actor_attribute_set.gd"
	var unit_path := TEMP_OUTPUT_DIR + "/gen_smoke_unit_attribute_set.gd"
	TestFramework.assert_true(FileAccess.file_exists(actor_path), "root set file written")
	TestFramework.assert_true(FileAccess.file_exists(unit_path), "child set file written")

	var actor_content := FileAccess.get_file_as_string(actor_path)
	TestFramework.assert_true(
		actor_content.contains("class_name GenSmokeActorAttributeSet"),
		"root set declares generated class_name"
	)
	# 资源属性：config 行带 kind + maxRef（apply_config 按 key 顺序定义，上限晚于资源也行），
	# 写入器是 set_hp / add_hp，不生成 base setter / breakdown 访问器，也不再注册跨属性 clamp。
	TestFramework.assert_true(
		actor_content.contains("\"hp\": { \"kind\": \"resource\", \"baseValue\": 10.0, \"minValue\": 0.0, \"maxRef\": \"max_hp\" },"),
		"resource config line carries kind + maxRef"
	)
	TestFramework.assert_true(
		actor_content.contains("func set_hp(value: float) -> void:\n\t_raw.set_resource(\"hp\", value)"),
		"resource writer set_hp generated"
	)
	TestFramework.assert_true(
		actor_content.contains("func add_hp(delta: float) -> void:\n\t_raw.add_resource(\"hp\", delta)"),
		"resource writer add_hp generated"
	)
	TestFramework.assert_true(actor_content.contains("const hp_attribute := \"hp\""), "resource keeps attribute name const")
	TestFramework.assert_true(actor_content.contains("func on_hp_changed(callback: Callable) -> Callable:"), "resource keeps change subscription")
	TestFramework.assert_false(actor_content.contains("_raw.set_base(\"hp\""), "resource has no base setter")
	TestFramework.assert_false(actor_content.contains("var hp_breakdown"), "resource has no breakdown property")
	TestFramework.assert_false(actor_content.contains("get_hp_breakdown"), "resource has no breakdown getter")
	# stat 属性照旧
	TestFramework.assert_true(actor_content.contains("func set_max_hp_base(value: float) -> void:"), "stat keeps base setter")
	TestFramework.assert_true(actor_content.contains("var max_hp_breakdown: AttributeBreakdown:"), "stat keeps breakdown property")

	var unit_content := FileAccess.get_file_as_string(unit_path)
	TestFramework.assert_true(
		unit_content.contains("extends GenSmokeActorAttributeSet"),
		"_extends generates class inheritance"
	)


## maxRef 只属于资源（stat 走 modifier 管线，没有跨属性上限）；资源的上限只能是 maxRef（静态 maxValue
## 与 minRef 都不在契约里）。预期路径：违规字段会 push_error（headless 输出可见），返回 false 即为正确行为。
func _test_clamp_fields_only_on_resources() -> void:
	var stat_with_max_ref := {
		"GenSmokeBadStat": {
			"mana": { "baseValue": 10.0, "maxRef": "max_mana" },
			"max_mana": { "baseValue": 10.0 },
		},
	}
	TestFramework.assert_false(
		AttributeSetGeneratorScript._generate_from_config(
			"res://in_memory_test_config.gd", stat_with_max_ref, TEMP_OUTPUT_DIR
		),
		"maxRef on a stat attribute must fail the config generation"
	)

	var resource_with_max_value := {
		"GenSmokeBadResource": {
			"mana": { "kind": "resource", "baseValue": 10.0, "maxValue": 10.0 },
		},
	}
	TestFramework.assert_false(
		AttributeSetGeneratorScript._generate_from_config(
			"res://in_memory_test_config.gd", resource_with_max_value, TEMP_OUTPUT_DIR
		),
		"maxValue on a resource must fail the config generation (its cap is maxRef)"
	)

	var min_ref := {
		"GenSmokeBadMinRef": {
			"mana": { "kind": "resource", "baseValue": 10.0, "minRef": "floor" },
			"floor": { "baseValue": 0.0 },
		},
	}
	TestFramework.assert_false(
		AttributeSetGeneratorScript._generate_from_config(
			"res://in_memory_test_config.gd", min_ref, TEMP_OUTPUT_DIR
		),
		"minRef is outside the contract and must fail the config generation"
	)


func _test_invalid_derived_fails() -> void:
	# 预期路径：无效 derived op 会 push_error（headless 输出可见），返回 false 即为正确行为
	var sets := {
		"GenSmokeBadDerived": {
			"strength": { "baseValue": 1.0 },
			"broken": { "derived": { "op": "div", "left": "strength", "right": 2.0 } },
		},
	}
	TestFramework.assert_false(
		AttributeSetGeneratorScript._generate_from_config(
			"res://in_memory_test_config.gd", sets, TEMP_OUTPUT_DIR
		),
		"invalid derived op must fail the config generation (no silent partial output)"
	)


func _test_unwritable_output_dir_fails() -> void:
	# 用一个普通文件挡住目录路径，使 make_dir_recursive_absolute 失败
	var blocker_path := "user://test_attr_gen_blocker"
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	blocker.store_string("dir blocker")
	blocker.close()

	var sets := { "GenSmokeBlocked": { "hp": { "baseValue": 1.0 } } }
	TestFramework.assert_false(
		AttributeSetGeneratorScript._generate_from_config(
			"res://in_memory_test_config.gd", sets, blocker_path + "/generated"
		),
		"unwritable output dir must fail the config generation"
	)
