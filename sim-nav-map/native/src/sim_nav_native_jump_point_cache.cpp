#include "sim_nav_native_jump_point_cache.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void SimNavNativeJumpPointCache::_bind_methods() {
	ClassDB::bind_method(D_METHOD("reset", "map", "pass_mask"), &SimNavNativeJumpPointCache::reset);
	ClassDB::bind_method(D_METHOD("repair_for_map_dirty"), &SimNavNativeJumpPointCache::repair_for_map_dirty);
	ClassDB::bind_method(D_METHOD("invalidate_all"), &SimNavNativeJumpPointCache::invalidate_all);
	ClassDB::bind_method(D_METHOD("is_dirty"), &SimNavNativeJumpPointCache::is_dirty);
	ClassDB::bind_method(D_METHOD("jump_point", "start", "direction", "goal_cell"), &SimNavNativeJumpPointCache::jump_point);
	ClassDB::bind_method(D_METHOD("movement_line_clear", "from_world", "to_world"), &SimNavNativeJumpPointCache::movement_line_clear);
	ClassDB::bind_method(D_METHOD("segment_clear", "from_world", "to_world"), &SimNavNativeJumpPointCache::segment_clear);
	ClassDB::bind_method(D_METHOD("baked_grid"), &SimNavNativeJumpPointCache::baked_grid);
	ClassDB::bind_method(D_METHOD("ray_table_east"), &SimNavNativeJumpPointCache::ray_table_east);
	ClassDB::bind_method(D_METHOD("ray_table_west"), &SimNavNativeJumpPointCache::ray_table_west);
	ClassDB::bind_method(D_METHOD("ray_table_south"), &SimNavNativeJumpPointCache::ray_table_south);
	ClassDB::bind_method(D_METHOD("ray_table_north"), &SimNavNativeJumpPointCache::ray_table_north);
	ClassDB::bind_method(D_METHOD("tables_equal", "other"), &SimNavNativeJumpPointCache::tables_equal);
	ClassDB::bind_method(D_METHOD("repair_count"), &SimNavNativeJumpPointCache::repair_count);
	ClassDB::bind_method(D_METHOD("full_reset_count"), &SimNavNativeJumpPointCache::full_reset_count);
}

void SimNavNativeJumpPointCache::reset(const Ref<SimNavNativeMap> &p_map, int64_t p_pass_mask) {
	ERR_FAIL_COND(p_map.is_null());
	bound_map = p_map;
	tables.reset(p_map->core(), (int32_t)p_pass_mask);
}

void SimNavNativeJumpPointCache::repair_for_map_dirty() {
	ERR_FAIL_COND_MSG(bound_map.is_null(), "cache has no bound map (call reset first)");
	std::vector<simnav::Vector2i> dirty_cells;
	bound_map->core().collect_dirty_navcells(dirty_cells);
	tables.repair_dirty_cells(bound_map->core(), dirty_cells);
}

void SimNavNativeJumpPointCache::invalidate_all() {
	tables.invalidate_all();
}

bool SimNavNativeJumpPointCache::is_dirty() const {
	return tables.is_dirty();
}

Vector2i SimNavNativeJumpPointCache::jump_point(const Vector2i &p_start, const Vector2i &p_direction, const Vector2i &p_goal_cell) const {
	// Public-boundary guards: the core method indexes the tables raw (the C++
	// pathfinder guarantees its inputs); a script caller must not be able to
	// read out of bounds.
	ERR_FAIL_COND_V_MSG(tables.is_dirty() || tables.baked_grid().empty(), p_start, "cache not reset");
	ERR_FAIL_COND_V_MSG(
			p_start.x < 0 || p_start.y < 0 || p_start.x >= tables.width() || p_start.y >= tables.height(),
			p_start, "start out of bounds");
	const bool valid_direction = p_direction.x >= -1 && p_direction.x <= 1 &&
			p_direction.y >= -1 && p_direction.y <= 1 &&
			(p_direction.x != 0 || p_direction.y != 0);
	ERR_FAIL_COND_V_MSG(!valid_direction, p_start, "direction must be one of the 8 unit neighbors");
	return tables.jump_point(p_start, p_direction, p_goal_cell);
}

bool SimNavNativeJumpPointCache::movement_line_clear(const Vector2 &p_a, const Vector2 &p_b) const {
	return tables.movement_line_clear(p_a, p_b);
}

bool SimNavNativeJumpPointCache::segment_clear(const Vector2 &p_a, const Vector2 &p_b) const {
	return tables.segment_clear(p_a, p_b);
}

static PackedInt32Array _to_packed(const std::vector<int32_t> &p_data) {
	PackedInt32Array out;
	out.resize((int64_t)p_data.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < p_data.size(); i++) {
		w[i] = p_data[i];
	}
	return out;
}

PackedInt32Array SimNavNativeJumpPointCache::baked_grid() const {
	return _to_packed(tables.baked_grid());
}

PackedInt32Array SimNavNativeJumpPointCache::ray_table_east() const {
	return _to_packed(tables.ray_table_east());
}

PackedInt32Array SimNavNativeJumpPointCache::ray_table_west() const {
	return _to_packed(tables.ray_table_west());
}

PackedInt32Array SimNavNativeJumpPointCache::ray_table_south() const {
	return _to_packed(tables.ray_table_south());
}

PackedInt32Array SimNavNativeJumpPointCache::ray_table_north() const {
	return _to_packed(tables.ray_table_north());
}

bool SimNavNativeJumpPointCache::tables_equal(const Ref<SimNavNativeJumpPointCache> &p_other) const {
	if (p_other.is_null()) {
		return false;
	}
	return tables.tables_equal(p_other->core_tables());
}
