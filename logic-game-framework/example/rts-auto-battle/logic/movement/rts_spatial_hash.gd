## RtsSpatialHash - cell_size=64 桶索引, 邻域查询用 (P2.2)
##
## 替代 P1.2 的 O(N²) RtsMinimalPushOut 邻接扫描:
##   N 单位的"找邻居"成本从 O(N²) 降为 O(N) 平均 (邻居 ≤ 9 桶, 每桶平均 1-2 单位)。
##
## 用法 (procedure 主循环):
##   _spatial_hash.update_all(world.get_alive_units())
##   for each unit:
##       var ids := _spatial_hash.query_radius(unit.position_2d, search_radius)
##       # ids 已按 actor_id 排序 (决定性), 调方按 id 取 actor 做 distance 精确过滤
##
## 决定性 (replay bit-equal 必备):
##   - bucket key = Vector2i(floor(x/cs), floor(y/cs)); 浮点同输入 → 同桶, 平台无关
##   - update_all 增量: 同桶不写, 跨桶才 remove+add (insertion order 影响 keys() 遍历, 但
##     query_radius 输出 sort() 后稳定)
##   - query_radius 返回的数组 .sort() 字典序; 不依赖 hashing 顺序
##
## 决策来源: phase-2-core-systems.md §P2.2
class_name RtsSpatialHash
extends RefCounted


## 默认 bucket size (像素)。64 = 2 * 标准单位 collision_radius * 2 (留 8px 余量)。
## 调大: 邻居桶变疏 (每次 query 候选少); 调小: 桶迁移更频繁 (insertion churn 增加)。
const DEFAULT_CELL_SIZE: float = 64.0


# ========== 字段 ==========

var cell_size: float = DEFAULT_CELL_SIZE

## bucket_key (Vector2i) → Dictionary[actor_id (String), true]
var _buckets: Dictionary = {}

## actor_id → 当前 bucket key (Vector2i); 用于增量 update 时判断是否需要 remove/add
var _actor_to_bucket: Dictionary = {}


# ========== 初始化 ==========

func _init(p_cell_size: float = DEFAULT_CELL_SIZE) -> void:
	cell_size = p_cell_size


# ========== 增量更新 ==========

## 添加 / 移动 actor 到当前位置对应的 bucket (同桶则 no-op, 跨桶则 remove+add)。
func update(actor_id: String, pos: Vector2) -> void:
	var new_bucket: Vector2i = _bucket_of(pos)
	if _actor_to_bucket.has(actor_id):
		var old_bucket: Vector2i = _actor_to_bucket[actor_id]
		if old_bucket == new_bucket:
			return
		_remove_from_bucket(actor_id, old_bucket)
	_actor_to_bucket[actor_id] = new_bucket
	var bucket: Dictionary = _buckets.get(new_bucket, {}) as Dictionary
	bucket[actor_id] = true
	_buckets[new_bucket] = bucket


## 单 actor 注销 (死亡 / 销毁时调)。
func unregister(actor_id: String) -> void:
	if not _actor_to_bucket.has(actor_id):
		return
	var bucket_key: Vector2i = _actor_to_bucket[actor_id]
	_remove_from_bucket(actor_id, bucket_key)
	_actor_to_bucket.erase(actor_id)


## 批量更新: 把 hash 与 actors 列表对齐。
##   - 列表中 actor 全 update (新位置进对应 bucket)
##   - 列表中没有但 hash 中存在的 actor (上一帧死亡 / 移除) 自动 unregister
##
## 调方约定: 每 tick 调一次 (在 steering / push-out 之前)。
func update_all(actors: Array) -> void:
	var seen: Dictionary = {}
	for a in actors:
		var actor := a as RtsBattleActor
		if actor == null:
			continue
		var aid: String = actor.get_id()
		seen[aid] = true
		update(aid, actor.position_2d)
	# Erase actors that disappeared between calls (death / removal)
	for stale_id in _actor_to_bucket.keys().duplicate():
		if not seen.has(stale_id):
			unregister(stale_id)


## 全清 (战斗结束 / reset 用)。
func clear() -> void:
	_buckets.clear()
	_actor_to_bucket.clear()


# ========== 查询 ==========

## 返回 center 周围 radius 像素内 bucket 中所有 actor_id (含 center 自身所在 bucket)。
##
## 注: 返回的 ids 是"候选" — 同 bucket 内但实际距离 > radius 的也会包含。调方需按
## actor.position_2d.distance_to(center) 精确过滤。
##
## 返回数组按 actor_id 字典序排序 (决定性: replay 同 seed 跑 2 次必须出同样顺序)。
func query_radius(center: Vector2, radius: float) -> Array[String]:
	var result: Array[String] = []
	var span: int = int(ceilf(radius / cell_size))
	var center_bucket: Vector2i = _bucket_of(center)
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			var key := Vector2i(center_bucket.x + dx, center_bucket.y + dy)
			if not _buckets.has(key):
				continue
			var bucket: Dictionary = _buckets[key]
			for aid in bucket.keys():
				result.append(aid as String)
	result.sort()
	return result


## 当前注册 actor 数 (debug / smoke 用)
func get_actor_count() -> int:
	return _actor_to_bucket.size()


## 当前非空 bucket 数 (debug / smoke 用)
func get_bucket_count() -> int:
	return _buckets.size()


# ========== 内部 ==========

func _bucket_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floorf(pos.x / cell_size)), int(floorf(pos.y / cell_size)))


func _remove_from_bucket(actor_id: String, bucket_key: Vector2i) -> void:
	if not _buckets.has(bucket_key):
		return
	var bucket: Dictionary = _buckets[bucket_key]
	bucket.erase(actor_id)
	if bucket.is_empty():
		_buckets.erase(bucket_key)
