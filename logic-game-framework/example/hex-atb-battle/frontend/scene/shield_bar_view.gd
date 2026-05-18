## ShieldBarView - 护盾条子组件（按类型分条）
##
## UnitView 的 attached visual,显示在血条上方。响应 update_from_state 同步
## actor.shields 数组。
##
## 策略：
##   - 按 shield.config_id 分组,每个类型独立一条(physical / magical / ward
##     各自一条),同 config_id 的多个独立实例在该条内聚合 sum(current)/sum(capacity)。
##   - 条按 priority desc → config_id asc 排序(确定性;与 ShieldResolver 消耗序
##     一致,先被消耗的类型固定贴近 HP 条)。
##   - 每条颜色 = 该组 summary.color(ShieldBarVisualizer 已按 config_id 分色写入)。
##   - 条竖直堆叠,bar i 在 base_offset + i*BAR_STEP;组内 current/capacity=0 或
##     无 shields 时对应条隐藏。
##
## 条网格池化复用(_bars):组数变化只增不删 MeshInstance3D,多余的 visible=false,
## 避免每帧创建/销毁。环境单位经 UnitView.set_environment_style 把整个 view
## Node3D visible=false,子条随父不渲染,无需特殊分支。
class_name FrontendShieldBarView
extends Node3D


## 最贴近 HP 条的护盾条 Y 偏移(HP 条在 1.2,高 0.1,顶 ~1.25)。后续条向上堆叠。
@export var shield_bar_offset: float = 1.34


const BAR_WIDTH := 1.0
## 比 HP 条(0.1)略厚,远相机下仍可辨;3 条堆叠玩家一眼能读。
const BAR_HEIGHT := 0.13
const BAR_DEPTH := 0.1
## 条间距 = 条高 + 间隙,保证相邻条不重叠。
const BAR_GAP := 0.04
const BAR_STEP := BAR_HEIGHT + BAR_GAP


## 池化的护盾条网格,index 即堆叠层(0 = 最贴近 HP 条)。
var _bars: Array[MeshInstance3D] = []


func update_from_state(state: FrontendActorRenderState) -> void:
	_apply(state.shields)


## 按 config_id 分组渲染。shields 元素为 FrontendShieldSummary。
func _apply(shields: Array) -> void:
	if shields.is_empty():
		_hide_from(0)
		return

	# config_id → {current, capacity, color, priority}
	var groups: Dictionary = {}
	for s in shields:
		var summary: FrontendShieldSummary = s
		var cid := summary.config_id
		if groups.has(cid):
			var g: Dictionary = groups[cid]
			g["current"] = (g["current"] as float) + summary.current
			g["capacity"] = (g["capacity"] as float) + summary.capacity
		else:
			groups[cid] = {
				"config_id": cid,
				"current": summary.current,
				"capacity": summary.capacity,
				"color": summary.color,
				"priority": summary.priority,
			}

	var ordered: Array = groups.values()
	ordered.sort_custom(_compare_groups)

	var visible_count := 0
	for entry in ordered:
		var group: Dictionary = entry
		var cur := group["current"] as float
		var cap := group["capacity"] as float
		if cap <= 0.0 or cur <= 0.0:
			continue
		var bar := _ensure_bar(visible_count)
		var mat := bar.material_override as StandardMaterial3D
		mat.albedo_color = group["color"] as Color
		bar.scale.x = maxf(0.01, cur / cap)
		bar.position = Vector3(0.0, shield_bar_offset + visible_count * BAR_STEP, 0.0)
		bar.visible = true
		visible_count += 1

	_hide_from(visible_count)


## 排序：priority desc → config_id asc(确定性)。
func _compare_groups(a: Dictionary, b: Dictionary) -> bool:
	var pa := a["priority"] as int
	var pb := b["priority"] as int
	if pa != pb:
		return pa > pb
	return (a["config_id"] as String) < (b["config_id"] as String)


## 取/建第 idx 层护盾条(懒创建并入池)。
func _ensure_bar(idx: int) -> MeshInstance3D:
	while _bars.size() <= idx:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(BAR_WIDTH, BAR_HEIGHT, BAR_DEPTH)
		bar.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar.material_override = mat
		bar.name = "ShieldBar%d" % _bars.size()
		bar.visible = false
		add_child(bar)
		_bars.append(bar)
	return _bars[idx]


## 隐藏 from_idx 起的所有条(组数收缩 / 无护盾时清场)。
func _hide_from(from_idx: int) -> void:
	for i in range(from_idx, _bars.size()):
		_bars[i].visible = false
