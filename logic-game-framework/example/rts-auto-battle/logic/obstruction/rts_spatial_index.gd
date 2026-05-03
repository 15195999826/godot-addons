## RtsSpatialIndex - Uniform grid bucket spatial index (M2 引入)
##
## 0 A.D. `helpers/Pathfinding.cpp` `BasicSpatialQuery` 的 GDScript 复刻 — 给 RtsObstructionManager
## 加速半径范围查询(get_obstructions_in_range / test_*_shape)。
##
## **算法**: uniform grid bucket — 把世界拆成 BUCKET_SIZE px 的方桶,每个 shape 注册到它的
##           AABB 覆盖的所有桶里; query 时只扫被 query 范围覆盖的桶,O(buckets × shapes_per_bucket)
##           而非 O(全 shape)。
##
## **参数选择** (M2 H2 决策 A):
##   - `BUCKET_SIZE = 256 px` = 8 navcell × 32 px,平衡 100 单位规模:
##     - 单位 query 半径 通常 < 256 → 1-4 个桶
##     - 全图 ~1024 px square → ~16 桶,bucket 数适中,Dictionary 不会膨胀
##   - 100 单位 × 平均 5 个 bucket(单位移动到 4 桶交界时跨多桶)= 500 entries,小 BUCKET 查询更精准
##   - 若 ≥500 单位 perf 超 50% → M3 时换 quadtree (data-structures.md §2.4 已留接口)
##
## **Determinism contract** (M3 Epic §12.4):
##   `query_circle` 末尾必须 `sort()` 强制返回 tag 升序; ObstructionManager.get_obstructions_in_range
##   依赖此排序,replay bit-identical 才能保证。
##
## **0 A.D. 对照**:
##   - `helpers/Pathfinding.cpp:BasicSpatialQuery` 是 hash-of-bucket 风格的相同算法
##   - 我们用 GDScript Dictionary[Vector2i, Array[int]] 取代 unordered_map<u16, vector<entity_t>>
##
## **决策来源**:
##   - data-structures.md §2.4 (RtsSpatialIndex 字段定义)
##   - milestones/M2-obstruction-manager.md §M2.2 (步骤 / API spec) + §H2 (BUCKET_SIZE 选择)
class_name RtsSpatialIndex
extends RefCounted


## Bucket 边长 (px)。8 navcell (cell_size=32) × 32 = 256。
const BUCKET_SIZE: int = 256


# ========== 字段 ==========

## bucket index (Vector2i) → Array[int (tag)]。每桶持有覆盖到此桶的 shape tags。
var _buckets: Dictionary = {}

## tag (int) → Array[Vector2i (bucket indices)]。反向索引, 让 remove / update 不必重算 AABB。
##
## **为什么需要**: remove(tag) 时若没有反向索引, 要重新算 shape 当前 AABB → 桶覆盖 → 从每个桶 erase。
##                  反向索引把这步 O(buckets) 重算降到 O(1) 查询 + O(buckets) erase, 也避开了"shape
##                  半径在 remove / update 之间已被外部改动"的潜在 bug。
var _shape_buckets: Dictionary = {}


# ========== 内部 helper ==========

## 计算 (pos ± radius) AABB 覆盖的所有 bucket index。
##
## **数学**: bucket_x = floor((pos.x ± radius) / BUCKET_SIZE),y 同理。
## 返回 (max_i - min_i + 1) × (max_j - min_j + 1) 个 bucket index。
func _bucket_indices(pos: Vector2, radius: float) -> Array[Vector2i]:
	var min_i: int = int(floorf((pos.x - radius) / float(BUCKET_SIZE)))
	var max_i: int = int(floorf((pos.x + radius) / float(BUCKET_SIZE)))
	var min_j: int = int(floorf((pos.y - radius) / float(BUCKET_SIZE)))
	var max_j: int = int(floorf((pos.y + radius) / float(BUCKET_SIZE)))
	var result: Array[Vector2i] = []
	for j in range(min_j, max_j + 1):
		for i in range(min_i, max_i + 1):
			result.append(Vector2i(i, j))
	return result


# ========== 公开 API ==========

## 注册一个 shape 到所有它 AABB 覆盖的桶。
##
## **前置**: tag 必须未被 insert 过 (否则 _shape_buckets 会被覆盖, 旧桶 entry 泄漏)。
##           调方 (ObstructionManager) 保证 tag 单调递增不复用。
func insert(tag: int, pos: Vector2, radius: float) -> void:
	var indices: Array[Vector2i] = _bucket_indices(pos, radius)
	for k in indices:
		var arr: Array = _buckets.get(k, [])
		arr.append(tag)
		_buckets[k] = arr
	_shape_buckets[tag] = indices


## 从所有桶 erase tag,清反向索引。
##
## **幂等**: 重复 remove 不存在的 tag 不报错 (M2.5 unit death 链路 + safety net)。
func remove(tag: int, _pos: Vector2, _radius: float) -> void:
	if not _shape_buckets.has(tag):
		return
	var indices: Array = _shape_buckets[tag]
	for k in indices:
		var arr: Array = _buckets.get(k, [])
		arr.erase(tag)
		if arr.is_empty():
			_buckets.erase(k)
		else:
			_buckets[k] = arr
	_shape_buckets.erase(tag)


## 移动 shape:remove (旧 AABB 桶) + insert (新 AABB 桶)。
##
## **优化预留**: 如果 old / new AABB 桶集合**完全相同** (单位移动幅度 < BUCKET_SIZE 且未跨界),
##                可以 short-circuit 不动桶 — M3 / M7 perf hot 时再加;M2 阶段每 tick 都 remove+insert
##                不影响 100 单位规模。
func update(tag: int, old_pos: Vector2, new_pos: Vector2, radius: float) -> void:
	remove(tag, old_pos, radius)
	insert(tag, new_pos, radius)


## 查询 (pos ± query_range) AABB 覆盖的桶, 返回所有 tag, **按升序**。
##
## **参数命名**: 用 `query_range` 而非 `range` 避免 shadow GDScript builtin `range(int)`。
##
## **去重**: 一个 shape 在 N 个桶里都注册过,只返回一次。
##
## **Determinism**: 末尾 `result.sort()` 强制 tag 升序 — ObstructionManager.get_obstructions_in_range
##                  依赖此, replay bit-identical 才稳。
##
## **注**: 此函数返回的是 AABB 桶覆盖的 tag, **不是** 真正圆相交 — 调方 (test_unit_shape /
##         test_static_shape) 拿到 tag 后还要做精确 circle/OBB 相交。spatial index 只是"粗筛"。
func query_circle(pos: Vector2, query_range: float) -> Array[int]:
	var indices: Array[Vector2i] = _bucket_indices(pos, query_range)
	var seen: Dictionary = {}
	var result: Array[int] = []
	for k in indices:
		if not _buckets.has(k):
			continue
		for tag in _buckets[k]:
			if not seen.has(tag):
				seen[tag] = true
				result.append(tag)
	result.sort()  # determinism: tag 升序 (data-structures §12.4)
	return result


# ========== 调试 / 测试辅助 ==========

## 返回当前已注册 shape 数 (= _shape_buckets.size())。给 smoke 单元测试用。
func size() -> int:
	return _shape_buckets.size()


## 返回当前桶数 (Dictionary entry 数)。给 smoke 验证 bucket 内存不泄漏用。
func bucket_count() -> int:
	return _buckets.size()
