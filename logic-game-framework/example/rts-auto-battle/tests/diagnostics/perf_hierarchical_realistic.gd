## Diagnostic: RtsHierarchicalPathfinder.recompute realistic demo perf 观测
##
## 96×96 grid (1 chunk) + 16 个 5×5 building 块状 obstacle,模拟 castle_war 1v1 demo 实际规模。
## 跑 100 iter dump median / p99 / max。**纯 info dump,不出 PASS/FAIL 退出码**。
##
## 拆分理由 (2026-05-04 从 smoke_hierarchical_perf 移过来):
## - 原本设计意图是"M4c 启动决策一次性 gate"(p99 ≤ 30ms 跳过 M4c, > 30ms 必做 M4c)
## - M4 末态 single-run p99=28 ms ≤ 阈值,**M4c 已 CANCEL**(见 Current-State.md M4 段)
## - gate 价值已过期;parallel test launcher 下 CPU contention 让 wall-clock 数据假 fail
##   (实测 M5 末态 5x parallel 下 p99=31 ms 略超阈值,单跑 p99=28 ms 仍合格)
## - 留作 perf 回归探测器,后续 milestone 跑对比 M5 baseline 是否退化
##
## Synthetic 192/384/768 future-warning 在同目录 `perf_hierarchical_synthetic.tscn`。
##
## **跑法**: 编辑器 F6 / 命令行 `godot --headless --path . tests/diagnostics/perf_hierarchical_realistic.tscn`
## **不依赖 actor / world / battle** — 纯算法层 perf。
extends Node


# ========== 常量 ==========

const _REALISTIC_GRID_SIZE: int = 96     # 1 chunk = 典型 castle_war demo 规模 (1024×768 px / ~32 navcell)
const _REALISTIC_BUILDINGS: int = 16     # 与 spec §1 "16 building" 对齐
const _REALISTIC_BUILDING_SIZE: int = 5  # 平均 building footprint = 5×5 navcells

const _ITERATIONS: int = 100
const _SEED: int = 0x4d345045  # "M4PE"
const _P99_THRESHOLD_REFERENCE_USEC: int = 30000   # 参考值(spec §1 = 30 ms),不再 gate


# ========== 状态 ==========

var _realistic_result: Dictionary = {}


# ========== 入口 ==========

func _ready() -> void:
	GameWorld.init()

	_realistic_result = _bench_realistic_demo()
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


func _print_summary() -> void:
	print("")
	print("=== HierarchicalPathfinder.recompute Realistic Perf (info only) ===")
	print("Iterations: %d, Seed: 0x%x" % [_ITERATIONS, _SEED])
	print("Reference threshold: p99 ≤ %d us (= %d ms / tick) — spec §1, M4c gate 已 CANCEL,仅作回归参考" % [
		_P99_THRESHOLD_REFERENCE_USEC, _P99_THRESHOLD_REFERENCE_USEC / 1000,
	])
	print("(Synthetic 192/384/768 在同目录 perf_hierarchical_synthetic.tscn)")
	print("")
	print("--- Realistic demo ---")
	print("| case | grid | chunks | obstacle | median (us) | p99 (us) | max (us) | within threshold |")
	print("|------|------|--------|----------|-------------|----------|----------|------------------|")
	var r: Dictionary = _realistic_result
	var r_within: String = "YES" if r["p99_usec"] <= _P99_THRESHOLD_REFERENCE_USEC else "NO"
	print("| realistic_demo | %d × %d | %d | %d building × %d² | %d | %d | %d | %s |" % [
		r["grid_size"], r["grid_size"], r["chunks"],
		_REALISTIC_BUILDINGS, _REALISTIC_BUILDING_SIZE,
		r["median_usec"], r["p99_usec"], r["max_usec"], r_within,
	])
	print("")
