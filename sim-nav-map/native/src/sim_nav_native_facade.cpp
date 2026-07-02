#include "sim_nav_native_facade.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

void SimNavNativeFacade::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "map"), &SimNavNativeFacade::setup);
	ClassDB::bind_method(D_METHOD("recompute", "passability_masks"), &SimNavNativeFacade::recompute);
	ClassDB::bind_method(D_METHOD("recompute_dirty", "passability_masks", "clear_dirty_navcells"), &SimNavNativeFacade::recompute_dirty, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("prewarm_jump_point_cache", "pass_mask"), &SimNavNativeFacade::prewarm_jump_point_cache);
	ClassDB::bind_method(D_METHOD("invalidate_long_path_cache"), &SimNavNativeFacade::invalidate_long_path_cache);
	ClassDB::bind_method(D_METHOD("query_reachability", "start_world", "goal", "pass_mask", "passability_class_name"), &SimNavNativeFacade::query_reachability, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("compute_path_result", "query"), &SimNavNativeFacade::compute_path_result);
	ClassDB::bind_method(D_METHOD("movement_line_clear", "start_world", "target_world", "clearance", "pass_mask", "obstruction_filter"), &SimNavNativeFacade::movement_line_clear, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("get_global_region", "coord", "pass_mask"), &SimNavNativeFacade::get_global_region);
	ClassDB::bind_method(D_METHOD("find_nearest_passable_navcell", "start", "pass_mask"), &SimNavNativeFacade::find_nearest_passable_navcell);
	ClassDB::bind_method(D_METHOD("export_connectivity", "pass_mask", "passability_class_name"), &SimNavNativeFacade::export_connectivity, DEFVAL(String()));
}

void SimNavNativeFacade::setup(const Ref<SimNavNativeMap> &p_map) {
	ERR_FAIL_COND(p_map.is_null());
	bound_map = p_map;
	facade.setup(&p_map->core());
}

std::vector<int32_t> SimNavNativeFacade::_masks_from_packed(const PackedInt32Array &p_masks) {
	std::vector<int32_t> masks;
	masks.reserve((size_t)p_masks.size());
	for (int64_t i = 0; i < p_masks.size(); i++) {
		masks.push_back(p_masks[i]);
	}
	return masks;
}

void SimNavNativeFacade::recompute(const PackedInt32Array &p_masks) {
	ERR_FAIL_COND_MSG(!_ready(), "facade has no bound map (call setup first)");
	ERR_FAIL_COND_MSG(batch_in_flight_guard, "recompute while a background plan batch is in flight (collect first)");
	facade.recompute(_masks_from_packed(p_masks));
}

Dictionary SimNavNativeFacade::recompute_dirty(const PackedInt32Array &p_masks, bool p_clear_dirty_navcells) {
	Dictionary out;
	ERR_FAIL_COND_V_MSG(!_ready(), out, "facade has no bound map (call setup first)");
	ERR_FAIL_COND_V_MSG(batch_in_flight_guard, out, "recompute_dirty while a background plan batch is in flight (collect first)");
	simnav::FlushStats stats = facade.recompute_dirty(_masks_from_packed(p_masks), p_clear_dirty_navcells);
	out["dirty_navcells"] = stats.dirty_navcells;
	out["changed_obstruction_navcells"] = stats.changed_obstruction_navcells;
	out["rebuilt_chunks"] = stats.rebuilt_chunks;
	out["invalidated_long_path_cache"] = stats.invalidated_long_path_cache;
	return out;
}

void SimNavNativeFacade::prewarm_jump_point_cache(int64_t p_pass_mask) {
	ERR_FAIL_COND_MSG(!_ready(), "facade has no bound map (call setup first)");
	ERR_FAIL_COND_MSG(batch_in_flight_guard, "prewarm while a background plan batch is in flight (collect first)");
	facade.long_path().prewarm_jump_point_cache((int32_t)p_pass_mask);
}

void SimNavNativeFacade::invalidate_long_path_cache() {
	ERR_FAIL_COND_MSG(batch_in_flight_guard, "invalidate while a background plan batch is in flight (collect first)");
	facade.long_path().invalidate_jump_point_cache();
}

Dictionary SimNavNativeFacade::query_reachability(const Vector2 &p_start_world, const Dictionary &p_goal, int64_t p_pass_mask, const String &p_class_name) const {
	Dictionary out;
	ERR_FAIL_COND_V_MSG(!_ready(), out, "facade has no bound map (call setup first)");
	bool has_goal = false;
	simnav::PathGoal goal = _goal_from_dict(p_goal, has_goal);
	if (!has_goal) {
		// Twin: the GDScript chain still records the start cells for an
		// invalid query (configure_query runs before the failure).
		simnav::ReachabilityData invalid;
		invalid.pass_mask = (int32_t)p_pass_mask;
		invalid.passability_class_name = p_class_name;
		invalid.start_navcell = bound_map->core().world_to_navcell(p_start_world);
		invalid.effective_start_navcell = invalid.start_navcell;
		invalid.set_failure(simnav::ReachabilityData::FAILURE_INVALID_QUERY);
		return _reachability_to_dict(invalid);
	}
	return _reachability_to_dict(facade.query_reachability(p_start_world, goal, (int32_t)p_pass_mask, p_class_name));
}

Dictionary SimNavNativeFacade::compute_path_result(const Dictionary &p_query) {
	Dictionary out;
	ERR_FAIL_COND_V_MSG(!_ready(), out, "facade has no bound map (call setup first)");
	return _result_to_dict(facade.compute_path_result(_query_from_dict(p_query)));
}

bool SimNavNativeFacade::movement_line_clear(const Vector2 &p_start, const Vector2 &p_target, double p_clearance, int64_t p_pass_mask, const Dictionary &p_filter) {
	ERR_FAIL_COND_V_MSG(!_ready(), false, "facade has no bound map (call setup first)");
	return facade.movement_line_clear(p_start, p_target, p_clearance, (int32_t)p_pass_mask, _filter_from_dict(p_filter));
}

int64_t SimNavNativeFacade::get_global_region(const Vector2i &p_coord, int64_t p_pass_mask) const {
	ERR_FAIL_COND_V_MSG(!_ready(), 0, "facade has no bound map (call setup first)");
	return facade.hierarchical().get_global_region(bound_map->core(), p_coord, (int32_t)p_pass_mask);
}

Vector2i SimNavNativeFacade::find_nearest_passable_navcell(const Vector2i &p_start, int64_t p_pass_mask) const {
	ERR_FAIL_COND_V_MSG(!_ready(), Vector2i(-1, -1), "facade has no bound map (call setup first)");
	return facade.hierarchical().find_nearest_passable_navcell(bound_map->core(), p_start, (int32_t)p_pass_mask);
}

Dictionary SimNavNativeFacade::export_connectivity(int64_t p_pass_mask, const String &p_class_name) const {
	Dictionary out;
	ERR_FAIL_COND_V_MSG(!_ready(), out, "facade has no bound map (call setup first)");
	std::vector<int32_t> regions;
	int global_region_count = 0;
	facade.hierarchical().export_connectivity(bound_map->core(), (int32_t)p_pass_mask, regions, global_region_count);
	PackedInt32Array packed;
	packed.resize((int64_t)regions.size());
	int32_t *w = packed.ptrw();
	for (size_t i = 0; i < regions.size(); i++) {
		w[i] = regions[i];
	}
	out["pass_mask"] = p_pass_mask;
	out["passability_class_name"] = p_class_name;
	out["width"] = regions.empty() ? 0 : bound_map->core().width;
	out["height"] = regions.empty() ? 0 : bound_map->core().height;
	out["chunk_size"] = simnav::Hierarchical::CHUNK_SIZE;
	out["chunks_w"] = facade.hierarchical().chunks_width();
	out["chunks_h"] = facade.hierarchical().chunks_height();
	out["global_region_count"] = global_region_count;
	out["regions"] = packed;
	return out;
}

// ── Converters ───────────────────────────────────────────────────────────────

simnav::PathGoal SimNavNativeFacade::_goal_from_dict(const Dictionary &p_goal, bool &r_has_goal) {
	simnav::PathGoal goal;
	r_has_goal = !p_goal.is_empty();
	if (!r_has_goal) {
		return goal;
	}
	goal.type = (int)(int64_t)p_goal.get("type", 0);
	goal.center = (Vector2)p_goal.get("center", Vector2());
	goal.hw = (double)p_goal.get("hw", 0.0);
	goal.hh = (double)p_goal.get("hh", 0.0);
	goal.u = (Vector2)p_goal.get("u", Vector2(1, 0));
	goal.v = (Vector2)p_goal.get("v", Vector2(0, 1));
	goal.maxdist = (double)p_goal.get("maxdist", 0.0);
	return goal;
}

Dictionary SimNavNativeFacade::_goal_to_dict(const simnav::PathGoal &p_goal) {
	Dictionary out;
	out["type"] = p_goal.type;
	out["center"] = p_goal.center;
	out["hw"] = p_goal.hw;
	out["hh"] = p_goal.hh;
	out["u"] = p_goal.u;
	out["v"] = p_goal.v;
	out["maxdist"] = p_goal.maxdist;
	return out;
}

Dictionary SimNavNativeFacade::_reachability_to_dict(const simnav::ReachabilityData &p_data) {
	Dictionary out;
	out["is_reachable"] = p_data.is_reachable;
	out["canonicalized"] = p_data.canonicalized;
	out["failure_reason"] = p_data.failure_reason;
	out["pass_mask"] = p_data.pass_mask;
	out["passability_class_name"] = p_data.passability_class_name;
	out["start_navcell"] = p_data.start_navcell;
	out["effective_start_navcell"] = p_data.effective_start_navcell;
	out["canonical_navcell"] = p_data.canonical_navcell;
	out["start_global_region"] = p_data.start_global_region;
	out["canonical_global_region"] = p_data.canonical_global_region;
	out["query_goal"] = p_data.has_query_goal ? Variant(_goal_to_dict(p_data.query_goal)) : Variant();
	out["canonical_goal"] = p_data.has_canonical_goal ? Variant(_goal_to_dict(p_data.canonical_goal)) : Variant();
	return out;
}

simnav::LongPathQuery SimNavNativeFacade::_query_from_dict(const Dictionary &p_query) {
	simnav::LongPathQuery query;
	query.start_world = (Vector2)p_query.get("start_world", Vector2());
	Dictionary goal_dict = p_query.get("goal", Dictionary());
	query.goal = _goal_from_dict(goal_dict, query.has_goal);
	query.pass_mask = (int32_t)(int64_t)p_query.get("pass_mask", 0);
	query.passability_class_name = (String)p_query.get("passability_class_name", String());
	Array excluded = p_query.get("excluded_regions", Array());
	for (int64_t i = 0; i < excluded.size(); i++) {
		Dictionary region = excluded[i];
		simnav::ExcludedRegion excluded_region;
		excluded_region.center = (Vector2)region.get("center", Vector2());
		excluded_region.radius = std::max(0.0, (double)region.get("radius", 0.0));
		query.excluded_regions.push_back(excluded_region);
	}
	query.waypoint_spacing = (double)p_query.get("waypoint_spacing", 0.0);
	query.post_process = (String)p_query.get("post_process", String(simnav::LongPathQuery::POST_PROCESS_RAW));
	return query;
}

Array SimNavNativeFacade::_excluded_to_array(const std::vector<simnav::ExcludedRegion> &p_regions) {
	Array out;
	for (const simnav::ExcludedRegion &region : p_regions) {
		Dictionary entry;
		entry["center"] = region.center;
		entry["radius"] = region.radius;
		out.push_back(entry);
	}
	return out;
}

Dictionary SimNavNativeFacade::_result_to_dict(const simnav::LongPathResult &p_result) {
	Dictionary out;
	out["status"] = p_result.status;
	out["failure_reason"] = p_result.failure_reason;
	out["canonicalization_reason"] = p_result.canonicalization_reason;
	out["pass_mask"] = p_result.pass_mask;
	out["passability_class_name"] = p_result.passability_class_name;
	out["start_world"] = p_result.start_world;
	out["effective_start_world"] = p_result.effective_start_world;
	out["start_navcell"] = p_result.start_navcell;
	out["effective_start_navcell"] = p_result.effective_start_navcell;
	out["canonical_navcell"] = p_result.canonical_navcell;
	out["query_goal"] = p_result.has_query_goal ? Variant(_goal_to_dict(p_result.query_goal)) : Variant();
	out["canonical_goal"] = p_result.has_canonical_goal ? Variant(_goal_to_dict(p_result.canonical_goal)) : Variant();
	out["canonicalized"] = p_result.canonicalized;
	out["start_recovered"] = p_result.start_recovered;
	out["reachability_result"] = p_result.has_reachability ? Variant(_reachability_to_dict(p_result.reachability)) : Variant();
	out["excluded_regions"] = _excluded_to_array(p_result.excluded_regions);
	out["post_process"] = p_result.post_process;
	out["waypoint_spacing"] = p_result.waypoint_spacing;
	// Constants in the GDScript DTO — mirrored so the boundary stays
	// field-for-field complete.
	out["waypoint_order"] = "reverse_consumption";
	out["raw_navcell_order"] = "start_to_goal";

	PackedInt32Array raw_cells;
	raw_cells.resize((int64_t)p_result.raw_navcell_path.size() * 2);
	int32_t *cw = raw_cells.ptrw();
	for (size_t i = 0; i < p_result.raw_navcell_path.size(); i++) {
		cw[i * 2] = p_result.raw_navcell_path[i].x;
		cw[i * 2 + 1] = p_result.raw_navcell_path[i].y;
	}
	out["raw_navcell_path"] = raw_cells;

	PackedVector2Array raw_path;
	raw_path.resize((int64_t)p_result.raw_waypoint_path.size());
	Vector2 *rw = raw_path.ptrw();
	for (size_t i = 0; i < p_result.raw_waypoint_path.size(); i++) {
		rw[i] = p_result.raw_waypoint_path[i];
	}
	out["raw_waypoint_path"] = raw_path;

	PackedVector2Array refined_path;
	refined_path.resize((int64_t)p_result.refined_waypoint_path.size());
	Vector2 *fw = refined_path.ptrw();
	for (size_t i = 0; i < p_result.refined_waypoint_path.size(); i++) {
		fw[i] = p_result.refined_waypoint_path[i];
	}
	out["refined_waypoint_path"] = refined_path;

	out["path_cost"] = p_result.path_cost;
	out["path_length"] = p_result.path_length;
	out["raw_navcell_count"] = (int64_t)p_result.raw_navcell_path.size();
	out["raw_waypoint_count"] = (int64_t)p_result.raw_waypoint_path.size();
	out["refined_waypoint_count"] = (int64_t)p_result.refined_waypoint_path.size();
	out["search_algorithm"] = p_result.search.algorithm;
	out["search_expansion_count"] = p_result.search.expansion_count;
	out["search_push_count"] = p_result.search.push_count;
	out["search_jump_count"] = p_result.search.jump_count;
	out["search_closed_count"] = p_result.search.closed_count;
	out["search_max_open_count"] = p_result.search.max_open_count;
	out["search_path_cell_count"] = p_result.search.path_cell_count;
	return out;
}

simnav::LineFilter SimNavNativeFacade::_filter_from_dict(const Dictionary &p_filter) {
	simnav::LineFilter filter;
	if (p_filter.is_empty()) {
		return filter;
	}
	filter.include_static = (bool)p_filter.get("include_static", true);
	filter.ignored_tag = (int32_t)(int64_t)p_filter.get("ignored_tag", 0);
	Array ignored_tags = p_filter.get("ignored_tags", Array());
	for (int64_t i = 0; i < ignored_tags.size(); i++) {
		filter.ignored_tags.push_back((int32_t)(int64_t)ignored_tags[i]);
	}
	filter.ignored_entity_id = (String)p_filter.get("ignored_entity_id", String());
	Array ignored_entities = p_filter.get("ignored_entity_ids", Array());
	for (int64_t i = 0; i < ignored_entities.size(); i++) {
		filter.ignored_entity_ids.push_back((String)ignored_entities[i]);
	}
	filter.control_group = (String)p_filter.get("control_group", String());
	Array ignored_groups = p_filter.get("ignored_control_groups", Array());
	for (int64_t i = 0; i < ignored_groups.size(); i++) {
		filter.ignored_control_groups.push_back((String)ignored_groups[i]);
	}
	filter.required_flags = (int32_t)(int64_t)p_filter.get("required_flags", 0);
	filter.excluded_flags = (int32_t)(int64_t)p_filter.get("excluded_flags", 0);
	return filter;
}
