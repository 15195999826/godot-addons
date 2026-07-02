#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "core/sim_nav_facade.h"
#include "sim_nav_native_map.h"

// GDExtension boundary for simnav::Facade (+ hierarchical + long pathfinder).
// Queries and results cross as Dictionaries at plan granularity — the
// GDScript bridge (SimNavNativeBridge) converts them to/from the SimNav DTO
// classes. Keys mirror the GDScript field names one-to-one.
class SimNavNativeFacade : public godot::RefCounted {
	GDCLASS(SimNavNativeFacade, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void setup(const godot::Ref<SimNavNativeMap> &p_map);
	void recompute(const godot::PackedInt32Array &p_masks);
	godot::Dictionary recompute_dirty(const godot::PackedInt32Array &p_masks, bool p_clear_dirty_navcells);
	void prewarm_jump_point_cache(int64_t p_pass_mask);
	void invalidate_long_path_cache();

	godot::Dictionary query_reachability(const godot::Vector2 &p_start_world, const godot::Dictionary &p_goal, int64_t p_pass_mask, const godot::String &p_class_name) const;
	godot::Dictionary compute_path_result(const godot::Dictionary &p_query);
	bool movement_line_clear(const godot::Vector2 &p_start, const godot::Vector2 &p_target, double p_clearance, int64_t p_pass_mask, const godot::Dictionary &p_filter);

	int64_t get_global_region(const godot::Vector2i &p_coord, int64_t p_pass_mask) const;
	godot::Vector2i find_nearest_passable_navcell(const godot::Vector2i &p_start, int64_t p_pass_mask) const;
	godot::Dictionary export_connectivity(int64_t p_pass_mask, const godot::String &p_class_name) const;

	// C++-side access for SimNavNativeQueue (worker computes against the core
	// facade directly; Variant conversion stays on the main thread).
	simnav::Facade &core_facade() { return facade; }
	const simnav::CoreMap &core_map_for_queue() const { return bound_map->core(); }
	// In-flight regime: the worker reads map + tables concurrently, so map
	// mutation, flush, prewarm and cache invalidation are refused and every
	// table access goes through the frozen-safe (read-only) lookup.
	void set_batch_in_flight(bool p_in_flight) {
		batch_in_flight_guard = p_in_flight;
		facade.long_path().set_frozen(p_in_flight);
		if (bound_map.is_valid()) {
			bound_map->set_mutation_frozen(p_in_flight);
		}
	}
	static simnav::LongPathQuery query_from_dict_public(const godot::Dictionary &p_query) { return _query_from_dict(p_query); }
	static godot::Dictionary result_to_dict_public(const simnav::LongPathResult &p_result) { return _result_to_dict(p_result); }

private:
	godot::Ref<SimNavNativeMap> bound_map;
	simnav::Facade facade;
	bool batch_in_flight_guard = false;

	bool _ready() const { return bound_map.is_valid(); }
	static std::vector<int32_t> _masks_from_packed(const godot::PackedInt32Array &p_masks);
	static simnav::PathGoal _goal_from_dict(const godot::Dictionary &p_goal, bool &r_has_goal);
	static godot::Dictionary _goal_to_dict(const simnav::PathGoal &p_goal);
	static godot::Dictionary _reachability_to_dict(const simnav::ReachabilityData &p_data);
	static simnav::LongPathQuery _query_from_dict(const godot::Dictionary &p_query);
	static godot::Dictionary _result_to_dict(const simnav::LongPathResult &p_result);
	static simnav::LineFilter _filter_from_dict(const godot::Dictionary &p_filter);
	static godot::Array _excluded_to_array(const std::vector<simnav::ExcludedRegion> &p_regions);
};
