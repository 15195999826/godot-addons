#pragma once

// Pure-C++ twin of pathfinding/sim_nav_pathfinder_facade.gd (the subset the
// dota2-envelope consumers use — see the port plan's scope table) plus the
// static-shape branch of sim_nav_line_of_sight.gd and the static-relevant
// subset of sim_nav_obstruction_filter.gd. Unit obstructions never enter the
// native map, so validate_unit_line and the unit LOS branch have no twin here.

#include "sim_nav_core_map.h"
#include "sim_nav_hierarchical.h"
#include "sim_nav_long_pathfinder.h"

namespace simnav {

// Static-relevant subset of SimNavObstructionFilter (matches() ported with
// the unit branches unreachable).
struct LineFilter {
	bool include_static = true;
	int32_t ignored_tag = 0;
	std::vector<int32_t> ignored_tags;
	String ignored_entity_id;
	std::vector<String> ignored_entity_ids;
	String control_group;
	std::vector<String> ignored_control_groups;
	int32_t required_flags = 0;
	int32_t excluded_flags = 0;

	bool matches_static(const StaticShape &p_shape) const;
};

struct FlushStats {
	int64_t dirty_navcells = 0;
	int64_t changed_obstruction_navcells = 0;
	int64_t rebuilt_chunks = 0;
	bool invalidated_long_path_cache = false;
};

class Facade {
public:
	void setup(CoreMap *p_map) {
		map = p_map;
		long_pathfinder.setup(p_map);
	}
	Hierarchical &hierarchical() { return hier; }
	const Hierarchical &hierarchical() const { return hier; }
	LongPathfinder &long_path() { return long_pathfinder; }

	void recompute(const std::vector<int32_t> &p_masks);
	FlushStats recompute_dirty(const std::vector<int32_t> &p_masks, bool p_clear_dirty_navcells);
	ReachabilityData query_reachability(const Vector2 &p_start_world, const PathGoal &p_goal, int32_t p_pass_mask, const String &p_class_name) const;
	LongPathResult compute_path_result(const LongPathQuery &p_query);
	bool movement_line_clear(const Vector2 &p_start, const Vector2 &p_target, double p_clearance, int32_t p_pass_mask, const LineFilter &p_filter);

	// LOS geometry (twin: SimNavLineOfSight static-shape branch), exposed for
	// tests.
	static bool static_shape_blocks_segment(const Vector2 &p_a, const Vector2 &p_b, const StaticShape &p_shape, double p_buffer);

private:
	CoreMap *map = nullptr;
	Hierarchical hier;
	LongPathfinder long_pathfinder;

	void _apply_reachability_metadata(LongPathResult &p_result, const LongPathQuery &p_query, const ReachabilityData &p_reachability) const;
	static String _status_for_reachability_failure(const ReachabilityData &p_reachability);
	static String _failure_for_reachability_failure(const ReachabilityData &p_reachability);
	void _collect_line_obstructions(const Vector2 &p_start, const Vector2 &p_target, double p_clearance, const LineFilter &p_filter, std::vector<const StaticShape *> &r_shapes) const;
	static double _segment_to_point_dist(const Vector2 &p_a, const Vector2 &p_b, const Vector2 &p_point);
	static double _segment_to_obb_dist(const Vector2 &p_a, const Vector2 &p_b, const StaticShape &p_obb, double p_buffer);
	static double _segment_to_aabb_dist(const Vector2 &p_a, const Vector2 &p_b, double p_hw, double p_hh);
	static double _segment_aabb_no_intersect_dist(const Vector2 &p_a, const Vector2 &p_b, double p_hw, double p_hh);
};

} // namespace simnav
