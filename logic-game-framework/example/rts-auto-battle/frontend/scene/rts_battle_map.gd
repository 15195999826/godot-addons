## RtsBattleMap - 500×500 RTS 战场场景(P1.2: grid 替代 navmesh)
##
## P1.2 重写: 去 NavigationRegion2D / NavigationPolygon, 改为 RtsBattleGrid (SQUARE
## grid_type, cell_size = 32) 描述战场。中央 (200..300, 200..300) 障碍由 grid cells
## 标 is_blocking 表达 — 决策 D3-B / D3-F (走 ultra-grid-map plugin, 不动插件本身)。
##
## 障碍范围: 标 cells (cols 6..9, rows 6..9) is_blocking, 像素覆盖 (192..320, 192..320),
## 略宽于 M0 的 100×100 obstacle 区(200..300), 但仍允许出生位 (50, 230) / (50, 270) 落在
## 非阻挡 cell — slot 1/2 的横向接敌仍必须绕路, 服务 AC2 主断言。
##
## headless 调方不再需要 await physics_frame: grid + A* 是同步算法, 路径立即可用。
class_name RtsBattleMap
extends Node2D


const MAP_WIDTH: float = 500.0
const MAP_HEIGHT: float = 500.0

const OBSTACLE_X_MIN: float = 200.0
const OBSTACLE_X_MAX: float = 300.0
const OBSTACLE_Y_MIN: float = 200.0
const OBSTACLE_Y_MAX: float = 300.0


var grid: RtsBattleGrid = null


func _ready() -> void:
	grid = RtsBattleGrid.new(Vector2(MAP_WIDTH, MAP_HEIGHT), RtsBattleGrid.DEFAULT_CELL_SIZE, Vector2.ZERO)
	_mark_obstacle_cells()


# ========== 内部 ==========

## 把中央障碍区域内的 cells 标 is_blocking。
## 用 cell_size=32 时 obstacle (200..300, 200..300) 横跨 cells (6..9, 6..9)
## (cell 6 起 192, cell 9 终 320; cell 边界稍宽于 obstacle 区)。
func _mark_obstacle_cells() -> void:
	var cs: float = grid.cell_size
	var col_min: int = int(floorf(OBSTACLE_X_MIN / cs))
	var col_max: int = int(floorf((OBSTACLE_X_MAX - 0.001) / cs))
	var row_min: int = int(floorf(OBSTACLE_Y_MIN / cs))
	var row_max: int = int(floorf((OBSTACLE_Y_MAX - 0.001) / cs))
	for row in range(row_min, row_max + 1):
		for col in range(col_min, col_max + 1):
			var coord := HexCoord.new(col, row)
			if grid.has_tile(coord):
				grid.model.set_tile_blocking(coord, true)


# ========== 查询 ==========

## 给 smoke / frontend 用的"对方阵营出生点"。team 0 → x≈50, team 1 → x≈450。
##
## 当 total_slots == 4 时使用专门排布: y ∈ {80, 230, 270, 420}。
## - slot 0 & 3 在顶 / 底, 接敌路径不过中央障碍 (200..300, 200..300)
## - slot 1 & 2 都在 y=230/270 (障碍中线): 接敌必绕 grid path, 服务 AC2 主断言
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
