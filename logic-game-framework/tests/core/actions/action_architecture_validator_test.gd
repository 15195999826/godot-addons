extends Node

## ActionArchitectureValidator V1 测试
##
## 锁住 §0.0 Action 分层合同的硬约束:
## 1. 实际仓库 scan 必须干净 (所有历史 BaseAction 直接继承者都在 allowlist)
## 2. allowlist 中每条都必须真实存在 (防止条目漂)
## 3. 给一个 mock "新增 Action 直接 extends BaseAction 且未 allowlist" 必须报错

const VALIDATOR := preload("res://addons/logic-game-framework/core/actions/action_architecture_validator.gd")


func _init() -> void:
	TestFramework.register_test("Repo scan is clean (all historical actions allowlisted)", _test_repo_scan_clean)
	TestFramework.register_test("Allowlist entries all reference existing files", _test_allowlist_entries_exist)
	TestFramework.register_test("Allowlist entries have migrate_by metadata", _test_allowlist_has_migrate_by)
	TestFramework.register_test("New extends BaseAction outside allowlist is flagged", _test_violation_detected_for_temp_file)
	TestFramework.register_test("New PrimitiveAction without class_name in allowlist is flagged", _test_new_public_class_name_flagged)


func _test_repo_scan_clean() -> void:
	var report = VALIDATOR.scan_repo()
	TestFramework.assert_true(report.is_clean(),
		"Validator violations:\n" + report.summary())


func _test_allowlist_entries_exist() -> void:
	for path in VALIDATOR.ALLOWLIST.keys():
		var f := FileAccess.open(path, FileAccess.READ)
		TestFramework.assert_true(f != null, "Allowlist references missing file: %s" % path)
		if f != null:
			f.close()


func _test_allowlist_has_migrate_by() -> void:
	for path in VALIDATOR.ALLOWLIST.keys():
		var entry: Dictionary = VALIDATOR.ALLOWLIST[path]
		TestFramework.assert_true(entry.has("reason"), "Allowlist entry missing 'reason': %s" % path)
		TestFramework.assert_true(entry.has("migrate_by"), "Allowlist entry missing 'migrate_by': %s" % path)


func _test_violation_detected_for_temp_file() -> void:
	# 写一个 mock public action 直接 extends BaseAction，validator 必须 flag
	var tmp_dir := "user://action_validator_test/"
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tmp_path := tmp_dir + "mock_new_action.gd"
	var content := "class_name MockNewAction\nextends Action.BaseAction\n"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	var report = VALIDATOR.scan_file(tmp_path)
	var has_direct_extends := false
	for v in report.violations:
		if v.category == "direct_extends_base_action_not_allowed":
			has_direct_extends = true
	TestFramework.assert_true(has_direct_extends, "Expected direct_extends_base_action_not_allowed violation")


func _test_new_public_class_name_flagged() -> void:
	# 一个 public-style class_name 不在 allowlist 必须 fail
	var tmp_dir := "user://action_validator_test/"
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tmp_path := tmp_dir + "mock_rogue_action.gd"
	var content := "class_name MockRogueAction\nextends Action.PrimitiveAction\n"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	var report = VALIDATOR.scan_file(tmp_path)
	var has_class_name_violation := false
	for v in report.violations:
		if v.category == "public_class_name_missing_from_allowlist":
			has_class_name_violation = true
	TestFramework.assert_true(has_class_name_violation,
		"Expected public_class_name_missing_from_allowlist violation, got: %s" % report.summary())
