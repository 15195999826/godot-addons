## Diagnostic: HierarchicalPathfinder.recompute synthetic perf 未来预警面板
##
## 192² / 384² / 768² grid + 10% scattered obstacle 是 BFS worst case,跑 100 iter dump
## median / p99 / max。**纯 info dump,不出 PASS/FAIL 退出码**(从 smoke_hierarchical_perf 拆出)。
##
## 拆分理由: 768² × 100 iter ≈ 24-47s GDScript 纯算法成本(64 chunks × 9216 cells × 4 邻居 BFS),
## 预期 timeout 是测试框架机制(timeout=FAIL)误把 info-only case 反客为主成 gate。
## 拆出去后 realistic 96² 1-2s 秒过 smoke gate,synthetic 大 grid 谁需要谁手跑,info-only 语义保留。
##
## **跑法**: 编辑器 F6 / 命令行 `godot --headless --path . tests/diagnostics/perf_hierarchical_synthetic.tscn`
##
## **未来阈值参考**: M4 spec p99 ≤ 30 ms (= 30000 us);超阈说明 demo 规模上去后需启动 M4c
## (incremental hierarchical update 替代 full recompute)。当前 demo 规模 96² 远低于此,
## synthetic 数据是"地图变 4 倍 / 16 倍后会怎样"的预测仪。
##
## 单跑大约 **30-90s**(GDScript per-cell BFS,无 timeout 约束)。
extends Node


# ========== 常量 ==========

const _GRID_SIZES: Array[int] = [192, 384, 768]
const _OBSTACLE_PERCENT: int = 10
const _ITERATIONS: int = 100
const _SEED: int = 0x4d345045  # "M4PE" — 跟 smoke_hierarchical_perf 同 seed 保数据可对照
const _P99_THRESHOLD_USEC: int = 30000


# ========== 状态 ==========

var _results: Array[Dictionary] = []


# ========== 入口 ==========

func _ready() -> void:
	GameWorld.init()

	print("=== HierarchicalPathfinder.recompute Synthetic Perf (info only) ===")
	print("Iterations per case: %d, Seed: 0x%x" % [_ITERATIONS, _SEED])
	print("Threshold reference: p99 ≤ %d us (= %d ms / tick)" % [
		_P99_THRESHOLD_USEC, _P99_THRESHOLD_USEC / 1000,
	])
	print("")

	for grid_size in _GRID_SIZES:
		print("跑 synthetic_%d (10%% scattered)..." % grid_size)
		var stats: Dictionary = _bench_synthetic(grid_size)
		_results.append(stats)

	_print_summary()
	GameWorld.destroy()
	get_tree().quit(0)


# ========== Helpers ==========

func _make_registry_default_only() -> RtsPassabilityClassRegistry:
	var registry := RtsPassabilityClassRegistry.new()
	var ground_cfg := RtsPassabilityClassConfig.new()
	ground_cfg.class_name_id = "default"
	ground_cfg.clearance = 14.0
	registry.register(ground_cfg)
	return registry


func _make_synthetic_grid(size: int, mask: int) -> RtsNavcellGrid:
	var grid := RtsNavcellGrid.new(size, size)
	grid.set_origin_world(Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED + size
	var threshold: int = _OBSTACLE_PERCENT * 1000
	for j in range(size):
		for i in range(size):
			if rng.randi_range(0, 99999) < threshold:
				grid.or_data(i, j, mask)
	return grid


func _bench(grid: RtsNavcellGrid, classes: Array[RtsPassabilityClassConfig], label: String) -> Dictionary:
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
		chunks = 1
	return {
		"label": label,
		"grid_size": grid.width(),
		"chunks": chunks,
		"median_usec": median,
		"p99_usec": p99,
		"max_usec": max_t,
	}


func _bench_synthetic(grid_size: int) -> Dictionary:
	var registry := _make_registry_default_only()
	var grid: RtsNavcellGrid = _make_synthetic_grid(grid_size, registry.get_mask("default"))
	return _bench(grid, registry.get_classes(), "synthetic_%d" % grid_size)


func _print_summary() -> void:
	print("")
	print("--- Synthetic future warning (info only) ---")
	print("| case | grid | chunks | obstacle | median (us) | p99 (us) | max (us) | within threshold |")
	print("|------|------|--------|----------|-------------|----------|----------|------------------|")
	for s in _results:
		var within: String = "YES" if s["p99_usec"] <= _P99_THRESHOLD_USEC else "NO"
		print("| %s | %d × %d | %d | %d%% scattered | %d | %d | %d | %s |" % [
			s["label"], s["grid_size"], s["grid_size"], s["chunks"],
			_OBSTACLE_PERCENT,
			s["median_usec"], s["p99_usec"], s["max_usec"], within,
		])
	print("")
