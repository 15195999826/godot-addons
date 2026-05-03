## RtsHierarchicalChunk - 单 chunk 内的 per-class region 分配 (M4 引入)
##
## 0 A.D. `helpers/HierarchicalPathfinder.h:175-205` 的 `struct Chunk` 复刻。
##
## 一个 chunk 覆盖 96×96 navcells (CHUNK_SIZE 跟 0 A.D. 一致)。每 navcell 在 chunk 内
## 被分配一个 local region ID(从 1 起;0 = impassable / 不属于任何 region)。region 通过
## chunk-internal flood-fill 划分(BFS,起点字典序 §12.2)。
##
## **内存布局**:
##   - `regions: PackedInt32Array` 长度 = CHUNK_SIZE² = 9216 个 int (36 KB / chunk),
##     row-major: `idx = local_j * CHUNK_SIZE + local_i`
##   - `regions_id: PackedInt32Array` 此 chunk 内所有有效 local region ID(1..N),
##     按 BFS 起点顺序 append → 单调递增,deterministic
##
## **何时被外部读**:
##   - RtsHierarchicalPathfinder.recompute / update — 写 regions
##   - get_region(local_i, local_j) — 取某 navcell 的 local region ID
##   - regions_id 给 _compute_global_regions 枚举所有 packed RegionID(R5 P1 #3 修订:
##     必须含 isolated region,所以走 chunks_id 而不是 edges.keys())
##
## **决策来源**:
##   - data-structures.md §4.3
##   - milestones/M4-hierarchical.md §M4a.2
##   - 0 A.D. CHUNK_SIZE = 96 (helpers/HierarchicalPathfinder.h:177)
class_name RtsHierarchicalChunk
extends RefCounted


# ========== 常量 ==========

## chunk 边长(navcells)。与 0 A.D. 一致(`helpers/HierarchicalPathfinder.h:177`)。
const CHUNK_SIZE: int = 96


# ========== 字段 ==========

## chunk index (世界坐标 chunk 列)。
var ci: int = 0

## chunk index (世界坐标 chunk 行)。
var cj: int = 0

## 此 chunk 内所有有效 local region ID(1..N),BFS 起点顺序 append → 单调递增。
## 0(impassable)不进此列表。
var regions_id: PackedInt32Array = PackedInt32Array()

## 长度 = CHUNK_SIZE²(9216),每 navcell 的 local region ID。
## 0 = impassable / 未分配;> 0 = 该 navcell 属于哪个 region。
## row-major:`regions[local_j * CHUNK_SIZE + local_i]`。
var regions: PackedInt32Array = PackedInt32Array()


# ========== 初始化 ==========

func _init(c_i: int, c_j: int) -> void:
	ci = c_i
	cj = c_j
	regions.resize(CHUNK_SIZE * CHUNK_SIZE)


# ========== 查询 ==========

## 取 chunk 内 (local_i, local_j) 的 local region ID。
##
## 0 = impassable / 未分配;> 0 = 该 navcell 所属 region(chunk-local 编号)。
## **调方约束**:local_i / local_j ∈ [0, CHUNK_SIZE);越界由调方负责(PackedInt32Array 越界 crash)。
func get_region(local_i: int, local_j: int) -> int:
	return regions[local_j * CHUNK_SIZE + local_i]


## 计算指定 local region 的几何中心(chunk 内坐标,Vector2i)。
##
## 暴力扫整 chunk(O(CHUNK_SIZE²)= O(9216))— 不缓存,调方按需调用。region 不存在时返
## `Vector2i(-1, -1)`。
##
## 用途:debug / M4b 寻路 heuristic / 体验点观察。
func region_center(r: int) -> Vector2i:
	var sum_i: int = 0
	var sum_j: int = 0
	var count: int = 0
	for j in range(CHUNK_SIZE):
		var row_base: int = j * CHUNK_SIZE
		for i in range(CHUNK_SIZE):
			if regions[row_base + i] == r:
				sum_i += i
				sum_j += j
				count += 1
	if count == 0:
		return Vector2i(-1, -1)
	return Vector2i(sum_i / count, sum_j / count)
