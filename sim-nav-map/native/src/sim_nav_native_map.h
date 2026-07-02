#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include "core/sim_nav_core_map.h"

// GDExtension boundary for simnav::CoreMap. Mirrors the SimNavMap public API
// (static-obstruction subset). Static obstructions are registered with
// primitive args instead of shape objects — the adapter layer owns the
// conversion. Test-support exports return packed copies for the A/B welds.
class SimNavNativeMap : public godot::RefCounted {
	GDCLASS(SimNavNativeMap, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void setup(int p_width, int p_height, double p_navcell_size, const godot::Vector2 &p_origin, int p_navcells_per_tile);

	int64_t register_passability_class(const godot::String &p_name, double p_clearance, bool p_affects_pathfinding, int64_t p_terrain_mask);
	int64_t get_passability_mask(const godot::String &p_name) const;
	double max_clearance() const;

	void set_bounds(double p_x0, double p_z0, double p_x1, double p_z1);
	bool is_inside_playable_bounds(const godot::Vector2 &p_world) const;

	int64_t get_terrain_tile_data(const godot::Vector2i &p_tile) const;
	void set_terrain_tile_data(const godot::Vector2i &p_tile, int64_t p_value);
	int64_t get_navcell_terrain_data(const godot::Vector2i &p_coord) const;
	int64_t rebuild_terrain_passability();

	int64_t add_static_obstruction(const godot::String &p_entity_id, const godot::Vector2 &p_center, double p_width, double p_height, double p_rotation_rad, int64_t p_flags, const godot::String &p_control_group, const godot::String &p_control_group_2);
	bool remove_obstruction(int64_t p_tag);
	bool move_obstruction(int64_t p_tag, const godot::Vector2 &p_center, double p_rotation_rad);
	void mark_obstruction_shape_dirty(int64_t p_tag);

	void rebuild_dirty();
	int64_t rasterize_dirty_obstructions();

	godot::Vector2 navcell_center_world(const godot::Vector2i &p_coord) const;
	godot::Vector2i world_to_navcell(const godot::Vector2 &p_world) const;
	bool is_valid_navcell(const godot::Vector2i &p_coord) const;
	bool is_passable_navcell(const godot::Vector2i &p_coord, int64_t p_pass_mask) const;
	int64_t get_navcell_data(const godot::Vector2i &p_coord) const;
	void set_navcell_data(const godot::Vector2i &p_coord, int64_t p_value);
	void or_navcell_data(const godot::Vector2i &p_coord, int64_t p_mask);
	void and_navcell_data(const godot::Vector2i &p_coord, int64_t p_inverse_mask);

	void mark_dirty_navcell(const godot::Vector2i &p_coord);
	bool is_dirty_navcell(const godot::Vector2i &p_coord) const;
	bool has_dirty_navcells() const;
	bool has_dirty_obstruction_navcells() const;
	void clear_dirty_navcells();
	void clear_dirty_obstruction_navcells();
	int64_t dirty_navcell_revision() const;
	// (x, y) pairs, row-major sorted / insertion-ordered — twins of the
	// collect_* methods' ordering contracts.
	godot::PackedInt32Array collect_dirty_navcells_packed() const;
	godot::PackedInt32Array collect_dirty_obstruction_navcells_packed() const;

	godot::PackedInt32Array composed_navcell_data() const;

	int64_t get_width() const { return core_map.width; }
	int64_t get_height() const { return core_map.height; }
	double get_navcell_size() const { return core_map.navcell_size; }
	godot::Vector2 get_origin() const { return core_map.origin; }
	int64_t get_navcells_per_tile() const { return core_map.navcells_per_tile; }

	// C++-side access for sibling native classes (cache, pathfinders).
	const simnav::CoreMap &core() const { return core_map; }
	simnav::CoreMap &core() { return core_map; }
	// Set by SimNavNativeQueue while a background batch is in flight; every
	// mutating entry point refuses until collect().
	void set_mutation_frozen(bool p_frozen) { mutation_frozen = p_frozen; }

private:
	simnav::CoreMap core_map;
	bool mutation_frozen = false;
};
