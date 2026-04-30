## RtsBattleMap - 500×500 RTS 战场场景
##
## 编程式构造 NavigationRegion2D + NavigationPolygon, 不用编辑器烘焙资源。
## 地图是 500×500 矩形, 中央 (200..300, 200..300) 一块矩形障碍。
##
## NavigationPolygon 用 3×3 网格(共 8 个凸四边形, 跳过中央障碍格)显式拼出可走区域。
## 关键: 相邻 polygon 必须**精确共享端点对**, NavigationServer2D 才会把它们连成可达图。
## (避免上一版"大条带"切法因端点不匹配导致路径在障碍前断开。)
##
## 顶点网格 x ∈ {0, 200, 300, 500}, y ∈ {0, 200, 300, 500} = 16 顶点;
## 中心格 (vertex 5,6,10,9 = obstacle 四角) 不进 polygon 数组 = 障碍。
##
## headless 调方在用 navmesh 之前必须 `await get_tree().physics_frame` 至少一次
## 让 NavigationServer2D.sync_map 跑一遍。
class_name RtsBattleMap
extends Node2D


const MAP_WIDTH: float = 500.0
const MAP_HEIGHT: float = 500.0

const OBSTACLE_X_MIN: float = 200.0
const OBSTACLE_X_MAX: float = 300.0
const OBSTACLE_Y_MIN: float = 200.0
const OBSTACLE_Y_MAX: float = 300.0


var navigation_region: NavigationRegion2D = null


func _ready() -> void:
	navigation_region = NavigationRegion2D.new()
	add_child(navigation_region)

	var nav_poly := NavigationPolygon.new()

	# 3×3 grid, 16 顶点 (4 列 × 4 行)
	# 索引规则: row * 4 + col
	#   row 0: y=0, row 1: y=200, row 2: y=300, row 3: y=500
	#   col 0: x=0, col 1: x=200, col 2: x=300, col 3: x=500
	var verts := PackedVector2Array([
		Vector2(0.0, 0.0),                         # 0
		Vector2(OBSTACLE_X_MIN, 0.0),              # 1
		Vector2(OBSTACLE_X_MAX, 0.0),              # 2
		Vector2(MAP_WIDTH, 0.0),                   # 3
		Vector2(0.0, OBSTACLE_Y_MIN),              # 4
		Vector2(OBSTACLE_X_MIN, OBSTACLE_Y_MIN),   # 5  obstacle TL
		Vector2(OBSTACLE_X_MAX, OBSTACLE_Y_MIN),   # 6  obstacle TR
		Vector2(MAP_WIDTH, OBSTACLE_Y_MIN),        # 7
		Vector2(0.0, OBSTACLE_Y_MAX),              # 8
		Vector2(OBSTACLE_X_MIN, OBSTACLE_Y_MAX),   # 9  obstacle BL
		Vector2(OBSTACLE_X_MAX, OBSTACLE_Y_MAX),   # 10 obstacle BR
		Vector2(MAP_WIDTH, OBSTACLE_Y_MAX),        # 11
		Vector2(0.0, MAP_HEIGHT),                  # 12
		Vector2(OBSTACLE_X_MIN, MAP_HEIGHT),       # 13
		Vector2(OBSTACLE_X_MAX, MAP_HEIGHT),       # 14
		Vector2(MAP_WIDTH, MAP_HEIGHT),            # 15
	])
	nav_poly.set_vertices(verts)

	# 8 个 polygon, 跳过中心格(5,6,10,9), 顺时针顶点序
	# Top row
	nav_poly.add_polygon(PackedInt32Array([0, 1, 5, 4]))   # TL
	nav_poly.add_polygon(PackedInt32Array([1, 2, 6, 5]))   # TM
	nav_poly.add_polygon(PackedInt32Array([2, 3, 7, 6]))   # TR
	# Middle row (skip center)
	nav_poly.add_polygon(PackedInt32Array([4, 5, 9, 8]))   # ML
	nav_poly.add_polygon(PackedInt32Array([6, 7, 11, 10])) # MR
	# Bottom row
	nav_poly.add_polygon(PackedInt32Array([8, 9, 13, 12])) # BL
	nav_poly.add_polygon(PackedInt32Array([9, 10, 14, 13]))# BM
	nav_poly.add_polygon(PackedInt32Array([10, 11, 15, 14]))# BR

	nav_poly.agent_radius = 6.0
	nav_poly.cell_size = 1.0

	navigation_region.navigation_polygon = nav_poly


# ========== 查询 ==========

## 给 smoke / frontend 用的"对方阵营出生点"。team 0 → x≈50, team 1 → x≈450。
##
## 当 total_slots == 4 时使用专门排布: y ∈ {80, 250, 250, 420}。
## - slot 0 & 3 在顶 / 底, 接敌路径不过中央障碍 (200..300, 200..300)
## - slot 1 & 2 都在 y=250 (障碍中线): 接敌必绕 navmesh, 服务 AC2 主断言
## 其它 total_slots 退化为 [80, 420] 均分(M1 扩到 8v8 时再细化)。
static func sample_team_spawn(team_id: int, slot: int, total_slots: int) -> Vector2:
	var x: float = 50.0 if team_id == 0 else 450.0
	if total_slots == 4:
		# y=230 / y=270 都在中央障碍 (y in 200..300) 范围内, 必绕路接敌
		var ys: PackedFloat32Array = PackedFloat32Array([80.0, 230.0, 270.0, 420.0])
		return Vector2(x, ys[slot])
	var span_top: float = 80.0
	var span_bottom: float = MAP_HEIGHT - 80.0
	var span: float = span_bottom - span_top
	var step: float = span / max(1, total_slots - 1) if total_slots > 1 else 0.0
	var y: float = span_top + step * float(slot)
	return Vector2(x, y)
