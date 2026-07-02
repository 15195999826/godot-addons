extends Node

# Native backend load probe: the extension registered its classes and a
# roundtrip call works. Everything goes through ClassDB indirection — this
# script must parse on platforms without a built native library.

var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map native extension load")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	if not ClassDB.class_exists("SimNavNativeSupport"):
		_failures.append("SimNavNativeSupport not registered (extension not loaded; build native/ or check simnav_native.gdextension)")
		return
	var support: Object = ClassDB.instantiate("SimNavNativeSupport")
	if support == null:
		_failures.append("ClassDB.instantiate(SimNavNativeSupport) returned null")
		return
	var version := str(support.call("version"))
	if version.is_empty():
		_failures.append("version() returned empty string")
	var info_variant: Variant = support.call("build_info")
	if not (info_variant is Dictionary):
		_failures.append("build_info() did not return a Dictionary")
		return
	var info := info_variant as Dictionary
	for key in ["version", "platform", "threads", "build"]:
		if not info.has(key):
			_failures.append("build_info() missing key: %s" % key)
	if str(info.get("version", "")) != version:
		_failures.append("build_info().version != version() (%s vs %s)" % [info.get("version"), version])
	print("[native-load] version=%s info=%s" % [version, str(info)])
