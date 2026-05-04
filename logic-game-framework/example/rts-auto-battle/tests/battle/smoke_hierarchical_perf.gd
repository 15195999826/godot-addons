## RtsHierarchicalPathfinder.recompute perf gate (M4 — M4c 启动决策)
##
## **目的**: 测 M4a full recompute wall-clock 时间,决定是否启动 M4c sub-phase。
##
## **决策模型**(2026-05-04 用户确认):
##   - **Realistic demo case = 阈值判**: 96×96 grid (1 chunk) + 16 个 building 块 ~5×5 navcell
##     模拟 castle_war 1v1 demo 实际规模。p99 ≤ 30 ms 才 PASS。
##   - **Synthetic case = info / 未来预警**: 192²/384²/768² + 10% scattered obstacle 是
##     BFS worst case。p99 超阈不阻塞 PASS,但保留数据 — 未来 demo 规模上去后(更大 grid /
##     更多 dynamic building)若超阈则补 M4c。
##
## **决策依据**:realistic demo p99 = M4 milestone 是否能现阶段收口的关键;synthetic
## p99 = "未来预警面板"。两者并存,不二选一。
##
## **不依赖 actor / world / battle** — 纯算法层 perf,只测 RtsHierarchicalPathfinder.recompute。
extends Node


# ========== 常量 ==========

## 测试 case 配置:realistic 是阈值判,synthetic 是未来预警。
const _REALISTIC_GRID_SIZE: int = 96     # 1 chunk = 典型 castle_war demo 规模 (1024×768 px / ~32 navcell)
const _REALISTIC_BUILDINGS: int = 16     # 与 spec §1 "16 building" 对齐
const _REALISTIC_BUILDING_SIZE: int = 5  # 平均 building footprint = 5×5 navcells

const _SYNTHETIC_GRID_SIZES: Array[int] = [192, 384, 768]
const _SYNTHETIC_OBSTACLE_PERCENT: int = 10

## 每 case 跑 recompute 次数。
const _ITERATIONS: int = 100

## 固定 seed 保 deterministic。
const _SEED: int = 0x4d345045  # "M4PE"

## p99 阈值(微秒)。spec §1 = 30 ms。仅 realistic case 必须 ≤ 此值。
const _P99_THRESHOLD_USEC: int = 30000


# ========== 状态 ==========

var _failures: Array[String] = []
var _realistic_result: Dictionary = {}
var _synthetic_results: Array[Dictionary] = []


# ========== 入口 ==========

func _ready() -> void:
	GameWorld.init()

	# 1) Realistic demo case — 阈值判
	_realistic_result = _bench_realistic_demo()
	_check_threshold(_realistic_result, true)

	# 2) Synthetic future-warning cases — info only,不阻塞 PASS
	for grid_size in _SYNTHETIC_GRID_SIZES:
		var stats: Dictionary = _bench_synthetic(grid_size)
		_synthetic_results.append(stats)

	_print_summary()

	if _failures.is_empty():
		var realistic_p99: int = _realistic_result["p99_usec"]
		print("SMOKE_TEST_RESULT: PASS - hierarchical_perf — realistic demo p99=%d us ≤ %d us (skip M4c)" % [
			realistic_p99, _P99_THRESHOLD_USEC,
		])
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Helpers ==========

func _make_registry_default_only() -> RtsPassabilityClassRegistry:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	return registry


## Realistic demo grid:96×96 navcells(1 chunk),16 个 5×5 building 块状 obstacle。
##
## Building 中心按 stratified random 分布(rng 固定 seed),不重叠地铺到 grid 上。
## 模拟 castle_war 1v1 demo 实际场景:1 个 chunk + 集中块 obstacle(不是 10% scattered)。
func _make_realistic_grid(mask: int) -> RtsNavcellGrid:
	var grid := RtsNavcellGrid.new(_REALISTIC_GRID_SIZE, _REALISTIC_GRID_SIZE)
	grid.set_origin_world(Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED
	# 16 building → 4×4 stratified bins。每 bin 内 random 取 building 中心。
	var bin_count: int = 4
	var bin_size: int = _REALISTIC_GRID_SIZE / bin_count
	var half: int = _REALISTIC_BUILDING_SIZE / 2
	for bj in range(bin_count):
		for bi in range(bin_count):
			var ci: int = bi * bin_size + rng.randi_range(half, bin_size - half - 1)
			var cj: int = bj * bin_size + rng.randi_range(half, bin_size - half - 1)
			for dj in range(-half, half + 1):
				for di in range(-half, half + 1):
					var i: int = ci + di
					var j: int = cj + dj
					if i >= 0 and i < _REALISTIC_GRID_SIZE and j >= 0 and j < _REALISTIC_GRID_SIZE:
						grid.or_data(i, j, mask)
	return grid


## Synthetic 大 grid + 10% scattered obstacle(BFS worst case)。
func _make_synthetic_grid(size: int, mask: int) -> RtsNavcellGrid:
	var grid := RtsNavcellGrid.new(size, size)
	grid.set_origin_world(Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED + size
	var threshold: int = _SYNTHETIC_OBSTACLE_PERCENT * 1000
	for j in range(size):
		for i in range(size):
			if rng.randi_range(0, 99999) < threshold:
				grid.or_data(i, j, mask)
	return grid


## 跑 _ITERATIONS 次 recompute,返回 timing 统计 + 描述字段。
func _bench(grid: RtsNavcellGrid, classes: Array[RtsPassabilityClassConfig], label: String) -> Dictionary:
	# Warmup 1 次
	var warmup_hp := RtsHierarchicalPathfinder.new()
	warmup_hp.recompute(grid, classes)

	var timings_usec: PackedInt64Array = PackedInt64Array()
	for k in range(_ITERATIONS):
		var hp := RtsHierarchicalPathfinder.new()
		var t0: int = Time.get_ticks_usec()
		hp.recompute(grid, classes)
		var dt: int = Time.get_ticks_usec() - t0
		timings_usec.append(dt)

	var sorted: Array[int] = []
	for t in timings_usec:
		sorted.append(t)
	sorted.sort()

	var median: int = sorted[sorted.size() / 2]
	var p99_idx: int = int(float(sorted.size() - 1) * 0.99)
	var p99: int = sorted[p99_idx]
	var max_t: int = sorted[sorted.size() - 1]
	var chunks: int = (grid.width() * grid.height()) / (96 * 96)
	if chunks == 0:
		chunks = 1   # 96² = 1 chunk(向下取整为 0,修正)
	return {
		"label": label,
		"grid_size": grid.width(),
		"chunks": chunks,
		"median_usec": median,
		"p99_usec": p99,
		"max_usec": max_t,
	}


func _bench_realistic_demo() -> Dictionary:
	var registry := _make_registry_default_only()
	var grid: RtsNavcellGrid = _make_realistic_grid(registry.get_mask("default"))
	return _bench(grid, registry.get_classes(), "realistic_demo")


func _bench_synthetic(grid_size: int) -> Dictionary:
	var registry := _make_registry_default_only()
	var grid: RtsNavcellGrid = _make_synthetic_grid(grid_size, registry.get_mask("default"))
	return _bench(grid, registry.get_classes(), "synthetic_%d" % grid_size)


func _check_threshold(stats: Dictionary, must_pass: bool) -> void:
	if not must_pass:
		return
	var p99: int = stats["p99_usec"]
	if p99 > _P99_THRESHOLD_USEC:
		_failures.append(
			"%s grid %d² (p99=%d us > %d us threshold) — M4c 必须启动" % [
				stats["label"], stats["grid_size"], p99, _P99_THRESHOLD_USEC,
			]
		)


func _print_summary() -> void:
	print("")
	print("=== HierarchicalPathfinder.recompute Perf Gate ===")
	print("Iterations per case: %d, Seed: 0x%x" % [_ITERATIONS, _SEED])
	print("Threshold: p99 ≤ %d us (= %d ms / tick) — 仅 realistic case 必须满足" % [
		_P99_THRESHOLD_USEC, _P99_THRESHOLD_USEC / 1000,
	])
	print("")
	print("--- Realistic demo (阈值判) ---")
	print("| case | grid | chunks | obstacle | median (us) | p99 (us) | max (us) | within threshold |")
	print("|------|------|--------|----------|-------------|----------|----------|------------------|")
	var r: Dictionary = _realistic_result
	var r_within: String = "YES" if r["p99_usec"] <= _P99_THRESHOLD_USEC else "NO"
	print("| realistic_demo | %d × %d | %d | %d building × %d² | %d | %d | %d | %s |" % [
		r["grid_size"], r["grid_size"], r["chunks"],
		_REALISTIC_BUILDINGS, _REALISTIC_BUILDING_SIZE,
		r["median_usec"], r["p99_usec"], r["max_usec"], r_within,
	])
	print("")
	print("--- Synthetic future warning (info only,不阻塞 PASS) ---")
	print("| case | grid | chunks | obstacle | median (us) | p99 (us) | max (us) | within threshold |")
	print("|------|------|--------|----------|-------------|----------|----------|------------------|")
	for s in _synthetic_results:
		var within: String = "YES" if s["p99_usec"] <= _P99_THRESHOLD_USEC else "NO"
		print("| %s | %d × %d | %d | %d%% scattered | %d | %d | %d | %s |" % [
			s["label"], s["grid_size"], s["grid_size"], s["chunks"],
			_SYNTHETIC_OBSTACLE_PERCENT,
			s["median_usec"], s["p99_usec"], s["max_usec"], within,
		])
	print("")
