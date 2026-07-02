#include "sim_nav_native_map.h"

#include <climits>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

// Core tags live in the int32 domain; a truncated 64-bit script value must
// not alias another tag (0x100000001 silently becoming 1).

// While a background plan batch is in flight the worker reads the core map
// concurrently — every mutation entry point refuses until collect() runs.
#define SIMNAV_MAP_MUTATION_GUARD(m_ret) 	ERR_FAIL_COND_V_MSG(mutation_frozen, m_ret, "map is frozen while a background plan batch is in flight (collect first)")
#define SIMNAV_MAP_MUTATION_GUARD_VOID() 	ERR_FAIL_COND_MSG(mutation_frozen, "map is frozen while a background plan batch is in flight (collect first)")

static bool _tag_in_range(int64_t p_tag) {
	return p_tag > 0 && p_tag <= INT32_MAX;
}

using namespace godot;

void SimNavNativeMap::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "width", "height", "navcell_size", "origin", "navcells_per_tile"), &SimNavNativeMap::setup, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("register_passability_class", "name", "clearance", "affects_pathfinding", "terrain_mask"), &SimNavNativeMap::register_passability_class, DEFVAL(true), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_passability_mask", "name"), &SimNavNativeMap::get_passability_mask);
	ClassDB::bind_method(D_METHOD("max_clearance"), &SimNavNativeMap::max_clearance);
	ClassDB::bind_method(D_METHOD("set_bounds", "x0", "z0", "x1", "z1"), &SimNavNativeMap::set_bounds);
	ClassDB::bind_method(D_METHOD("is_inside_playable_bounds", "world_pos"), &SimNavNativeMap::is_inside_playable_bounds);
	ClassDB::bind_method(D_METHOD("get_terrain_tile_data", "tile"), &SimNavNativeMap::get_terrain_tile_data);
	ClassDB::bind_method(D_METHOD("set_terrain_tile_data", "tile", "value"), &SimNavNativeMap::set_terrain_tile_data);
	ClassDB::bind_method(D_METHOD("get_navcell_terrain_data", "coord"), &SimNavNativeMap::get_navcell_terrain_data);
	ClassDB::bind_method(D_METHOD("rebuild_terrain_passability"), &SimNavNativeMap::rebuild_terrain_passability);
	ClassDB::bind_method(D_METHOD("add_static_obstruction", "entity_id", "center", "width", "height", "rotation_rad", "flags", "control_group", "control_group_2"), &SimNavNativeMap::add_static_obstruction, DEFVAL(String()), DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("remove_obstruction", "tag"), &SimNavNativeMap::remove_obstruction);
	ClassDB::bind_method(D_METHOD("move_obstruction", "tag", "center", "rotation_rad"), &SimNavNativeMap::move_obstruction, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("mark_obstruction_shape_dirty", "tag"), &SimNavNativeMap::mark_obstruction_shape_dirty);
	ClassDB::bind_method(D_METHOD("rebuild_dirty"), &SimNavNativeMap::rebuild_dirty);
	ClassDB::bind_method(D_METHOD("rasterize_dirty_obstructions"), &SimNavNativeMap::rasterize_dirty_obstructions);
	ClassDB::bind_method(D_METHOD("navcell_center_world", "coord"), &SimNavNativeMap::navcell_center_world);
	ClassDB::bind_method(D_METHOD("world_to_navcell", "world_pos"), &SimNavNativeMap::world_to_navcell);
	ClassDB::bind_method(D_METHOD("is_valid_navcell", "coord"), &SimNavNativeMap::is_valid_navcell);
	ClassDB::bind_method(D_METHOD("is_passable_navcell", "coord", "passability_mask"), &SimNavNativeMap::is_passable_navcell);
	ClassDB::bind_method(D_METHOD("get_navcell_data", "coord"), &SimNavNativeMap::get_navcell_data);
	ClassDB::bind_method(D_METHOD("set_navcell_data", "coord", "value"), &SimNavNativeMap::set_navcell_data);
	ClassDB::bind_method(D_METHOD("or_navcell_data", "coord", "mask"), &SimNavNativeMap::or_navcell_data);
	ClassDB::bind_method(D_METHOD("and_navcell_data", "coord", "inverse_mask"), &SimNavNativeMap::and_navcell_data);
	ClassDB::bind_method(D_METHOD("mark_dirty_navcell", "coord"), &SimNavNativeMap::mark_dirty_navcell);
	ClassDB::bind_method(D_METHOD("is_dirty_navcell", "coord"), &SimNavNativeMap::is_dirty_navcell);
	ClassDB::bind_method(D_METHOD("has_dirty_navcells"), &SimNavNativeMap::has_dirty_navcells);
	ClassDB::bind_method(D_METHOD("has_dirty_obstruction_navcells"), &SimNavNativeMap::has_dirty_obstruction_navcells);
	ClassDB::bind_method(D_METHOD("clear_dirty_navcells"), &SimNavNativeMap::clear_dirty_navcells);
	ClassDB::bind_method(D_METHOD("clear_dirty_obstruction_navcells"), &SimNavNativeMap::clear_dirty_obstruction_navcells);
	ClassDB::bind_method(D_METHOD("dirty_navcell_revision"), &SimNavNativeMap::dirty_navcell_revision);
	ClassDB::bind_method(D_METHOD("collect_dirty_navcells_packed"), &SimNavNativeMap::collect_dirty_navcells_packed);
	ClassDB::bind_method(D_METHOD("collect_dirty_obstruction_navcells_packed"), &SimNavNativeMap::collect_dirty_obstruction_navcells_packed);
	ClassDB::bind_method(D_METHOD("composed_navcell_data"), &SimNavNativeMap::composed_navcell_data);
	ClassDB::bind_method(D_METHOD("get_width"), &SimNavNativeMap::get_width);
	ClassDB::bind_method(D_METHOD("get_height"), &SimNavNativeMap::get_height);
	ClassDB::bind_method(D_METHOD("get_navcell_size"), &SimNavNativeMap::get_navcell_size);
	ClassDB::bind_method(D_METHOD("get_origin"), &SimNavNativeMap::get_origin);
	ClassDB::bind_method(D_METHOD("get_navcells_per_tile"), &SimNavNativeMap::get_navcells_per_tile);
}

void SimNavNativeMap::setup(int p_width, int p_height, double p_navcell_size, const Vector2 &p_origin, int p_navcells_per_tile) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	ERR_FAIL_COND_MSG(p_width < 0 || p_height < 0, "map dimensions must be non-negative");
	ERR_FAIL_COND_MSG(p_navcell_size <= 0.0, "navcell_size must be positive");
	ERR_FAIL_COND_MSG((int64_t)p_width * (int64_t)p_height > (int64_t)INT32_MAX, "map cell count overflows the int32 domain");
	core_map.setup(p_width, p_height, p_navcell_size, p_origin, p_navcells_per_tile);
}

int64_t SimNavNativeMap::register_passability_class(const String &p_name, double p_clearance, bool p_affects_pathfinding, int64_t p_terrain_mask) {
	SIMNAV_MAP_MUTATION_GUARD(0);
	return core_map.register_passability_class(p_name, p_clearance, p_affects_pathfinding, (int32_t)p_terrain_mask);
}

int64_t SimNavNativeMap::get_passability_mask(const String &p_name) const {
	return core_map.get_passability_mask(p_name);
}

double SimNavNativeMap::max_clearance() const {
	return core_map.max_clearance();
}

void SimNavNativeMap::set_bounds(double p_x0, double p_z0, double p_x1, double p_z1) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.set_bounds(p_x0, p_z0, p_x1, p_z1);
}

bool SimNavNativeMap::is_inside_playable_bounds(const Vector2 &p_world) const {
	return core_map.is_inside_playable_bounds(p_world);
}

int64_t SimNavNativeMap::get_terrain_tile_data(const Vector2i &p_tile) const {
	return core_map.get_terrain_tile_data(p_tile);
}

void SimNavNativeMap::set_terrain_tile_data(const Vector2i &p_tile, int64_t p_value) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.set_terrain_tile_data(p_tile, (int32_t)p_value);
}

int64_t SimNavNativeMap::get_navcell_terrain_data(const Vector2i &p_coord) const {
	return core_map.get_navcell_terrain_data(p_coord);
}

int64_t SimNavNativeMap::rebuild_terrain_passability() {
	SIMNAV_MAP_MUTATION_GUARD(0);
	return core_map.rebuild_terrain_passability();
}

int64_t SimNavNativeMap::add_static_obstruction(const String &p_entity_id, const Vector2 &p_center, double p_width, double p_height, double p_rotation_rad, int64_t p_flags, const String &p_control_group, const String &p_control_group_2) {
	SIMNAV_MAP_MUTATION_GUARD(0);
	simnav::StaticShape shape;
	shape.entity_id = p_entity_id;
	shape.center = p_center;
	shape.width = p_width;
	shape.height = p_height;
	shape.rotation_rad = p_rotation_rad;
	shape.flags = (int32_t)p_flags;
	shape.control_group = p_control_group;
	shape.control_group_2 = p_control_group_2;
	return core_map.add_static_obstruction(shape);
}

bool SimNavNativeMap::remove_obstruction(int64_t p_tag) {
	SIMNAV_MAP_MUTATION_GUARD(false);
	if (!_tag_in_range(p_tag)) {
		return false;
	}
	return core_map.remove_obstruction((int32_t)p_tag);
}

bool SimNavNativeMap::move_obstruction(int64_t p_tag, const Vector2 &p_center, double p_rotation_rad) {
	SIMNAV_MAP_MUTATION_GUARD(false);
	if (!_tag_in_range(p_tag)) {
		return false;
	}
	return core_map.move_obstruction((int32_t)p_tag, p_center, p_rotation_rad);
}

void SimNavNativeMap::mark_obstruction_shape_dirty(int64_t p_tag) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	if (!_tag_in_range(p_tag)) {
		return;
	}
	core_map.mark_obstruction_shape_dirty((int32_t)p_tag);
}

void SimNavNativeMap::rebuild_dirty() {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.rebuild_dirty();
}

int64_t SimNavNativeMap::rasterize_dirty_obstructions() {
	SIMNAV_MAP_MUTATION_GUARD(0);
	return core_map.rasterize_dirty_obstructions();
}

Vector2 SimNavNativeMap::navcell_center_world(const Vector2i &p_coord) const {
	return core_map.navcell_center_world(p_coord);
}

Vector2i SimNavNativeMap::world_to_navcell(const Vector2 &p_world) const {
	return core_map.world_to_navcell(p_world);
}

bool SimNavNativeMap::is_valid_navcell(const Vector2i &p_coord) const {
	return core_map.is_valid_navcell(p_coord);
}

bool SimNavNativeMap::is_passable_navcell(const Vector2i &p_coord, int64_t p_pass_mask) const {
	return core_map.is_passable_navcell(p_coord, (int32_t)p_pass_mask);
}

int64_t SimNavNativeMap::get_navcell_data(const Vector2i &p_coord) const {
	return core_map.get_navcell_data(p_coord);
}

void SimNavNativeMap::set_navcell_data(const Vector2i &p_coord, int64_t p_value) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.set_navcell_data(p_coord, (int32_t)p_value);
}

void SimNavNativeMap::or_navcell_data(const Vector2i &p_coord, int64_t p_mask) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.or_navcell_data(p_coord, (int32_t)p_mask);
}

void SimNavNativeMap::and_navcell_data(const Vector2i &p_coord, int64_t p_inverse_mask) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.and_navcell_data(p_coord, (int32_t)p_inverse_mask);
}

void SimNavNativeMap::mark_dirty_navcell(const Vector2i &p_coord) {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.mark_dirty_navcell(p_coord);
}

bool SimNavNativeMap::is_dirty_navcell(const Vector2i &p_coord) const {
	return core_map.is_dirty_navcell(p_coord);
}

bool SimNavNativeMap::has_dirty_navcells() const {
	return core_map.has_dirty_navcells();
}

bool SimNavNativeMap::has_dirty_obstruction_navcells() const {
	return core_map.has_dirty_obstruction_navcells();
}

void SimNavNativeMap::clear_dirty_navcells() {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.clear_dirty_navcells();
}

void SimNavNativeMap::clear_dirty_obstruction_navcells() {
	SIMNAV_MAP_MUTATION_GUARD_VOID();
	core_map.clear_dirty_obstruction_navcells();
}

int64_t SimNavNativeMap::dirty_navcell_revision() const {
	return core_map.dirty_navcell_revision();
}

static PackedInt32Array _cells_to_packed(const std::vector<Vector2i> &p_cells) {
	PackedInt32Array out;
	out.resize((int64_t)p_cells.size() * 2);
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < p_cells.size(); i++) {
		w[i * 2] = p_cells[i].x;
		w[i * 2 + 1] = p_cells[i].y;
	}
	return out;
}

PackedInt32Array SimNavNativeMap::collect_dirty_navcells_packed() const {
	std::vector<Vector2i> cells;
	core_map.collect_dirty_navcells(cells);
	return _cells_to_packed(cells);
}

PackedInt32Array SimNavNativeMap::collect_dirty_obstruction_navcells_packed() const {
	std::vector<Vector2i> cells;
	core_map.collect_dirty_obstruction_navcells(cells);
	return _cells_to_packed(cells);
}

PackedInt32Array SimNavNativeMap::composed_navcell_data() const {
	std::vector<int32_t> composed;
	core_map.composed_navcell_data(composed);
	PackedInt32Array out;
	out.resize((int64_t)composed.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < composed.size(); i++) {
		w[i] = composed[i];
	}
	return out;
}
