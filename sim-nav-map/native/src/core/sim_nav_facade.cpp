#include "sim_nav_facade.h"

#include <algorithm>
#include <cmath>

namespace simnav {

using godot::real_t;

// Twin: SimNavObstructionFlags.BLOCK_PATHFINDING.
static constexpr int32_t FLAG_BLOCK_PATHFINDING = 1 << 3;

// ── LineFilter ───────────────────────────────────────────────────────────────

static bool _shape_matches_control_group(const StaticShape &p_shape, const String &p_group) {
	if (p_group.is_empty()) {
		return false;
	}
	return p_shape.control_group == p_group || p_shape.control_group_2 == p_group;
}

bool LineFilter::matches_static(const StaticShape &p_shape) const {
	if (!include_static) {
		return false;
	}
	if (ignored_tag > 0 && p_shape.tag == ignored_tag) {
		return false;
	}
	if (std::find(ignored_tags.begin(), ignored_tags.end(), p_shape.tag) != ignored_tags.end()) {
		return false;
	}
	if (!ignored_entity_id.is_empty() && p_shape.entity_id == ignored_entity_id) {
		return false;
	}
	if (std::find(ignored_entity_ids.begin(), ignored_entity_ids.end(), p_shape.entity_id) != ignored_entity_ids.end()) {
		return false;
	}
	if (_shape_matches_control_group(p_shape, control_group)) {
		return false;
	}
	for (const String &group : ignored_control_groups) {
		if (_shape_matches_control_group(p_shape, group)) {
			return false;
		}
	}
	if (required_flags != 0 && (p_shape.flags & required_flags) != required_flags) {
		return false;
	}
	if (excluded_flags != 0 && (p_shape.flags & excluded_flags) != 0) {
		return false;
	}
	return true;
}

// ── Flush / reachability / long path ─────────────────────────────────────────

void Facade::recompute(const std::vector<int32_t> &p_masks) {
	hier.recompute(*map, p_masks);
}

FlushStats Facade::recompute_dirty(const std::vector<int32_t> &p_masks, bool p_clear_dirty_navcells) {
	FlushStats stats;
	if (map == nullptr) {
		return stats;
	}
	stats.changed_obstruction_navcells = map->rasterize_dirty_obstructions();
	std::vector<Vector2i> dirty;
	map->collect_dirty_navcells(dirty);
	stats.dirty_navcells = (int64_t)dirty.size();
	if (stats.dirty_navcells > 0) {
		stats.rebuilt_chunks = hier.recompute_dirty(*map, p_masks);
		// Incremental: built jump tables are repaired for the dirty band, not
		// discarded. Must precede the clear below.
		long_pathfinder.repair_jump_point_caches();
	}
	if (p_clear_dirty_navcells && stats.dirty_navcells > 0) {
		map->clear_dirty_navcells();
	}
	stats.invalidated_long_path_cache = stats.dirty_navcells > 0;
	return stats;
}

ReachabilityData Facade::query_reachability(const Vector2 &p_start_world, const PathGoal &p_goal, int32_t p_pass_mask, const String &p_class_name) const {
	if (map == nullptr) {
		ReachabilityData missing;
		missing.pass_mask = p_pass_mask;
		missing.passability_class_name = p_class_name;
		missing.has_query_goal = true;
		missing.query_goal = p_goal;
		missing.set_failure(ReachabilityData::FAILURE_NOT_RECOMPUTED);
		return missing;
	}
	Vector2i start_cell = map->world_to_navcell(p_start_world);
	return hier.query_goal_reachability(*map, start_cell, p_goal, p_pass_mask, p_class_name);
}

LongPathResult Facade::compute_path_result(const LongPathQuery &p_query) {
	LongPathResult result;
	result.configure_query(p_query, map);
	if (!p_query.has_goal) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_GOAL_MISSING);
		return result;
	}
	if (map == nullptr) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_NAV_MAP_MISSING);
		return result;
	}

	LongPathQuery working_query = p_query;
	bool have_reachability = false;
	ReachabilityData reachability;
	if (hier.is_recomputed()) {
		reachability = query_reachability(p_query.start_world, p_query.goal, p_query.pass_mask, p_query.passability_class_name);
		have_reachability = true;
		if (reachability.is_failure()) {
			result.has_reachability = true;
			result.reachability = reachability;
			result.canonicalization_reason = reachability.failure_reason;
			result.effective_start_navcell = reachability.effective_start_navcell;
			result.set_failure(_status_for_reachability_failure(reachability), _failure_for_reachability_failure(reachability));
			return result;
		}
		if (reachability.has_canonical_goal) {
			working_query.goal = reachability.canonical_goal;
			working_query.has_goal = true;
			if (reachability.effective_start_navcell != reachability.start_navcell) {
				working_query.start_world = map->navcell_center_world(reachability.effective_start_navcell);
			}
		}
	}

	LongPathResult path_result = long_pathfinder.compute_path_result(working_query);
	if (have_reachability) {
		_apply_reachability_metadata(path_result, p_query, reachability);
	}
	return path_result;
}

void Facade::_apply_reachability_metadata(LongPathResult &p_result, const LongPathQuery &p_query, const ReachabilityData &p_reachability) const {
	p_result.has_reachability = true;
	p_result.reachability = p_reachability;
	p_result.start_world = p_query.start_world;
	p_result.start_navcell = p_reachability.start_navcell;
	p_result.effective_start_navcell = p_reachability.effective_start_navcell;
	p_result.effective_start_world = map->navcell_center_world(p_reachability.effective_start_navcell);
	p_result.pass_mask = p_reachability.pass_mask;
	p_result.passability_class_name = p_reachability.passability_class_name;
	p_result.has_query_goal = p_query.has_goal;
	p_result.query_goal = p_query.goal;
	p_result.has_canonical_goal = p_reachability.has_canonical_goal;
	if (p_reachability.has_canonical_goal) {
		p_result.canonical_goal = p_reachability.canonical_goal;
	}
	p_result.canonical_navcell = p_reachability.canonical_navcell;
	p_result.canonicalized = p_reachability.canonicalized;
	p_result.canonicalization_reason = p_reachability.canonicalized ? p_reachability.failure_reason : String(ReachabilityData::FAILURE_NONE);
	p_result.start_recovered = p_reachability.effective_start_navcell != p_reachability.start_navcell;
	if (!p_result.is_success()) {
		return;
	}
	if (p_result.start_recovered) {
		p_result.status = LongPathResult::STATUS_START_RECOVERED;
	} else if (p_result.canonicalized) {
		p_result.status = LongPathResult::STATUS_CANONICALIZED;
	}
}

String Facade::_status_for_reachability_failure(const ReachabilityData &p_reachability) {
	if (p_reachability.failure_reason == String(ReachabilityData::FAILURE_NO_START_REGION)) {
		return LongPathResult::STATUS_INVALID_START;
	}
	if (p_reachability.failure_reason == String(ReachabilityData::FAILURE_NO_REACHABLE_GOAL) ||
			p_reachability.failure_reason == String(ReachabilityData::FAILURE_ORIGINAL_GOAL_UNREACHABLE)) {
		return LongPathResult::STATUS_UNREACHABLE;
	}
	return LongPathResult::STATUS_INVALID_QUERY;
}

String Facade::_failure_for_reachability_failure(const ReachabilityData &p_reachability) {
	if (p_reachability.failure_reason == String(ReachabilityData::FAILURE_NO_START_REGION)) {
		return LongPathResult::FAILURE_START_BLOCKED;
	}
	if (p_reachability.failure_reason == String(ReachabilityData::FAILURE_NO_REACHABLE_GOAL) ||
			p_reachability.failure_reason == String(ReachabilityData::FAILURE_ORIGINAL_GOAL_UNREACHABLE)) {
		return LongPathResult::FAILURE_NO_ROUTE;
	}
	if (p_reachability.failure_reason == String(ReachabilityData::FAILURE_INVALID_QUERY)) {
		return LongPathResult::FAILURE_GOAL_MISSING;
	}
	return LongPathResult::FAILURE_NAV_MAP_MISSING;
}

// ── Movement line (boolean fast path) ────────────────────────────────────────

bool Facade::movement_line_clear(const Vector2 &p_start, const Vector2 &p_target, double p_clearance, int32_t p_pass_mask, const LineFilter &p_filter) {
	if (map == nullptr) {
		return false;
	}
	if (p_pass_mask != 0) {
		if (!long_pathfinder.movement_raster_clear(p_start, p_target, p_pass_mask)) {
			return false;
		}
	}
	std::vector<const StaticShape *> shapes;
	_collect_line_obstructions(p_start, p_target, p_clearance, p_filter, shapes);
	double buffer = std::max(p_clearance, 0.000001);
	for (const StaticShape *shape : shapes) {
		if (static_shape_blocks_segment(p_start, p_target, *shape, buffer)) {
			return false;
		}
	}
	return true;
}

void Facade::_collect_line_obstructions(const Vector2 &p_start, const Vector2 &p_target, double p_clearance, const LineFilter &p_filter, std::vector<const StaticShape *> &r_shapes) const {
	// Twin: facade._collect_line_obstructions — center/range math, filter
	// match, then the BLOCK_PATHFINDING gate for statics.
	Vector2 center = (p_start + p_target) * (real_t)0.5;
	double query_range = (double)p_start.distance_to(p_target) * 0.5 + p_clearance + map->navcell_size;
	std::vector<const StaticShape *> candidates;
	map->get_static_shapes_in_range(center, query_range, candidates);
	r_shapes.clear();
	for (const StaticShape *shape : candidates) {
		if (!p_filter.matches_static(*shape)) {
			continue;
		}
		if ((shape->flags & FLAG_BLOCK_PATHFINDING) == 0) {
			continue;
		}
		r_shapes.push_back(shape);
	}
}

// ── LOS geometry (twin: SimNavLineOfSight static branch) ─────────────────────

bool Facade::static_shape_blocks_segment(const Vector2 &p_a, const Vector2 &p_b, const StaticShape &p_shape, double p_buffer) {
	if (p_shape.contains_point_with_clearance(p_a, p_buffer)) {
		return false;
	}
	if (p_shape.contains_point_with_clearance(p_b, p_buffer)) {
		return true;
	}
	return _segment_to_obb_dist(p_a, p_b, p_shape, p_buffer) < p_buffer;
}

double Facade::_segment_to_point_dist(const Vector2 &p_a, const Vector2 &p_b, const Vector2 &p_point) {
	Vector2 ab = p_b - p_a;
	double len_sq = (double)ab.length_squared();
	if (len_sq <= 0.0) {
		return (double)p_point.distance_to(p_a);
	}
	double t = std::clamp((double)(p_point - p_a).dot(ab) / len_sq, 0.0, 1.0);
	return (double)p_point.distance_to(p_a + ab * (real_t)t);
}

double Facade::_segment_to_obb_dist(const Vector2 &p_a, const Vector2 &p_b, const StaticShape &p_obb, double p_buffer) {
	double enclose_radius = std::sqrt(p_obb.width * p_obb.width + p_obb.height * p_obb.height) * 0.5;
	double center_dist = _segment_to_point_dist(p_a, p_b, p_obb.center);
	if (center_dist >= enclose_radius + p_buffer) {
		return center_dist - enclose_radius;
	}

	Vector2 local_a;
	Vector2 local_b;
	if (std::abs(p_obb.rotation_rad) < 0.000001) {
		local_a = p_a - p_obb.center;
		local_b = p_b - p_obb.center;
	} else {
		Vector2 u((real_t)std::cos(p_obb.rotation_rad), (real_t)std::sin(p_obb.rotation_rad));
		Vector2 v((real_t)-std::sin(p_obb.rotation_rad), (real_t)std::cos(p_obb.rotation_rad));
		local_a = Vector2((p_a - p_obb.center).dot(u), (p_a - p_obb.center).dot(v));
		local_b = Vector2((p_b - p_obb.center).dot(u), (p_b - p_obb.center).dot(v));
	}
	return _segment_to_aabb_dist(local_a, local_b, p_obb.width * 0.5, p_obb.height * 0.5);
}

double Facade::_segment_to_aabb_dist(const Vector2 &p_a, const Vector2 &p_b, double p_hw, double p_hh) {
	if (std::abs((double)p_a.x) <= p_hw && std::abs((double)p_a.y) <= p_hh) {
		return 0.0;
	}
	if (std::abs((double)p_b.x) <= p_hw && std::abs((double)p_b.y) <= p_hh) {
		return 0.0;
	}

	double t_min = 0.0;
	double t_max = 1.0;
	double dx = (double)p_b.x - (double)p_a.x;
	double dy = (double)p_b.y - (double)p_a.y;

	if (std::abs(dx) > 0.000000001) {
		double inv_dx = 1.0 / dx;
		double tx1 = (-p_hw - (double)p_a.x) * inv_dx;
		double tx2 = (p_hw - (double)p_a.x) * inv_dx;
		if (tx1 > tx2) {
			std::swap(tx1, tx2);
		}
		t_min = std::max(t_min, tx1);
		t_max = std::min(t_max, tx2);
	} else if ((double)p_a.x < -p_hw || (double)p_a.x > p_hw) {
		return _segment_aabb_no_intersect_dist(p_a, p_b, p_hw, p_hh);
	}

	if (std::abs(dy) > 0.000000001) {
		double inv_dy = 1.0 / dy;
		double ty1 = (-p_hh - (double)p_a.y) * inv_dy;
		double ty2 = (p_hh - (double)p_a.y) * inv_dy;
		if (ty1 > ty2) {
			std::swap(ty1, ty2);
		}
		t_min = std::max(t_min, ty1);
		t_max = std::min(t_max, ty2);
	} else if ((double)p_a.y < -p_hh || (double)p_a.y > p_hh) {
		return _segment_aabb_no_intersect_dist(p_a, p_b, p_hw, p_hh);
	}

	if (t_min <= t_max) {
		return 0.0;
	}
	return _segment_aabb_no_intersect_dist(p_a, p_b, p_hw, p_hh);
}

double Facade::_segment_aabb_no_intersect_dist(const Vector2 &p_a, const Vector2 &p_b, double p_hw, double p_hh) {
	double dxa = std::max(std::abs((double)p_a.x) - p_hw, 0.0);
	double dya = std::max(std::abs((double)p_a.y) - p_hh, 0.0);
	double min_dist = std::sqrt(dxa * dxa + dya * dya);

	double dxb = std::max(std::abs((double)p_b.x) - p_hw, 0.0);
	double dyb = std::max(std::abs((double)p_b.y) - p_hh, 0.0);
	min_dist = std::min(min_dist, std::sqrt(dxb * dxb + dyb * dyb));

	min_dist = std::min(min_dist, _segment_to_point_dist(p_a, p_b, Vector2((real_t)-p_hw, (real_t)-p_hh)));
	min_dist = std::min(min_dist, _segment_to_point_dist(p_a, p_b, Vector2((real_t)p_hw, (real_t)-p_hh)));
	min_dist = std::min(min_dist, _segment_to_point_dist(p_a, p_b, Vector2((real_t)p_hw, (real_t)p_hh)));
	min_dist = std::min(min_dist, _segment_to_point_dist(p_a, p_b, Vector2((real_t)-p_hw, (real_t)p_hh)));
	return min_dist;
}

} // namespace simnav
