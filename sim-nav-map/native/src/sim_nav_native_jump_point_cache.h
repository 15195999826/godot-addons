#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include "core/sim_nav_jump_tables.h"
#include "sim_nav_native_map.h"

// GDExtension boundary for simnav::JumpTables. reset() binds the native map
// (mirroring the GDScript cache's _nav_map field); bakes and band repairs
// read the bound core grid directly — no per-cell Variant traffic.
class SimNavNativeJumpPointCache : public godot::RefCounted {
	GDCLASS(SimNavNativeJumpPointCache, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void reset(const godot::Ref<SimNavNativeMap> &p_map, int64_t p_pass_mask);
	// Repairs against the bound map's CURRENT dirty navcell list (row-major
	// sorted, the same enumeration SimNavLongPathfinder feeds the GDScript
	// cache).
	void repair_for_map_dirty();
	void invalidate_all();
	bool is_dirty() const;

	godot::Vector2i jump_point(const godot::Vector2i &p_start, const godot::Vector2i &p_direction, const godot::Vector2i &p_goal_cell) const;
	bool movement_line_clear(const godot::Vector2 &p_a, const godot::Vector2 &p_b) const;
	bool segment_clear(const godot::Vector2 &p_a, const godot::Vector2 &p_b) const;

	// Weld/test support.
	godot::PackedInt32Array baked_grid() const;
	godot::PackedInt32Array ray_table_east() const;
	godot::PackedInt32Array ray_table_west() const;
	godot::PackedInt32Array ray_table_south() const;
	godot::PackedInt32Array ray_table_north() const;
	bool tables_equal(const godot::Ref<SimNavNativeJumpPointCache> &p_other) const;
	int64_t repair_count() const { return tables.repair_count; }
	int64_t full_reset_count() const { return tables.full_reset_count; }

	const simnav::JumpTables &core_tables() const { return tables; }
	simnav::JumpTables &core_tables() { return tables; }

private:
	simnav::JumpTables tables;
	godot::Ref<SimNavNativeMap> bound_map;
};
