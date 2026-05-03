## RtsNavcellGrid - Multi-class navcell 数据 grid (PackedInt32Array 16-bit 位掩码)
##
## 替换 RtsBattleGrid 内部 per-cell `is_blocking: bool` 存储 (M0 末态: 走 ultra-grid-map
## plugin 的 model.is_tile_blocking 单一阻挡标记) → 多 class passability 位掩码。每个 navcell
## 一个 int (16 bit), 每 bit 表示 "对该 class 不能通过"。
##
## 不变量:
##   - _data 长度 = _width * _height; _dirtiness 同等长度
##   - row-major: _idx(i, j) = j * width + i (i=col, j=row)
##   - is_passable 边界外返 false (防越界, 跟 0 A.D. helpers/Pathfinding.h 一致)
##   - or_data / and_data 仅在实际改变值时 mark dirty (精确 dirty 集合)
##
## Determinism: PackedInt32Array 跨平台字节序由 Godot 标准化; 不直接 serialize 此 grid
## (replay 序列化 actor state, grid 是 derived; 漂只能从 actor sort 顺序 / 写入顺序漂)。
##
## Dirty lifecycle (R5 P1-2 决策, M3.4+ 重要):
##   - rasterize / hierarchical update 路径只读 dirtiness, 不清
##   - RtsWorld.tick step 7 末端统一 clear_dirty()
##   - 任何路径在 step 5-6 中间清 dirty 视为 invariant 违反 (stop runner 第 8 条)
##
## 决策来源:
##   - data-structures §1.4 (字段定义)
##   - 0 A.D. 对照: Grid<NavcellData> (helpers/Grid.h) + dirtinessGrid (CCmpPathfinder)
##   - typedef u16 NavcellData (helpers/Pathfinding.h:130) — 我们用 int (Godot 没 u16)
class_name RtsNavcellGrid
extends RefCounted


# ========== 常量 ==========

## 跟 RtsBattleGrid.cell_size 一致 (D3-G); pathing 单位 = 1 navcell = 32 px
const NAVCELL_SIZE_PX: int = 32


# ========== 字段 ==========

var _width: int = 0
var _height: int = 0
var _data: PackedInt32Array = PackedInt32Array()
var _dirtiness: PackedByteArray = PackedByteArray()


# ========== 初始化 ==========

func _init(w: int, h: int) -> void:
	_width = w
	_height = h
	_data.resize(w * h)
	_dirtiness.resize(w * h)


# ========== 内部 ==========

## row-major index; 调方应保证 (i, j) 在范围内, 越界访问 PackedInt32Array 会 crash。
func _idx(i: int, j: int) -> int:
	return j * _width + i


# ========== 读 / 查询 ==========

## 读 cell 数据; 边界外返 -1。
func get_data(i: int, j: int) -> int:
	if i < 0 or i >= _width or j < 0 or j >= _height:
		return -1
	return _data[_idx(i, j)]


## 该 class 对此 cell 是否可通行; 边界外返 false (视为阻挡, 跟 0 A.D. 一致)。
##
## class_mask 由 RtsPassabilityClassRegistry.get_mask("class_name") 取。
func is_passable(i: int, j: int, class_mask: int) -> bool:
	if i < 0 or i >= _width or j < 0 or j >= _height:
		return false
	return (_data[_idx(i, j)] & class_mask) == 0


# ========== 写 ==========

## 整个 cell 数据替换; 边界内调方信任 (越界 crash); 立即 mark dirty。
func set_data(i: int, j: int, value: int) -> void:
	var k := _idx(i, j)
	_data[k] = value
	_dirtiness[k] = 1


## 设 mask 对应 bit (= 该 class 在此 cell 不可通过); 仅在值变化时 mark dirty。
##
## 用例: place_building 时把 default class bit 设上 → 单位走不进。
func or_data(i: int, j: int, mask: int) -> void:
	var k := _idx(i, j)
	if (_data[k] & mask) != mask:
		_data[k] = _data[k] | mask
		_dirtiness[k] = 1


## 清 inverse_mask 对应 bit (= 该 class 在此 cell 重新可通过); 仅在值变化时 mark dirty。
##
## 用例: remove_building 时把 default class bit 清掉 → 单位重新能走。
##
## 注: 参数命名沿 0 A.D. 风格 inverse_mask 是 "想清掉的 bit", 内部用 `& ~inverse_mask`。
func and_data(i: int, j: int, inverse_mask: int) -> void:
	var k := _idx(i, j)
	if (_data[k] & ~inverse_mask) != _data[k]:
		_data[k] = _data[k] & ~inverse_mask
		_dirtiness[k] = 1


# ========== Dirty lifecycle (M3.4+ 重要) ==========

## 显式标 dirty (set_data / or_data / and_data 已自动标; 此方法用于"不改值但需重标"场景)。
func mark_dirty(i: int, j: int) -> void:
	_dirtiness[_idx(i, j)] = 1


## 是否 dirty。
func is_dirty(i: int, j: int) -> bool:
	if i < 0 or i >= _width or j < 0 or j >= _height:
		return false
	return _dirtiness[_idx(i, j)] != 0


## 全部清 dirty。RtsWorld.tick step 7 末端调用 (R5 P1-2 决策);
## rasterize / hierarchical update 路径只读 dirtiness 不调此方法。
func clear_dirty() -> void:
	for k in range(_dirtiness.size()):
		_dirtiness[k] = 0


# ========== 元信息 ==========

func width() -> int:
	return _width


func height() -> int:
	return _height


# ========== 坐标转换 (内联 helper) ==========

## navcell (i, j) 中心的世界坐标 (px)。
func navcell_center_world(i: int, j: int) -> Vector2:
	return Vector2((float(i) + 0.5) * NAVCELL_SIZE_PX, (float(j) + 0.5) * NAVCELL_SIZE_PX)


## 世界坐标 → 最近 navcell index (Vector2i, x=i, y=j)。
##
## 边界外的 world_pos 返回的 index 也可能越界, 调方需要再走 is_passable / get_data 边界判定。
func nearest_navcell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / NAVCELL_SIZE_PX), int(world_pos.y / NAVCELL_SIZE_PX))
