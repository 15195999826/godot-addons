## Smoke test: FrontendShieldBarView 多类型分条布局契约
##
## 白盒,不走 main.tscn。直接实例化 FrontendShieldBarView,喂构造的
## FrontendActorRenderState,断言子条网格的数量 / 颜色 / Y 偏移堆叠,
## 以及空护盾态全隐藏。
##
## 覆盖:
##   1. 3 个不同 config_id → 3 条可见护盾条
##   2. 3 条颜色互不相同(按 config_id 分色)
##   3. 条 Y 偏移不重叠(间距 >= BAR_HEIGHT)
##   4. 排序 priority desc → config_id asc:bottom→top = magical/physical/ward
##   5. 空护盾态 → 全条隐藏
##
## 退出码: 0 PASS / 1 FAIL,标记: "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


const PHYS_COLOR := Color(0.95, 0.62, 0.28)
const MAG_COLOR := Color(0.25, 0.85, 1.0)
const WARD_COLOR := Color(0.3, 0.5, 1.0)


func _ready() -> void:
	print("=== Smoke Test: Shield Bar Layout ===")
	Log.set_level(Log.LogLevel.WARNING)

	var view := FrontendShieldBarView.new()
	add_child(view)

	# 3 个不同类型护盾:physical(pri10) / magical(pri10) / ward(pri0)
	var state := FrontendActorRenderState.new()
	state.shields.append(_summary("phys_1", "buff_physical_shield", 20.0, 30.0, PHYS_COLOR, 10))
	state.shields.append(_summary("mag_1", "buff_magical_shield", 30.0, 30.0, MAG_COLOR, 10))
	state.shields.append(_summary("ward_1", "buff_ward", 15.0, 30.0, WARD_COLOR, 0))
	view.update_from_state(state)

	var bars := _visible_bars(view)
	if bars.size() != 3:
		_fail("expected 3 visible bars, got %d" % bars.size())
		return
	print("  + Step 1 OK: 3 个类型 → 3 条可见护盾条")

	var colors := {}
	for b in bars:
		colors[str((b.material_override as StandardMaterial3D).albedo_color)] = true
	if colors.size() != 3:
		_fail("expected 3 distinct bar colors, got %d" % colors.size())
		return
	print("  + Step 2 OK: 3 条颜色互不相同")

	var sorted_bars := bars.duplicate()
	sorted_bars.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return a.position.y < b.position.y)
	for i in range(1, sorted_bars.size()):
		var dy: float = sorted_bars[i].position.y - sorted_bars[i - 1].position.y
		if dy < FrontendShieldBarView.BAR_HEIGHT:
			_fail("bars overlap: dy=%f < BAR_HEIGHT=%f" % [dy, FrontendShieldBarView.BAR_HEIGHT])
			return
	print("  + Step 3 OK: 条 Y 偏移不重叠 (间距 >= BAR_HEIGHT)")

	# 排序 priority desc → config_id asc:
	#   pri10: buff_magical_shield < buff_physical_shield(字典序)
	#   pri0:  buff_ward 最后
	# bottom(最小 y,贴 HP)→ top: magical / physical / ward
	var expect := [MAG_COLOR, PHYS_COLOR, WARD_COLOR]
	for i in range(3):
		var c: Color = (sorted_bars[i].material_override as StandardMaterial3D).albedo_color
		if not c.is_equal_approx(expect[i]):
			_fail("bar[%d] color %s != expected %s (sort: pri desc → cid asc)" % [i, c, expect[i]])
			return
	print("  + Step 4 OK: 排序 bottom→top = magical(pri10)/physical(pri10)/ward(pri0)")

	# 填充比例:magical 满(30/30=1.0),physical 20/30,ward 15/30
	if not is_equal_approx(sorted_bars[0].scale.x, 1.0):
		_fail("magical bar scale.x=%f (expected 1.0)" % sorted_bars[0].scale.x)
		return
	if not is_equal_approx(sorted_bars[2].scale.x, 0.5):
		_fail("ward bar scale.x=%f (expected 0.5)" % sorted_bars[2].scale.x)
		return
	print("  + Step 4b OK: 填充比例正确 (magical=1.0, ward=0.5)")

	var empty := FrontendActorRenderState.new()
	view.update_from_state(empty)
	if _visible_bars(view).size() != 0:
		_fail("after empty state, bars should all be hidden")
		return
	print("  + Step 5 OK: 空护盾态 → 全条隐藏")

	_pass()


func _summary(
	id: String, cid: String, cur: float, cap: float, col: Color, pri: int
) -> FrontendShieldSummary:
	var s := FrontendShieldSummary.new()
	s.id = id
	s.config_id = cid
	s.current = cur
	s.capacity = cap
	s.color = col
	s.priority = pri
	return s


func _visible_bars(view: FrontendShieldBarView) -> Array:
	var out: Array = []
	for c in view.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).visible:
			out.append(c)
	return out


func _pass() -> void:
	print("SMOKE_TEST_RESULT: PASS - shield bar layout: per-type stacked bars verified")
	GameWorld.destroy()
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	GameWorld.destroy()
	get_tree().quit(1)
