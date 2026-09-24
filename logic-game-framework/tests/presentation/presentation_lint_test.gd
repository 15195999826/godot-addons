extends Node

## presentation/ 目录的边界 lint（adr/0013 D1 / D2）
##
## 钉住合同：
## - 框架件不认识任何项目方言：presentation/ 下不出现 hex 词（HexCoord / HexFacing / HexBattle / BattleEvents /
##   ProjectileEvents）、不出现退役词（Visualizer / RenderWorld / Scheduler）、不带项目前缀（Frontend / InkMon）
## - 只讲逻辑平面 Vector2：不出现 Vector3 / GridLayout / 像素投影
## - 依赖方向 presentation/ → core/：不引用 stdlib/、example/、ultra-grid-map
## - 每个 .gd 都有 class_name 且无前缀（词表 D3），并带同名 .gd.uid


const PRESENTATION_DIR := "res://addons/logic-game-framework/presentation"

## 内容里一律不许出现的词
const FORBIDDEN_TOKENS: Array[String] = [
	"HexCoord", "HexFacing", "HexBattle", "BattleEvents", "ProjectileEvents",
	"Visualizer", "RenderWorld", "Scheduler",
	"Frontend", "InkMon",
	"Vector3", "GridLayout",
	"logic-game-framework/stdlib", "logic-game-framework/example", "ultra-grid-map", "ultra_grid_map",
]


func _init() -> void:
	TestFramework.register_test("presentation lint 不含 hex 词 / 退役词 / 项目前缀 / 3D / stdlib·example 依赖", _test_no_forbidden_tokens)
	TestFramework.register_test("presentation lint 每个脚本带无前缀 class_name 与 .uid", _test_class_names_and_uids)


static func _collect_scripts(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	TestFramework.assert_true(dir != null, "open %s" % dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_scripts(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _test_no_forbidden_tokens() -> void:
	var scripts: Array[String] = []
	_collect_scripts(PRESENTATION_DIR, scripts)
	TestFramework.assert_true(scripts.size() >= 20, "presentation/ 至少 20 个脚本（core 11 + actions 12），实得 %d" % scripts.size())
	for path in scripts:
		var text := FileAccess.get_file_as_string(path)
		TestFramework.assert_true(not text.is_empty(), "read %s" % path)
		for token in FORBIDDEN_TOKENS:
			TestFramework.assert_false(text.contains(token), "%s 含禁词 '%s'" % [path, token])


func _test_class_names_and_uids() -> void:
	var scripts: Array[String] = []
	_collect_scripts(PRESENTATION_DIR, scripts)
	var seen := {}
	for path in scripts:
		var text := FileAccess.get_file_as_string(path)
		var regex := RegEx.new()
		regex.compile("(?m)^class_name\\s+([A-Za-z0-9_]+)")
		var found := regex.search(text)
		TestFramework.assert_true(found != null, "%s 缺 class_name" % path)
		if found == null:
			continue
		var class_id := found.get_string(1)
		TestFramework.assert_false(seen.has(class_id), "class_name %s 重复" % class_id)
		seen[class_id] = true
		TestFramework.assert_false(class_id.begins_with("Frontend") or class_id.begins_with("InkMon"), "%s 带项目前缀" % class_id)
		TestFramework.assert_true(FileAccess.file_exists(path + ".uid"), "%s 缺 .uid" % path)
