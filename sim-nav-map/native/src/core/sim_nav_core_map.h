#pragma once

// Pure-C++ core of SimNavMap (model/sim_nav_map.gd) plus its direct
// dependencies (terrain tile map, passability registry, static obstruction
// shapes, spatial index). No Variant API on hot paths — GDExtension wrapper
// classes own instances of these and convert at the boundary.
//
// Bit-parity rules (welded by the native A/B smokes):
//   * GDScript scalar `float` is 64-bit — port scalars as double.
//   * Vector2 components are 32-bit — keep godot::Vector2 for vector math and
//     mirror the exact narrowing points of the GDScript expressions.
//   * `floorf` in GDScript is the double-precision floor, not C's floorf.
// Port expressions statement-for-statement from the GDScript twin; do not
// "improve" math or iteration order here without updating the twin note.

#include <cstdint>
#include <unordered_map>
#include <vector>

#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace simnav {

using godot::Rect2;
using godot::String;
using godot::Vector2;
using godot::Vector2i;

struct PassClass {
	String name;
	int bit_index = -1;
	double clearance = 0.0;
	bool affects_pathfinding = true;
	int32_t terrain_mask = 0;
};

// Twin: obstruction/sim_nav_obstruction_shape_static.gd (geometry only; the
// GDScript DTO fields tag/entity_id/flags ride along for filters/diagnostics).
struct StaticShape {
	int32_t tag = 0;
	String entity_id;
	Vector2 center;
	double width = 0.0;
	double height = 0.0;
	double rotation_rad = 0.0;
	int32_t flags = 0;

	bool contains_point_with_clearance(const Vector2 &p_point, double p_clearance) const;
};

// Twin: obstruction/sim_nav_spatial_index.gd. Buckets keep ascending tag
// order and query() returns ascending tags, matching the GDScript contract
// that downstream mask ORs and shape loops iterate deterministically.
class SpatialIndex {
public:
	void setup(double p_cell_size);
	void clear();
	void add(int32_t p_tag, const Vector2 &p_min, const Vector2 &p_max);
	bool remove(int32_t p_tag);
	bool move(int32_t p_tag, const Vector2 &p_min, const Vector2 &p_max);
	void query(const Vector2 &p_min, const Vector2 &p_max, std::vector<int32_t> &r_result) const;

private:
	double cell_size = 64.0;
	std::unordered_map<uint64_t, std::vector<int32_t>> cells;
	std::unordered_map<int32_t, Rect2> bounds_by_tag;

	static uint64_t _cell_key(int32_t p_x, int32_t p_y);
	Rect2 _make_rect(const Vector2 &p_min, const Vector2 &p_max) const;
	void _cell_range(const Rect2 &p_rect, int32_t &r_min_x, int32_t &r_min_y, int32_t &r_max_x, int32_t &r_max_y) const;
};

// Twin: model/sim_nav_terrain_tile_map.gd.
class TileMapData {
public:
	int width = 0;
	int height = 0;
	int navcells_per_tile = 1;

	void setup(int p_navcell_width, int p_navcell_height, int p_navcells_per_tile);
	Vector2i navcell_to_tile(const Vector2i &p_coord) const;
	Vector2i tile_origin_navcell(const Vector2i &p_tile) const;
	bool is_valid_tile(const Vector2i &p_tile) const;
	int32_t get_tile_data(const Vector2i &p_tile) const;
	void set_tile_data(const Vector2i &p_tile, int32_t p_value);
	int32_t get_navcell_terrain_data(const Vector2i &p_coord) const;

private:
	std::vector<int32_t> data;
};

// Twin: model/sim_nav_map.gd (static-obstruction subset — dynamic unit
// obstructions never enter the native map; see the port plan's scope table).
class CoreMap {
public:
	static constexpr int PASS_CLASS_BITS = 16;

	int width = 0;
	int height = 0;
	double navcell_size = 1.0;
	Vector2 origin;
	int navcells_per_tile = 1;

	void setup(int p_width, int p_height, double p_navcell_size, const Vector2 &p_origin, int p_navcells_per_tile);

	// Passability registry (twin: model/sim_nav_passability_class_registry.gd).
	int32_t register_passability_class(const String &p_name, double p_clearance, bool p_affects_pathfinding, int32_t p_terrain_mask);
	const PassClass *get_pass_class(const String &p_name) const;
	int32_t get_passability_mask(const String &p_name) const;
	double max_clearance() const;
	const std::vector<PassClass> &get_classes() const { return classes; }

	// Playable bounds.
	void set_bounds(double p_x0, double p_z0, double p_x1, double p_z1);
	bool is_inside_playable_bounds(const Vector2 &p_world) const;
	Vector2 get_playable_bounds_min() const { return playable_bounds_min; }
	Vector2 get_playable_bounds_max() const { return playable_bounds_max; }

	// Terrain.
	int32_t get_terrain_tile_data(const Vector2i &p_tile) const { return terrain_tiles.get_tile_data(p_tile); }
	void set_terrain_tile_data(const Vector2i &p_tile, int32_t p_value);
	int32_t get_navcell_terrain_data(const Vector2i &p_coord) const { return terrain_tiles.get_navcell_terrain_data(p_coord); }
	int rebuild_terrain_passability();

	// Static obstructions.
	int32_t add_static_obstruction(const StaticShape &p_shape);
	bool remove_obstruction(int32_t p_tag);
	bool move_obstruction(int32_t p_tag, const Vector2 &p_center, double p_rotation_rad);
	const StaticShape *get_static_shape(int32_t p_tag) const;
	void get_static_shapes_sorted(std::vector<const StaticShape *> &r_shapes) const;
	void mark_obstruction_shape_dirty(int32_t p_tag);

	// Dirty / raster lifecycle.
	void rebuild_dirty();
	int rasterize_dirty_obstructions();
	void mark_dirty_navcell(const Vector2i &p_coord);
	bool is_dirty_navcell(const Vector2i &p_coord) const;
	bool has_dirty_navcells() const { return !dirty_cell_list.empty(); }
	bool has_dirty_obstruction_navcells() const { return !obstruction_dirty_cell_list.empty(); }
	// Row-major sorted, matching SimNavMap.collect_dirty_navcells().
	void collect_dirty_navcells(std::vector<Vector2i> &r_cells) const;
	void collect_dirty_obstruction_navcells(std::vector<Vector2i> &r_cells) const;
	void clear_dirty_navcells();
	void clear_dirty_obstruction_navcells();
	int64_t dirty_navcell_revision() const { return dirty_revision; }

	// Navcell data.
	Vector2 navcell_center_world(const Vector2i &p_coord) const;
	Vector2i world_to_navcell(const Vector2 &p_world) const;
	bool is_valid_navcell(const Vector2i &p_coord) const;
	bool is_passable_navcell(const Vector2i &p_coord, int32_t p_pass_mask) const;
	int32_t get_navcell_data(const Vector2i &p_coord) const;
	void set_navcell_data(const Vector2i &p_coord, int32_t p_value);
	void or_navcell_data(const Vector2i &p_coord, int32_t p_mask);
	void and_navcell_data(const Vector2i &p_coord, int32_t p_inverse_mask);
	void composed_navcell_data(std::vector<int32_t> &r_out) const;

private:
	std::vector<PassClass> classes;
	int next_bit = 0;

	TileMapData terrain_tiles;
	std::vector<int32_t> navcell_data;
	std::vector<int32_t> terrain_navcell_data;
	std::vector<int32_t> obstruction_navcell_data;

	std::vector<uint8_t> dirtiness;
	std::vector<Vector2i> dirty_cell_list;
	int64_t dirty_revision = 0;
	std::vector<uint8_t> obstruction_dirtiness;
	std::vector<Vector2i> obstruction_dirty_cell_list;

	// Insertion-ordered static shapes (GDScript Dictionary keys iterate in
	// insertion order; tags are allocated ascending, so ascending tag order
	// is the same thing).
	std::vector<StaticShape> static_shapes;
	SpatialIndex static_index;
	int32_t next_obstruction_tag = 1;

	Vector2 playable_bounds_min;
	Vector2 playable_bounds_max;

	int _index(const Vector2i &p_coord) const { return p_coord.y * width + p_coord.x; }
	void _mark_navcell_dirty_idx(int p_idx, const Vector2i &p_coord);
	void _mark_obstruction_cell_dirty(int p_idx, const Vector2i &p_coord);
	void _mark_shape_region_obstruction_dirty(const StaticShape &p_shape);
	void _mark_all_static_obstructions_dirty();
	int _rebuild_terrain_tile_passability(const Vector2i &p_tile);
	bool _set_terrain_navcell_data(const Vector2i &p_coord, int32_t p_value, bool p_mark_dirty);
	int32_t _blocked_mask_for_terrain_navcell(const Vector2i &p_coord) const;
	bool _terrain_data_blocks_class(int32_t p_terrain_data, const PassClass &p_config) const;
	bool _class_uses_terrain_mask(const PassClass &p_config) const;
	bool _terrain_blocks_navcell_for_class(const Vector2i &p_coord, const PassClass &p_config) const;
	bool _point_overlaps_navcell_rect_with_clearance(const Vector2 &p_point, const Vector2i &p_coord, double p_clearance) const;
	int _clearance_navcell_padding(double p_clearance) const;
	int32_t _blocked_mask_for_point(const StaticShape &p_shape, const Vector2 &p_point) const;
	int32_t _blocked_mask_for_static_obstructions_at(const Vector2i &p_coord) const;
	double _shape_query_radius(const StaticShape &p_shape) const;
	Vector2 _shape_bounds_min(const StaticShape &p_shape) const;
	Vector2 _shape_bounds_max(const StaticShape &p_shape) const;
	double _default_spatial_cell_size() const;
	StaticShape *_find_static_shape(int32_t p_tag);
};

} // namespace simnav
