#pragma once

// Pure-C++ twin of pathfinding/sim_nav_jump_point_cache.gd: JPS+ cardinal
// ray tables over a baked passability grid, with the incremental band repair
// and the three hot queries (table jump dispatch for POINT goals, the
// escape-rule movement raster walk, and the plain segment walk).
//
// The goal-aware find() path (non-POINT goals, SimNavJumpPointHit DTO) is an
// M3 item — it needs the PathGoal port and rides on top of these tables.

#include <cstdint>
#include <vector>

#include "sim_nav_core_map.h"

namespace simnav {

class JumpTables {
public:
	// Ray table entry: (steps << 2) | kind. Twin constants of the GDScript.
	static constexpr int32_t RAY_JUMP = 0;
	static constexpr int32_t RAY_OBSTRUCTION = 1;
	static constexpr int32_t RAY_BOUNDARY = 2;
	static constexpr int32_t RAY_IMPASSABLE = 3;

	int64_t repair_count = 0;
	int64_t full_reset_count = 0;
	int64_t repaired_dirty_revision = -1;

	void reset(const CoreMap &p_map, int32_t p_pass_mask);
	void repair_dirty_cells(const CoreMap &p_map, const std::vector<Vector2i> &p_dirty_cells);
	void invalidate_all() { dirty = true; }
	bool is_dirty() const { return dirty; }
	int32_t pass_mask_value() const { return pass_mask; }
	int width() const { return baked_width; }
	int height() const { return baked_height; }

	Vector2i jump_point(const Vector2i &p_start, const Vector2i &p_direction, const Vector2i &p_goal_cell) const;
	bool movement_line_clear(const Vector2 &p_a, const Vector2 &p_b) const;
	bool segment_clear(const Vector2 &p_a, const Vector2 &p_b) const;

	// Weld/test support (native A/B smokes compare these byte-wise).
	const std::vector<int32_t> &baked_grid() const { return baked; }
	const std::vector<int32_t> &ray_table_east() const { return ray_east; }
	const std::vector<int32_t> &ray_table_west() const { return ray_west; }
	const std::vector<int32_t> &ray_table_south() const { return ray_south; }
	const std::vector<int32_t> &ray_table_north() const { return ray_north; }
	bool tables_equal(const JumpTables &p_other) const;

private:
	int32_t pass_mask = 0;
	bool dirty = true;
	std::vector<int32_t> baked;
	int baked_width = 0;
	int baked_height = 0;
	Vector2 origin;
	double cell_size = 1.0;
	std::vector<int32_t> ray_east;
	std::vector<int32_t> ray_west;
	std::vector<int32_t> ray_south;
	std::vector<int32_t> ray_north;

	void _bake_grid(const CoreMap &p_map);
	void _build_ray_tables();
	void _rebuild_ray_row_east(int p_y);
	void _rebuild_ray_row_west(int p_y);
	void _rebuild_ray_col_south(int p_x);
	void _rebuild_ray_col_north(int p_x);
	Vector2i _jump_diagonal_point(const Vector2i &p_start, const Vector2i &p_direction, const Vector2i &p_goal_cell) const;
	const std::vector<int32_t> &_ray_table_for(const Vector2i &p_direction) const;
};

} // namespace simnav
