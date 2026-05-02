## RtsGroupFormation - 多单位编队 offset 计算 (P3.2)
##
## 当玩家选中 N 单位下同一移动命令时, 把单一 target_pos 拆成 N 个偏移目标
## (target_pos + offset[i]), 让 N 单位抵达后排成方阵, 不挤一团。
##
## 算法 = 居中方阵 (square grid):
##   - cols = ceil(sqrt(N))  最少列数让 rows ≤ cols (略宽于高, 适合 RTS 朝向)
##   - rows = ceil(N / cols)
##   - offset[i] = ((col_index - col_center_offset) × spacing,
##                  (row_index - row_center_offset) × spacing)
##   - col_center_offset = (cols - 1) / 2.0  让方阵几何中心对齐 target_pos
##   - 末行 (可能不满) 居中: 末行起始 col 偏移 = (cols - last_row_count) / 2.0
##
## spacing 默认 30 px:
##   - melee collision_radius = 12 → 2r = 24, 留 6 px 安全间隙避免 steering 撞抖
##   - ranged collision_radius = 10 → 2r = 20, spacing 30 时 separation 余量更宽
##   - flying_scout 同 ranged 半径
##
## 决策来源: phase-3-advanced.md §P3.2
class_name RtsGroupFormation


## 给定 unit_count, 返回 Array[Vector2] 长度 = unit_count, 每项是 unit i 相对 target_pos
## 的 offset (caller 把 target_pos + offset[i] 作为 unit i 的 nav target).
##
## 不变量:
##   - 返回数组长度 == unit_count
##   - 几何中心 = ZERO (sum(offset) / N ≈ ZERO; 末行居中后近似零)
##   - pairwise distance ≥ spacing (不重叠)
##   - 排列稳定 (同 unit_count → 同 offsets, 决定性安全)
##
## unit_count = 0 → 返回空数组. unit_count = 1 → [ZERO] (单 unit 直接抵达 target).
static func assign_offsets(unit_count: int, spacing: float = 30.0) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if unit_count <= 0:
		return result
	if unit_count == 1:
		result.append(Vector2.ZERO)
		return result

	var cols: int = int(ceil(sqrt(float(unit_count))))
	if cols < 1:
		cols = 1
	var rows: int = int(ceil(float(unit_count) / float(cols)))
	# 几何中心对齐: x_center 在 col 范围 [0, cols-1] 的中点 = (cols-1)/2
	var col_center: float = float(cols - 1) * 0.5
	var row_center: float = float(rows - 1) * 0.5

	# 末行可能不满 cols 个 — 末行 col 范围用 float 居中, 让末行几何中心仍 = 满行几何中心
	var full_rows: int = unit_count / cols
	var last_row_count: int = unit_count - full_rows * cols  # 0 = 末行恰好填满

	for i in unit_count:
		var row_idx: int = i / cols
		var col_idx: int = i % cols
		var col_pos: float = float(col_idx)
		# 末行不满: 加 float offset 让末行中心对齐 (cols-last)/2.0
		if last_row_count > 0 and row_idx == full_rows:
			col_pos += float(cols - last_row_count) * 0.5
		var x: float = (col_pos - col_center) * spacing
		var y: float = (float(row_idx) - row_center) * spacing
		result.append(Vector2(x, y))

	return result
