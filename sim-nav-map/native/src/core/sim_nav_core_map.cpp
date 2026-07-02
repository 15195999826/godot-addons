#include "sim_nav_core_map.h"

#include <algorithm>
#include <cmath>
#include <unordered_set>

#include <godot_cpp/core/error_macros.hpp>

namespace simnav {

using godot::real_t;

// Twin: SimNavObstructionFlags.BLOCK_PATHFINDING (core/sim_nav_obstruction_flags.gd).
static constexpr int32_t FLAG_BLOCK_PATHFINDING = 1 << 3;

// ── StaticShape ──────────────────────────────────────────────────────────────

bool StaticShape::contains_point_with_clearance(const Vector2 &p_point, double p_clearance) const {
	// Twin: SimNavObstructionShapeStatic.contains_point_with_clearance.
	// delta and the axes are float32 Vector2s (cos/sin computed in double,
	// narrowed by the Vector2 constructor); dot runs in float32; the final
	// comparison is double, exactly like the GDScript expression.
	Vector2 delta = p_point - center;
	Vector2 u((real_t)std::cos(rotation_rad), (real_t)std::sin(rotation_rad));
	Vector2 v((real_t)-std::sin(rotation_rad), (real_t)std::cos(rotation_rad));
	double local_x = (double)delta.dot(u);
	double local_y = (double)delta.dot(v);
	return std::abs(local_x) <= width * 0.5 + p_clearance && std::abs(local_y) <= height * 0.5 + p_clearance;
}

// ── SpatialIndex ─────────────────────────────────────────────────────────────

void SpatialIndex::setup(double p_cell_size) {
	cell_size = std::max(1.0, p_cell_size);
	clear();
}

void SpatialIndex::clear() {
	cells.clear();
	bounds_by_tag.clear();
}

uint64_t SpatialIndex::_cell_key(int32_t p_x, int32_t p_y) {
	// Unsigned packing: left-shifting a negative y is UB, and negative spatial
	// cells are legal (shapes near/over the map edge).
	return ((uint64_t)(uint32_t)p_y << 32) | (uint32_t)p_x;
}

Rect2 SpatialIndex::_make_rect(const Vector2 &p_min, const Vector2 &p_max) const {
	double left = std::min((double)p_min.x, (double)p_max.x);
	double top = std::min((double)p_min.y, (double)p_max.y);
	double right = std::max((double)p_min.x, (double)p_max.x);
	double bottom = std::max((double)p_min.y, (double)p_max.y);
	return Rect2(Vector2((real_t)left, (real_t)top), Vector2((real_t)(right - left), (real_t)(bottom - top)));
}

void SpatialIndex::_cell_range(const Rect2 &p_rect, int32_t &r_min_x, int32_t &r_min_y, int32_t &r_max_x, int32_t &r_max_y) const {
	// Twin: _world_to_cell — GDScript floorf is the double-precision floor.
	r_min_x = (int32_t)std::floor((double)p_rect.position.x / cell_size);
	r_min_y = (int32_t)std::floor((double)p_rect.position.y / cell_size);
	Vector2 end = p_rect.position + p_rect.size;
	r_max_x = (int32_t)std::floor((double)end.x / cell_size);
	r_max_y = (int32_t)std::floor((double)end.y / cell_size);
}

void SpatialIndex::add(int32_t p_tag, const Vector2 &p_min, const Vector2 &p_max) {
	if (p_tag <= 0) {
		return;
	}
	if (bounds_by_tag.count(p_tag)) {
		remove(p_tag);
	}
	Rect2 rect = _make_rect(p_min, p_max);
	bounds_by_tag[p_tag] = rect;
	int32_t min_x, min_y, max_x, max_y;
	_cell_range(rect, min_x, min_y, max_x, max_y);
	for (int32_t y = min_y; y <= max_y; y++) {
		for (int32_t x = min_x; x <= max_x; x++) {
			std::vector<int32_t> &bucket = cells[_cell_key(x, y)];
			auto pos = std::lower_bound(bucket.begin(), bucket.end(), p_tag);
			if (pos == bucket.end() || *pos != p_tag) {
				bucket.insert(pos, p_tag);
			}
		}
	}
}

bool SpatialIndex::remove(int32_t p_tag) {
	auto found = bounds_by_tag.find(p_tag);
	if (found == bounds_by_tag.end()) {
		return false;
	}
	Rect2 rect = found->second;
	int32_t min_x, min_y, max_x, max_y;
	_cell_range(rect, min_x, min_y, max_x, max_y);
	for (int32_t y = min_y; y <= max_y; y++) {
		for (int32_t x = min_x; x <= max_x; x++) {
			auto cell = cells.find(_cell_key(x, y));
			if (cell == cells.end()) {
				continue;
			}
			std::vector<int32_t> &bucket = cell->second;
			auto pos = std::lower_bound(bucket.begin(), bucket.end(), p_tag);
			if (pos != bucket.end() && *pos == p_tag) {
				bucket.erase(pos);
			}
			if (bucket.empty()) {
				cells.erase(cell);
			}
		}
	}
	bounds_by_tag.erase(found);
	return true;
}

bool SpatialIndex::move(int32_t p_tag, const Vector2 &p_min, const Vector2 &p_max) {
	if (!bounds_by_tag.count(p_tag)) {
		return false;
	}
	remove(p_tag);
	add(p_tag, p_min, p_max);
	return true;
}

void SpatialIndex::query(const Vector2 &p_min, const Vector2 &p_max, std::vector<int32_t> &r_result) const {
	r_result.clear();
	Rect2 rect = _make_rect(p_min, p_max);
	int32_t min_x, min_y, max_x, max_y;
	_cell_range(rect, min_x, min_y, max_x, max_y);
	std::unordered_set<int32_t> seen;
	for (int32_t y = min_y; y <= max_y; y++) {
		for (int32_t x = min_x; x <= max_x; x++) {
			auto cell = cells.find(_cell_key(x, y));
			if (cell == cells.end()) {
				continue;
			}
			for (int32_t tag : cell->second) {
				if (seen.count(tag)) {
					continue;
				}
				auto bounds = bounds_by_tag.find(tag);
				if (bounds == bounds_by_tag.end() || !bounds->second.intersects(rect, true)) {
					continue;
				}
				seen.insert(tag);
				r_result.push_back(tag);
			}
		}
	}
	std::sort(r_result.begin(), r_result.end());
}

// ── TileMapData ──────────────────────────────────────────────────────────────

static int _ceil_div(int p_value, int p_divisor) {
	if (p_value <= 0) {
		return 0;
	}
	return (p_value + p_divisor - 1) / p_divisor;
}

void TileMapData::setup(int p_navcell_width, int p_navcell_height, int p_navcells_per_tile) {
	navcells_per_tile = std::max(1, p_navcells_per_tile);
	width = _ceil_div(p_navcell_width, navcells_per_tile);
	height = _ceil_div(p_navcell_height, navcells_per_tile);
	data.assign((size_t)width * height, 0);
}

Vector2i TileMapData::navcell_to_tile(const Vector2i &p_coord) const {
	return Vector2i(p_coord.x / navcells_per_tile, p_coord.y / navcells_per_tile);
}

Vector2i TileMapData::tile_origin_navcell(const Vector2i &p_tile) const {
	return p_tile * navcells_per_tile;
}

bool TileMapData::is_valid_tile(const Vector2i &p_tile) const {
	return p_tile.x >= 0 && p_tile.y >= 0 && p_tile.x < width && p_tile.y < height;
}

int32_t TileMapData::get_tile_data(const Vector2i &p_tile) const {
	if (!is_valid_tile(p_tile)) {
		return 0;
	}
	return data[(size_t)p_tile.y * width + p_tile.x];
}

void TileMapData::set_tile_data(const Vector2i &p_tile, int32_t p_value) {
	if (!is_valid_tile(p_tile)) {
		return;
	}
	data[(size_t)p_tile.y * width + p_tile.x] = p_value;
}

int32_t TileMapData::get_navcell_terrain_data(const Vector2i &p_coord) const {
	return get_tile_data(navcell_to_tile(p_coord));
}

// ── CoreMap ──────────────────────────────────────────────────────────────────

void CoreMap::setup(int p_width, int p_height, double p_navcell_size, const Vector2 &p_origin, int p_navcells_per_tile) {
	width = p_width;
	height = p_height;
	navcell_size = p_navcell_size;
	origin = p_origin;
	navcells_per_tile = std::max(1, p_navcells_per_tile);
	// Twin: origin + Vector2(float(width), float(height)) * navcell_size —
	// all float32 vector math.
	playable_bounds_min = origin;
	playable_bounds_max = origin + Vector2((real_t)(double)width, (real_t)(double)height) * (real_t)navcell_size;
	terrain_tiles.setup(width, height, navcells_per_tile);
	static_index.setup(_default_spatial_cell_size());
	size_t cell_count = (size_t)width * height;
	navcell_data.assign(cell_count, 0);
	terrain_navcell_data.assign(cell_count, 0);
	obstruction_navcell_data.assign(cell_count, 0);
	dirtiness.assign(cell_count, 0);
	obstruction_dirtiness.assign(cell_count, 0);
	dirty_cell_list.clear();
	obstruction_dirty_cell_list.clear();
	dirty_revision = 0;
	classes.clear();
	next_bit = 0;
	static_shapes.clear();
	next_obstruction_tag = 1;
}

int32_t CoreMap::register_passability_class(const String &p_name, double p_clearance, bool p_affects_pathfinding, int32_t p_terrain_mask) {
	if (next_bit >= PASS_CLASS_BITS) {
		ERR_PRINT("[SimNavNativeMap] passability registry full");
		return 0;
	}
	for (const PassClass &existing : classes) {
		if (existing.name == p_name) {
			ERR_PRINT("[SimNavNativeMap] duplicate passability class: " + p_name);
			return 0;
		}
	}
	PassClass config;
	config.name = p_name;
	config.clearance = p_clearance;
	config.affects_pathfinding = p_affects_pathfinding;
	config.terrain_mask = p_terrain_mask;
	config.bit_index = next_bit;
	next_bit += 1;
	classes.push_back(config);
	// Twin: SimNavMap.register_passability_class — a successful registration
	// rebuilds terrain passability and re-dirties every static obstruction.
	rebuild_terrain_passability();
	_mark_all_static_obstructions_dirty();
	return 1 << config.bit_index;
}

const PassClass *CoreMap::get_pass_class(const String &p_name) const {
	for (const PassClass &config : classes) {
		if (config.name == p_name) {
			return &config;
		}
	}
	return nullptr;
}

int32_t CoreMap::get_passability_mask(const String &p_name) const {
	const PassClass *config = get_pass_class(p_name);
	if (config == nullptr) {
		return 0;
	}
	return 1 << config->bit_index;
}

double CoreMap::max_clearance() const {
	double max_value = 0.0;
	for (const PassClass &config : classes) {
		max_value = std::max(max_value, config.clearance);
	}
	return max_value;
}

void CoreMap::set_bounds(double p_x0, double p_z0, double p_x1, double p_z1) {
	playable_bounds_min = Vector2((real_t)std::min(p_x0, p_x1), (real_t)std::min(p_z0, p_z1));
	playable_bounds_max = Vector2((real_t)std::max(p_x0, p_x1), (real_t)std::max(p_z0, p_z1));
	_mark_all_static_obstructions_dirty();
}

bool CoreMap::is_inside_playable_bounds(const Vector2 &p_world) const {
	return p_world.x >= playable_bounds_min.x && p_world.y >= playable_bounds_min.y &&
			p_world.x <= playable_bounds_max.x && p_world.y <= playable_bounds_max.y;
}

void CoreMap::set_terrain_tile_data(const Vector2i &p_tile, int32_t p_value) {
	if (!terrain_tiles.is_valid_tile(p_tile)) {
		return;
	}
	int32_t old_value = terrain_tiles.get_tile_data(p_tile);
	if (old_value == p_value) {
		return;
	}
	terrain_tiles.set_tile_data(p_tile, p_value);
	_rebuild_terrain_tile_passability(p_tile);
}

int CoreMap::rebuild_terrain_passability() {
	int changed_count = 0;
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			Vector2i coord(x, y);
			if (_set_terrain_navcell_data(coord, _blocked_mask_for_terrain_navcell(coord), true)) {
				changed_count += 1;
			}
		}
	}
	return changed_count;
}

int32_t CoreMap::add_static_obstruction(const StaticShape &p_shape) {
	int32_t tag = next_obstruction_tag;
	next_obstruction_tag += 1;
	StaticShape shape = p_shape;
	shape.tag = tag;
	static_shapes.push_back(shape);
	static_index.add(tag, _shape_bounds_min(shape), _shape_bounds_max(shape));
	_mark_shape_region_obstruction_dirty(shape);
	return tag;
}

bool CoreMap::remove_obstruction(int32_t p_tag) {
	for (size_t i = 0; i < static_shapes.size(); i++) {
		if (static_shapes[i].tag == p_tag) {
			_mark_shape_region_obstruction_dirty(static_shapes[i]);
			static_index.remove(p_tag);
			static_shapes.erase(static_shapes.begin() + i);
			return true;
		}
	}
	return false;
}

bool CoreMap::move_obstruction(int32_t p_tag, const Vector2 &p_center, double p_rotation_rad) {
	StaticShape *shape = _find_static_shape(p_tag);
	if (shape == nullptr) {
		return false;
	}
	_mark_shape_region_obstruction_dirty(*shape);
	shape->center = p_center;
	shape->rotation_rad = p_rotation_rad;
	static_index.move(p_tag, _shape_bounds_min(*shape), _shape_bounds_max(*shape));
	_mark_shape_region_obstruction_dirty(*shape);
	return true;
}

const StaticShape *CoreMap::get_static_shape(int32_t p_tag) const {
	for (const StaticShape &shape : static_shapes) {
		if (shape.tag == p_tag) {
			return &shape;
		}
	}
	return nullptr;
}

void CoreMap::get_static_shapes_sorted(std::vector<const StaticShape *> &r_shapes) const {
	// static_shapes stays ascending by tag (allocation order, order-preserving
	// removal), which is exactly GDScript's sorted-keys iteration.
	r_shapes.clear();
	r_shapes.reserve(static_shapes.size());
	for (const StaticShape &shape : static_shapes) {
		r_shapes.push_back(&shape);
	}
}

void CoreMap::get_static_shapes_in_range(const Vector2 &p_center, double p_range, std::vector<const StaticShape *> &r_shapes) const {
	r_shapes.clear();
	Vector2 query_min = p_center - Vector2((real_t)p_range, (real_t)p_range);
	Vector2 query_max = p_center + Vector2((real_t)p_range, (real_t)p_range);
	std::vector<int32_t> tags;
	static_index.query(query_min, query_max, tags);
	for (int32_t tag : tags) {
		const StaticShape *shape = get_static_shape(tag);
		if (shape == nullptr) {
			continue;
		}
		if ((double)shape->center.distance_to(p_center) <= p_range + _shape_query_radius(*shape)) {
			r_shapes.push_back(shape);
		}
	}
}

void CoreMap::mark_obstruction_shape_dirty(int32_t p_tag) {
	StaticShape *shape = _find_static_shape(p_tag);
	if (shape != nullptr) {
		_mark_shape_region_obstruction_dirty(*shape);
	}
}

void CoreMap::rebuild_dirty() {
	// Twin: SimNavMap.rebuild_dirty — scan the union of dirty obstruction
	// cells and every static shape's clearance-expanded AABB. The GDScript
	// version iterates a Dictionary in insertion order; per-cell writes are
	// independent and the dirty list is sorted on collect, so a row-major
	// sweep over a membership grid is content-identical.
	double expansion = max_clearance() + navcell_size;
	std::vector<uint8_t> scan((size_t)width * height, 0);
	std::vector<Vector2i> seed;
	collect_dirty_obstruction_navcells(seed);
	for (const Vector2i &coord : seed) {
		if (is_valid_navcell(coord)) {
			scan[(size_t)_index(coord)] = 1;
		}
	}
	for (const StaticShape &shape : static_shapes) {
		Vector2i min_cell = world_to_navcell(_shape_bounds_min(shape) - Vector2((real_t)expansion, (real_t)expansion));
		Vector2i max_cell = world_to_navcell(_shape_bounds_max(shape) + Vector2((real_t)expansion, (real_t)expansion));
		int sx = std::max(0, std::min(min_cell.x, max_cell.x));
		int ex = std::min(width - 1, std::max(min_cell.x, max_cell.x));
		int sy = std::max(0, std::min(min_cell.y, max_cell.y));
		int ey = std::min(height - 1, std::max(min_cell.y, max_cell.y));
		for (int y = sy; y <= ey; y++) {
			for (int x = sx; x <= ex; x++) {
				scan[(size_t)y * width + x] = 1;
			}
		}
	}
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			size_t idx = (size_t)y * width + x;
			if (!scan[idx]) {
				continue;
			}
			Vector2i cell(x, y);
			int32_t old_composed = navcell_data[idx] | terrain_navcell_data[idx] | obstruction_navcell_data[idx];
			obstruction_navcell_data[idx] = _blocked_mask_for_static_obstructions_at(cell);
			int32_t new_composed = navcell_data[idx] | terrain_navcell_data[idx] | obstruction_navcell_data[idx];
			if (old_composed != new_composed) {
				_mark_navcell_dirty_idx((int)idx, cell);
			}
		}
	}
	clear_dirty_obstruction_navcells();
}

int CoreMap::rasterize_dirty_obstructions() {
	if (!has_dirty_obstruction_navcells()) {
		return 0;
	}
	int changed_count = 0;
	// Iterate a copy in stored (insertion) order, mirroring the GDScript loop
	// over collect_dirty_obstruction_navcells(); per-cell writes are
	// independent of order.
	std::vector<Vector2i> cells = obstruction_dirty_cell_list;
	for (const Vector2i &coord : cells) {
		int idx = _index(coord);
		int32_t old_value = get_navcell_data(coord);
		obstruction_navcell_data[(size_t)idx] = _blocked_mask_for_static_obstructions_at(coord);
		int32_t next_value = get_navcell_data(coord);
		if (old_value != next_value) {
			_mark_navcell_dirty_idx(idx, coord);
			changed_count += 1;
		}
	}
	clear_dirty_obstruction_navcells();
	return changed_count;
}

void CoreMap::mark_dirty_navcell(const Vector2i &p_coord) {
	if (is_valid_navcell(p_coord)) {
		_mark_navcell_dirty_idx(_index(p_coord), p_coord);
	}
}

bool CoreMap::is_dirty_navcell(const Vector2i &p_coord) const {
	if (!is_valid_navcell(p_coord)) {
		return false;
	}
	return dirtiness[(size_t)_index(p_coord)] != 0;
}

void CoreMap::collect_dirty_navcells(std::vector<Vector2i> &r_cells) const {
	r_cells = dirty_cell_list;
	std::sort(r_cells.begin(), r_cells.end(), [](const Vector2i &a, const Vector2i &b) {
		if (a.y != b.y) {
			return a.y < b.y;
		}
		return a.x < b.x;
	});
}

void CoreMap::collect_dirty_obstruction_navcells(std::vector<Vector2i> &r_cells) const {
	r_cells = obstruction_dirty_cell_list;
}

void CoreMap::clear_dirty_navcells() {
	for (const Vector2i &cell : dirty_cell_list) {
		dirtiness[(size_t)_index(cell)] = 0;
	}
	dirty_cell_list.clear();
}

void CoreMap::clear_dirty_obstruction_navcells() {
	for (const Vector2i &cell : obstruction_dirty_cell_list) {
		obstruction_dirtiness[(size_t)_index(cell)] = 0;
	}
	obstruction_dirty_cell_list.clear();
}

Vector2 CoreMap::navcell_center_world(const Vector2i &p_coord) const {
	// Twin: origin + Vector2(float(x) + 0.5, float(y) + 0.5) * navcell_size.
	return origin + Vector2((real_t)((double)p_coord.x + 0.5), (real_t)((double)p_coord.y + 0.5)) * (real_t)navcell_size;
}

Vector2i CoreMap::world_to_navcell(const Vector2 &p_world) const {
	return Vector2i(
			(int)std::floor(((double)p_world.x - (double)origin.x) / navcell_size),
			(int)std::floor(((double)p_world.y - (double)origin.y) / navcell_size));
}

bool CoreMap::is_valid_navcell(const Vector2i &p_coord) const {
	return p_coord.x >= 0 && p_coord.y >= 0 && p_coord.x < width && p_coord.y < height;
}

bool CoreMap::is_passable_navcell(const Vector2i &p_coord, int32_t p_pass_mask) const {
	if (!is_valid_navcell(p_coord)) {
		return false;
	}
	return (get_navcell_data(p_coord) & p_pass_mask) == 0;
}

int32_t CoreMap::get_navcell_data(const Vector2i &p_coord) const {
	if (!is_valid_navcell(p_coord)) {
		return 0;
	}
	size_t idx = (size_t)_index(p_coord);
	return navcell_data[idx] | terrain_navcell_data[idx] | obstruction_navcell_data[idx];
}

void CoreMap::set_navcell_data(const Vector2i &p_coord, int32_t p_value) {
	if (!is_valid_navcell(p_coord)) {
		return;
	}
	int idx = _index(p_coord);
	int32_t old_value = get_navcell_data(p_coord);
	if (navcell_data[(size_t)idx] == p_value) {
		return;
	}
	navcell_data[(size_t)idx] = p_value;
	if (old_value != get_navcell_data(p_coord)) {
		_mark_navcell_dirty_idx(idx, p_coord);
	}
}

void CoreMap::or_navcell_data(const Vector2i &p_coord, int32_t p_mask) {
	if (!is_valid_navcell(p_coord)) {
		return;
	}
	int idx = _index(p_coord);
	int32_t next_value = navcell_data[(size_t)idx] | p_mask;
	if (next_value == navcell_data[(size_t)idx]) {
		return;
	}
	int32_t old_value = get_navcell_data(p_coord);
	navcell_data[(size_t)idx] = next_value;
	if (old_value != get_navcell_data(p_coord)) {
		_mark_navcell_dirty_idx(idx, p_coord);
	}
}

void CoreMap::and_navcell_data(const Vector2i &p_coord, int32_t p_inverse_mask) {
	if (!is_valid_navcell(p_coord)) {
		return;
	}
	int idx = _index(p_coord);
	int32_t next_value = navcell_data[(size_t)idx] & ~p_inverse_mask;
	if (next_value == navcell_data[(size_t)idx]) {
		return;
	}
	int32_t old_value = get_navcell_data(p_coord);
	navcell_data[(size_t)idx] = next_value;
	if (old_value != get_navcell_data(p_coord)) {
		_mark_navcell_dirty_idx(idx, p_coord);
	}
}

void CoreMap::composed_navcell_data(std::vector<int32_t> &r_out) const {
	size_t cell_count = navcell_data.size();
	r_out.resize(cell_count);
	for (size_t i = 0; i < cell_count; i++) {
		r_out[i] = navcell_data[i] | terrain_navcell_data[i] | obstruction_navcell_data[i];
	}
}

void CoreMap::composed_navcell_data_rect(const Vector2i &p_origin_cell, const Vector2i &p_size, std::vector<int32_t> &r_out) const {
	int size_x = std::max(0, p_size.x);
	int size_y = std::max(0, p_size.y);
	r_out.assign((size_t)size_x * size_y, 0);
	for (int row = 0; row < size_y; row++) {
		int y = p_origin_cell.y + row;
		size_t out_base = (size_t)row * size_x;
		if (y < 0 || y >= height) {
			for (int col = 0; col < size_x; col++) {
				r_out[out_base + col] = -1;
			}
			continue;
		}
		size_t src_base = (size_t)y * width;
		for (int col = 0; col < size_x; col++) {
			int x = p_origin_cell.x + col;
			if (x < 0 || x >= width) {
				r_out[out_base + col] = -1;
			} else {
				size_t i = src_base + x;
				r_out[out_base + col] = navcell_data[i] | terrain_navcell_data[i] | obstruction_navcell_data[i];
			}
		}
	}
}

// ── CoreMap internals ────────────────────────────────────────────────────────

void CoreMap::_mark_navcell_dirty_idx(int p_idx, const Vector2i &p_coord) {
	if (dirtiness[(size_t)p_idx] == 0) {
		dirtiness[(size_t)p_idx] = 1;
		dirty_cell_list.push_back(p_coord);
		dirty_revision += 1;
	}
}

void CoreMap::_mark_obstruction_cell_dirty(int p_idx, const Vector2i &p_coord) {
	if (obstruction_dirtiness[(size_t)p_idx] == 0) {
		obstruction_dirtiness[(size_t)p_idx] = 1;
		obstruction_dirty_cell_list.push_back(p_coord);
	}
}

void CoreMap::_mark_shape_region_obstruction_dirty(const StaticShape &p_shape) {
	double expansion = max_clearance() + navcell_size;
	Vector2i min_cell = world_to_navcell(_shape_bounds_min(p_shape) - Vector2((real_t)expansion, (real_t)expansion));
	Vector2i max_cell = world_to_navcell(_shape_bounds_max(p_shape) + Vector2((real_t)expansion, (real_t)expansion));
	int start_x = std::max(0, std::min(min_cell.x, max_cell.x));
	int end_x = std::min(width - 1, std::max(min_cell.x, max_cell.x));
	int start_y = std::max(0, std::min(min_cell.y, max_cell.y));
	int end_y = std::min(height - 1, std::max(min_cell.y, max_cell.y));
	for (int y = start_y; y <= end_y; y++) {
		for (int x = start_x; x <= end_x; x++) {
			Vector2i coord(x, y);
			_mark_obstruction_cell_dirty(_index(coord), coord);
		}
	}
}

void CoreMap::_mark_all_static_obstructions_dirty() {
	for (const StaticShape &shape : static_shapes) {
		_mark_shape_region_obstruction_dirty(shape);
	}
}

int CoreMap::_rebuild_terrain_tile_passability(const Vector2i &p_tile) {
	if (!terrain_tiles.is_valid_tile(p_tile)) {
		return 0;
	}
	int changed_count = 0;
	Vector2i start = terrain_tiles.tile_origin_navcell(p_tile);
	int terrain_padding = _clearance_navcell_padding(max_clearance());
	int start_x = std::max(0, start.x - terrain_padding);
	int start_y = std::max(0, start.y - terrain_padding);
	int end_x = std::min(width - 1, start.x + navcells_per_tile - 1 + terrain_padding);
	int end_y = std::min(height - 1, start.y + navcells_per_tile - 1 + terrain_padding);
	for (int y = start_y; y <= end_y; y++) {
		for (int x = start_x; x <= end_x; x++) {
			Vector2i coord(x, y);
			if (_set_terrain_navcell_data(coord, _blocked_mask_for_terrain_navcell(coord), true)) {
				changed_count += 1;
			}
		}
	}
	return changed_count;
}

bool CoreMap::_set_terrain_navcell_data(const Vector2i &p_coord, int32_t p_value, bool p_mark_dirty) {
	if (!is_valid_navcell(p_coord)) {
		return false;
	}
	int idx = _index(p_coord);
	if (terrain_navcell_data[(size_t)idx] == p_value) {
		return false;
	}
	int32_t old_value = get_navcell_data(p_coord);
	terrain_navcell_data[(size_t)idx] = p_value;
	if (p_mark_dirty && old_value != get_navcell_data(p_coord)) {
		_mark_navcell_dirty_idx(idx, p_coord);
		return true;
	}
	return false;
}

int32_t CoreMap::_blocked_mask_for_terrain_navcell(const Vector2i &p_coord) const {
	int32_t result = 0;
	for (const PassClass &config : classes) {
		if (_terrain_blocks_navcell_for_class(p_coord, config)) {
			result |= 1 << config.bit_index;
		}
	}
	return result;
}

bool CoreMap::_terrain_data_blocks_class(int32_t p_terrain_data, const PassClass &p_config) const {
	if (!_class_uses_terrain_mask(p_config)) {
		return false;
	}
	return (p_terrain_data & p_config.terrain_mask) != 0;
}

bool CoreMap::_class_uses_terrain_mask(const PassClass &p_config) const {
	if (!p_config.affects_pathfinding) {
		return false;
	}
	return p_config.terrain_mask != 0;
}

bool CoreMap::_terrain_blocks_navcell_for_class(const Vector2i &p_coord, const PassClass &p_config) const {
	if (!is_valid_navcell(p_coord)) {
		return false;
	}
	if (!_class_uses_terrain_mask(p_config)) {
		return false;
	}
	if (p_config.clearance <= 0.0) {
		return _terrain_data_blocks_class(get_navcell_terrain_data(p_coord), p_config);
	}
	Vector2 center_world = navcell_center_world(p_coord);
	int padding = _clearance_navcell_padding(p_config.clearance);
	int start_x = std::max(0, p_coord.x - padding);
	int end_x = std::min(width - 1, p_coord.x + padding);
	int start_y = std::max(0, p_coord.y - padding);
	int end_y = std::min(height - 1, p_coord.y + padding);
	for (int y = start_y; y <= end_y; y++) {
		for (int x = start_x; x <= end_x; x++) {
			Vector2i terrain_coord(x, y);
			if (!_terrain_data_blocks_class(get_navcell_terrain_data(terrain_coord), p_config)) {
				continue;
			}
			if (_point_overlaps_navcell_rect_with_clearance(center_world, terrain_coord, p_config.clearance)) {
				return true;
			}
		}
	}
	return false;
}

bool CoreMap::_point_overlaps_navcell_rect_with_clearance(const Vector2 &p_point, const Vector2i &p_coord, double p_clearance) const {
	// Twin: same-named GDScript helper — float32 rect corners, double
	// distance test.
	Vector2 min_world = origin + Vector2((real_t)(double)p_coord.x, (real_t)(double)p_coord.y) * (real_t)navcell_size;
	Vector2 max_world = min_world + Vector2((real_t)navcell_size, (real_t)navcell_size);
	double dx = 0.0;
	if (p_point.x < min_world.x) {
		dx = (double)min_world.x - (double)p_point.x;
	} else if (p_point.x > max_world.x) {
		dx = (double)p_point.x - (double)max_world.x;
	}
	double dy = 0.0;
	if (p_point.y < min_world.y) {
		dy = (double)min_world.y - (double)p_point.y;
	} else if (p_point.y > max_world.y) {
		dy = (double)p_point.y - (double)max_world.y;
	}
	return dx * dx + dy * dy <= p_clearance * p_clearance + 0.001;
}

int CoreMap::_clearance_navcell_padding(double p_clearance) const {
	if (p_clearance <= 0.0) {
		return 0;
	}
	return (int)std::ceil(p_clearance / std::max(navcell_size, 0.001)) + 1;
}

int32_t CoreMap::_blocked_mask_for_point(const StaticShape &p_shape, const Vector2 &p_point) const {
	if (!is_inside_playable_bounds(p_point)) {
		return 0;
	}
	// CLEARANCE_EXTENSION_RADIUS (+1 navcell) — see the GDScript twin's
	// CORE-005 note; terrain rasterization intentionally does NOT get this.
	double raster_extension = navcell_size;
	int32_t result = 0;
	for (const PassClass &config : classes) {
		if (!config.affects_pathfinding) {
			continue;
		}
		if (p_shape.contains_point_with_clearance(p_point, config.clearance + raster_extension)) {
			result |= 1 << config.bit_index;
		}
	}
	return result;
}

int32_t CoreMap::_blocked_mask_for_static_obstructions_at(const Vector2i &p_coord) const {
	Vector2 point = navcell_center_world(p_coord);
	double query_radius = max_clearance() + navcell_size;
	std::vector<int32_t> tags;
	static_index.query(
			point - Vector2((real_t)query_radius, (real_t)query_radius),
			point + Vector2((real_t)query_radius, (real_t)query_radius), tags);
	int32_t result = 0;
	for (int32_t tag : tags) {
		const StaticShape *shape = get_static_shape(tag);
		if (shape == nullptr) {
			continue;
		}
		if ((shape->flags & FLAG_BLOCK_PATHFINDING) == 0) {
			continue;
		}
		result |= _blocked_mask_for_point(*shape, point);
	}
	return result;
}

double CoreMap::_shape_query_radius(const StaticShape &p_shape) const {
	return std::sqrt(p_shape.width * p_shape.width + p_shape.height * p_shape.height) * 0.5;
}

Vector2 CoreMap::_shape_bounds_min(const StaticShape &p_shape) const {
	double radius = _shape_query_radius(p_shape);
	return p_shape.center - Vector2((real_t)radius, (real_t)radius);
}

Vector2 CoreMap::_shape_bounds_max(const StaticShape &p_shape) const {
	double radius = _shape_query_radius(p_shape);
	return p_shape.center + Vector2((real_t)radius, (real_t)radius);
}

double CoreMap::_default_spatial_cell_size() const {
	return std::max(navcell_size * 8.0, 16.0);
}

StaticShape *CoreMap::_find_static_shape(int32_t p_tag) {
	for (StaticShape &shape : static_shapes) {
		if (shape.tag == p_tag) {
			return &shape;
		}
	}
	return nullptr;
}

} // namespace simnav
