#include "sim_nav_jump_tables.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <set>

namespace simnav {

void JumpTables::reset(const CoreMap &p_map, int32_t p_pass_mask) {
	pass_mask = p_pass_mask;
	dirty = false;
	_bake_grid(p_map);
	_build_ray_tables();
	full_reset_count += 1;
	repaired_dirty_revision = p_map.dirty_navcell_revision();
}

void JumpTables::_bake_grid(const CoreMap &p_map) {
	baked_width = p_map.width;
	baked_height = p_map.height;
	origin = p_map.origin;
	cell_size = p_map.navcell_size;
	p_map.composed_navcell_data(baked);
}

void JumpTables::repair_dirty_cells(const CoreMap &p_map, const std::vector<Vector2i> &p_dirty_cells) {
	if (dirty || baked.empty()) {
		reset(p_map, pass_mask);
		return;
	}
	if (p_dirty_cells.empty()) {
		return;
	}
	int w = baked_width;
	int h = baked_height;
	std::set<int> rows;
	std::set<int> cols;
	for (const Vector2i &cell : p_dirty_cells) {
		if (cell.x < 0 || cell.y < 0 || cell.x >= w || cell.y >= h) {
			continue;
		}
		baked[(size_t)cell.y * w + cell.x] = p_map.get_navcell_data(cell);
		for (int dy = -1; dy <= 1; dy++) {
			int y = cell.y + dy;
			if (y >= 0 && y < h) {
				rows.insert(y);
			}
		}
		for (int dx = -1; dx <= 1; dx++) {
			int x = cell.x + dx;
			if (x >= 0 && x < w) {
				cols.insert(x);
			}
		}
	}
	if (rows.empty()) {
		return;
	}
	if ((int64_t)rows.size() * 2 * w + (int64_t)cols.size() * 2 * h > (int64_t)2 * w * h) {
		reset(p_map, pass_mask);
		return;
	}
	for (int y : rows) {
		_rebuild_ray_row_east(y);
		_rebuild_ray_row_west(y);
	}
	for (int x : cols) {
		_rebuild_ray_col_south(x);
		_rebuild_ray_col_north(x);
	}
	repair_count += 1;
}

bool JumpTables::tables_equal(const JumpTables &p_other) const {
	return baked == p_other.baked &&
			ray_east == p_other.ray_east &&
			ray_west == p_other.ray_west &&
			ray_south == p_other.ray_south &&
			ray_north == p_other.ray_north;
}

void JumpTables::_build_ray_tables() {
	size_t size = (size_t)baked_width * baked_height;
	ray_east.assign(size, 0);
	ray_west.assign(size, 0);
	ray_south.assign(size, 0);
	ray_north.assign(size, 0);
	if (size == 0) {
		return;
	}
	for (int y = 0; y < baked_height; y++) {
		_rebuild_ray_row_east(y);
		_rebuild_ray_row_west(y);
	}
	for (int x = 0; x < baked_width; x++) {
		_rebuild_ray_col_south(x);
		_rebuild_ray_col_north(x);
	}
}

void JumpTables::_rebuild_ray_row_east(int p_y) {
	int w = baked_width;
	int h = baked_height;
	int32_t mask = pass_mask;
	int row = p_y * w;
	for (int step = 0; step < w; step++) {
		int x = w - 1 - step;
		int i = row + x;
		if ((baked[(size_t)i] & mask) != 0) {
			ray_east[(size_t)i] = RAY_IMPASSABLE;
			continue;
		}
		if (x + 1 >= w) {
			ray_east[(size_t)i] = RAY_BOUNDARY;
			continue;
		}
		int ni = i + 1;
		if ((baked[(size_t)ni] & mask) != 0) {
			ray_east[(size_t)i] = (1 << 2) | RAY_OBSTRUCTION;
			continue;
		}
		bool forced = false;
		if (p_y > 0) {
			// blocked at (x, y - 1) with (x + 1, y - 1) open
			if ((baked[(size_t)(i - w)] & mask) != 0 && (baked[(size_t)(ni - w)] & mask) == 0) {
				forced = true;
			}
		}
		if (!forced && p_y + 1 < h) {
			if ((baked[(size_t)(i + w)] & mask) != 0 && (baked[(size_t)(ni + w)] & mask) == 0) {
				forced = true;
			}
		}
		if (forced) {
			ray_east[(size_t)i] = (1 << 2) | RAY_JUMP;
		} else {
			ray_east[(size_t)i] = ray_east[(size_t)ni] + 4;
		}
	}
}

void JumpTables::_rebuild_ray_row_west(int p_y) {
	int w = baked_width;
	int h = baked_height;
	int32_t mask = pass_mask;
	int row = p_y * w;
	for (int x = 0; x < w; x++) {
		int i = row + x;
		if ((baked[(size_t)i] & mask) != 0) {
			ray_west[(size_t)i] = RAY_IMPASSABLE;
			continue;
		}
		if (x - 1 < 0) {
			ray_west[(size_t)i] = RAY_BOUNDARY;
			continue;
		}
		int ni = i - 1;
		if ((baked[(size_t)ni] & mask) != 0) {
			ray_west[(size_t)i] = (1 << 2) | RAY_OBSTRUCTION;
			continue;
		}
		bool forced = false;
		if (p_y > 0) {
			// blocked at (x, y - 1) with (x - 1, y - 1) open
			if ((baked[(size_t)(i - w)] & mask) != 0 && (baked[(size_t)(ni - w)] & mask) == 0) {
				forced = true;
			}
		}
		if (!forced && p_y + 1 < h) {
			if ((baked[(size_t)(i + w)] & mask) != 0 && (baked[(size_t)(ni + w)] & mask) == 0) {
				forced = true;
			}
		}
		if (forced) {
			ray_west[(size_t)i] = (1 << 2) | RAY_JUMP;
		} else {
			ray_west[(size_t)i] = ray_west[(size_t)ni] + 4;
		}
	}
}

void JumpTables::_rebuild_ray_col_south(int p_x) {
	int w = baked_width;
	int h = baked_height;
	int32_t mask = pass_mask;
	for (int step = 0; step < h; step++) {
		int y = h - 1 - step;
		int i = y * w + p_x;
		if ((baked[(size_t)i] & mask) != 0) {
			ray_south[(size_t)i] = RAY_IMPASSABLE;
			continue;
		}
		if (y + 1 >= h) {
			ray_south[(size_t)i] = RAY_BOUNDARY;
			continue;
		}
		int ni = i + w;
		if ((baked[(size_t)ni] & mask) != 0) {
			ray_south[(size_t)i] = (1 << 2) | RAY_OBSTRUCTION;
			continue;
		}
		bool forced = false;
		if (p_x > 0) {
			// blocked at (x - 1, y) with (x - 1, y + 1) open
			if ((baked[(size_t)(i - 1)] & mask) != 0 && (baked[(size_t)(ni - 1)] & mask) == 0) {
				forced = true;
			}
		}
		if (!forced && p_x + 1 < w) {
			if ((baked[(size_t)(i + 1)] & mask) != 0 && (baked[(size_t)(ni + 1)] & mask) == 0) {
				forced = true;
			}
		}
		if (forced) {
			ray_south[(size_t)i] = (1 << 2) | RAY_JUMP;
		} else {
			ray_south[(size_t)i] = ray_south[(size_t)ni] + 4;
		}
	}
}

void JumpTables::_rebuild_ray_col_north(int p_x) {
	int w = baked_width;
	int h = baked_height;
	int32_t mask = pass_mask;
	for (int y = 0; y < h; y++) {
		int i = y * w + p_x;
		if ((baked[(size_t)i] & mask) != 0) {
			ray_north[(size_t)i] = RAY_IMPASSABLE;
			continue;
		}
		if (y - 1 < 0) {
			ray_north[(size_t)i] = RAY_BOUNDARY;
			continue;
		}
		int ni = i - w;
		if ((baked[(size_t)ni] & mask) != 0) {
			ray_north[(size_t)i] = (1 << 2) | RAY_OBSTRUCTION;
			continue;
		}
		bool forced = false;
		if (p_x > 0) {
			// blocked at (x - 1, y) with (x - 1, y - 1) open
			if ((baked[(size_t)(i - 1)] & mask) != 0 && (baked[(size_t)(ni - 1)] & mask) == 0) {
				forced = true;
			}
		}
		if (!forced && p_x + 1 < w) {
			if ((baked[(size_t)(i + 1)] & mask) != 0 && (baked[(size_t)(ni + 1)] & mask) == 0) {
				forced = true;
			}
		}
		if (forced) {
			ray_north[(size_t)i] = (1 << 2) | RAY_JUMP;
		} else {
			ray_north[(size_t)i] = ray_north[(size_t)ni] + 4;
		}
	}
}

const std::vector<int32_t> &JumpTables::_ray_table_for(const Vector2i &p_direction) const {
	if (p_direction.x == 1) {
		return ray_east;
	}
	if (p_direction.x == -1) {
		return ray_west;
	}
	if (p_direction.y == 1) {
		return ray_south;
	}
	return ray_north;
}

Vector2i JumpTables::jump_point(const Vector2i &p_start, const Vector2i &p_direction, const Vector2i &p_goal_cell) const {
	if (p_direction.x != 0 && p_direction.y != 0) {
		return _jump_diagonal_point(p_start, p_direction, p_goal_cell);
	}
	int32_t entry = _ray_table_for(p_direction)[(size_t)p_start.y * baked_width + p_start.x];
	int32_t kind = entry & 3;
	int32_t steps = entry >> 2;
	int32_t max_steps = kind == RAY_OBSTRUCTION ? steps - 1 : steps;
	int32_t step_count = (p_goal_cell.x - p_start.x) * p_direction.x + (p_goal_cell.y - p_start.y) * p_direction.y;
	if (step_count >= 1 && step_count <= max_steps &&
			p_start.x + p_direction.x * step_count == p_goal_cell.x &&
			p_start.y + p_direction.y * step_count == p_goal_cell.y) {
		return p_goal_cell;
	}
	if (kind == RAY_JUMP) {
		return Vector2i(p_start.x + p_direction.x * steps, p_start.y + p_direction.y * steps);
	}
	return p_start;
}

Vector2i JumpTables::_jump_diagonal_point(const Vector2i &p_start, const Vector2i &p_direction, const Vector2i &p_goal_cell) const {
	int w = baked_width;
	int h = baked_height;
	int32_t mask = pass_mask;
	int dx = p_direction.x;
	int dy = p_direction.y;
	int gx = p_goal_cell.x;
	int gy = p_goal_cell.y;
	const std::vector<int32_t> &h_table = dx == 1 ? ray_east : ray_west;
	const std::vector<int32_t> &v_table = dy == 1 ? ray_south : ray_north;
	int cx = p_start.x;
	int cy = p_start.y;
	while (true) {
		int nx = cx + dx;
		int ny = cy + dy;
		// _can_step: to-cell plus both cardinal-adjacent cells must be passable
		// (no corner cutting).
		if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
			return p_start;
		}
		if ((baked[(size_t)ny * w + nx] & mask) != 0) {
			return p_start;
		}
		if ((baked[(size_t)cy * w + nx] & mask) != 0) {
			return p_start;
		}
		if ((baked[(size_t)ny * w + cx] & mask) != 0) {
			return p_start;
		}
		if (nx == gx && ny == gy) {
			return Vector2i(nx, ny);
		}
		// Diagonal jump point: either cardinal ray from the advanced cell sees
		// a forced jump or the goal within its passable run.
		int32_t entry = h_table[(size_t)ny * w + nx];
		int32_t kind = entry & 3;
		if (kind == RAY_JUMP) {
			return Vector2i(nx, ny);
		}
		int32_t step_count = (gx - nx) * dx;
		if (gy == ny && step_count >= 1 &&
				step_count <= (entry >> 2) - (kind == RAY_OBSTRUCTION ? 1 : 0)) {
			return Vector2i(nx, ny);
		}
		entry = v_table[(size_t)ny * w + nx];
		kind = entry & 3;
		if (kind == RAY_JUMP) {
			return Vector2i(nx, ny);
		}
		step_count = (gy - ny) * dy;
		if (gx == nx && step_count >= 1 &&
				step_count <= (entry >> 2) - (kind == RAY_OBSTRUCTION ? 1 : 0)) {
			return Vector2i(nx, ny);
		}
		cx = nx;
		cy = ny;
	}
}

bool JumpTables::movement_line_clear(const Vector2 &p_a, const Vector2 &p_b) const {
	// Twin: SimNavJumpPointCache.movement_line_clear — the 0 A.D. escape-rule
	// raster walk. All scalar math in double, exactly like the GDScript.
	constexpr double INF = std::numeric_limits<double>::infinity();
	int w = baked_width;
	int h = baked_height;
	int32_t mask = pass_mask;
	double cs = cell_size;
	int i0 = (int)std::floor(((double)p_a.x - (double)origin.x) / cs);
	int j0 = (int)std::floor(((double)p_a.y - (double)origin.y) / cs);
	int i1 = (int)std::floor(((double)p_b.x - (double)origin.x) / cs);
	int j1 = (int)std::floor(((double)p_b.y - (double)origin.y) / cs);
	if (i0 < 0 || j0 < 0 || i0 >= w || j0 >= h) {
		return false;
	}
	bool on_impassable = (baked[(size_t)j0 * w + i0] & mask) != 0;
	if (i0 == i1 && j0 == j1) {
		return true;
	}
	double dx = (double)p_b.x - (double)p_a.x;
	double dy = (double)p_b.y - (double)p_a.y;
	int step_i = 0;
	int step_j = 0;
	double t_max_x = INF;
	double t_max_y = INF;
	double delta_t_x = INF;
	double delta_t_y = INF;
	if (dx > 0.0) {
		step_i = 1;
		t_max_x = ((double)origin.x + (double)(i0 + 1) * cs - (double)p_a.x) / dx;
		delta_t_x = cs / dx;
	} else if (dx < 0.0) {
		step_i = -1;
		t_max_x = ((double)origin.x + (double)i0 * cs - (double)p_a.x) / dx;
		delta_t_x = -cs / dx;
	}
	if (dy > 0.0) {
		step_j = 1;
		t_max_y = ((double)origin.y + (double)(j0 + 1) * cs - (double)p_a.y) / dy;
		delta_t_y = cs / dy;
	} else if (dy < 0.0) {
		step_j = -1;
		t_max_y = ((double)origin.y + (double)j0 * cs - (double)p_a.y) / dy;
		delta_t_y = -cs / dy;
	}
	int max_steps = std::abs(i1 - i0) + std::abs(j1 - j0) + 4;
	int ci = i0;
	int cj = j0;
	while (ci != i1 || cj != j1) {
		if (max_steps <= 0) {
			return false;
		}
		max_steps -= 1;
		if (ci == i1) {
			cj += step_j;
			t_max_y += delta_t_y;
		} else if (cj == j1) {
			ci += step_i;
			t_max_x += delta_t_x;
		} else if (t_max_x < t_max_y) {
			ci += step_i;
			t_max_x += delta_t_x;
		} else {
			cj += step_j;
			t_max_y += delta_t_y;
		}
		if (ci < 0 || cj < 0 || ci >= w || cj >= h) {
			return false;
		}
		if ((baked[(size_t)cj * w + ci] & mask) == 0) {
			on_impassable = false;
		} else if (!on_impassable) {
			return false;
		}
	}
	return true;
}

bool JumpTables::segment_clear(const Vector2 &p_a, const Vector2 &p_b) const {
	// Twin: SimNavJumpPointCache.segment_clear — Amanatides-Woo walk with the
	// axis-convergence guard; start cell must already be passable.
	constexpr double INF = std::numeric_limits<double>::infinity();
	int w = baked_width;
	int h = baked_height;
	int32_t mask = pass_mask;
	double cs = cell_size;
	int i0 = (int)std::floor(((double)p_a.x - (double)origin.x) / cs);
	int j0 = (int)std::floor(((double)p_a.y - (double)origin.y) / cs);
	int i1 = (int)std::floor(((double)p_b.x - (double)origin.x) / cs);
	int j1 = (int)std::floor(((double)p_b.y - (double)origin.y) / cs);
	if (i0 < 0 || j0 < 0 || i0 >= w || j0 >= h) {
		return false;
	}
	if ((baked[(size_t)j0 * w + i0] & mask) != 0) {
		return false;
	}
	if (i0 == i1 && j0 == j1) {
		return true;
	}
	double dx = (double)p_b.x - (double)p_a.x;
	double dy = (double)p_b.y - (double)p_a.y;
	int step_i = 0;
	int step_j = 0;
	double t_max_x = INF;
	double t_max_y = INF;
	double delta_t_x = INF;
	double delta_t_y = INF;
	if (dx > 0.0) {
		step_i = 1;
		t_max_x = ((double)origin.x + (double)(i0 + 1) * cs - (double)p_a.x) / dx;
		delta_t_x = cs / dx;
	} else if (dx < 0.0) {
		step_i = -1;
		t_max_x = ((double)origin.x + (double)i0 * cs - (double)p_a.x) / dx;
		delta_t_x = -cs / dx;
	}
	if (dy > 0.0) {
		step_j = 1;
		t_max_y = ((double)origin.y + (double)(j0 + 1) * cs - (double)p_a.y) / dy;
		delta_t_y = cs / dy;
	} else if (dy < 0.0) {
		step_j = -1;
		t_max_y = ((double)origin.y + (double)j0 * cs - (double)p_a.y) / dy;
		delta_t_y = -cs / dy;
	}
	int i = i0;
	int j = j0;
	int max_steps = std::abs(i1 - i0) + std::abs(j1 - j0) + 4;
	while (i != i1 || j != j1) {
		if (max_steps <= 0) {
			return false;
		}
		max_steps -= 1;
		if (i == i1) {
			j += step_j;
			t_max_y += delta_t_y;
		} else if (j == j1) {
			i += step_i;
			t_max_x += delta_t_x;
		} else if (t_max_x < t_max_y) {
			i += step_i;
			t_max_x += delta_t_x;
		} else {
			j += step_j;
			t_max_y += delta_t_y;
		}
		if (i < 0 || j < 0 || i >= w || j >= h) {
			return false;
		}
		if ((baked[(size_t)j * w + i] & mask) != 0) {
			return false;
		}
	}
	return true;
}

} // namespace simnav
