#pragma once

// Pure-C++ twin of pathfinding/sim_nav_long_pathfinder.gd (+ the query/result
// DTO shapes from sim_nav_long_path_query.gd / sim_nav_long_path_result.gd).
// Search order (sorted-array 5-key "heap", insertion sequence, successor
// pruning) and every diagnostic counter are ported one-to-one — cells, costs
// and counters are part of the A/B weld. Status/failure strings match the
// GDScript constants byte-for-byte.

#include <array>
#include <unordered_map>
#include <vector>

#include "sim_nav_core_map.h"
#include "sim_nav_hierarchical.h"
#include "sim_nav_jump_tables.h"
#include "sim_nav_path_goal.h"

namespace simnav {

struct ExcludedRegion {
	Vector2 center;
	double radius = 0.0;
};

struct LongPathQuery {
	static constexpr const char *POST_PROCESS_RAW = "raw";
	static constexpr const char *POST_PROCESS_LINE_OF_SIGHT = "line_of_sight";
	static constexpr const char *POST_PROCESS_MAX_SPACING = "max_spacing";

	Vector2 start_world;
	bool has_goal = false;
	PathGoal goal;
	int32_t pass_mask = 0;
	String passability_class_name;
	std::vector<ExcludedRegion> excluded_regions;
	double waypoint_spacing = 0.0;
	String post_process = POST_PROCESS_RAW;
};

struct SearchDiagnostics {
	String algorithm;
	int64_t expansion_count = 0;
	int64_t push_count = 0;
	int64_t jump_count = 0;
	int64_t closed_count = 0;
	int64_t max_open_count = 0;
	int64_t path_cell_count = 0;
};

struct LongPathResult {
	static constexpr const char *STATUS_SUCCESS = "success";
	static constexpr const char *STATUS_CANONICALIZED = "canonicalized";
	static constexpr const char *STATUS_START_RECOVERED = "start_recovered";
	static constexpr const char *STATUS_DIRECT_GOAL = "direct_goal";
	static constexpr const char *STATUS_UNREACHABLE = "unreachable";
	static constexpr const char *STATUS_NO_PATH = "no_path";
	static constexpr const char *STATUS_INVALID_START = "invalid_start";
	static constexpr const char *STATUS_INVALID_QUERY = "invalid_query";

	static constexpr const char *FAILURE_NONE = "none";
	static constexpr const char *FAILURE_NAV_MAP_MISSING = "nav_map_missing";
	static constexpr const char *FAILURE_GOAL_MISSING = "goal_missing";
	static constexpr const char *FAILURE_PASS_MASK_MISSING = "pass_mask_missing";
	static constexpr const char *FAILURE_MAP_TOO_LARGE = "map_too_large";
	static constexpr const char *FAILURE_START_OUT_OF_BOUNDS = "start_out_of_bounds";
	static constexpr const char *FAILURE_START_BLOCKED = "start_blocked";
	static constexpr const char *FAILURE_GOAL_OUT_OF_BOUNDS = "goal_out_of_bounds";
	static constexpr const char *FAILURE_GOAL_BLOCKED = "goal_blocked";
	static constexpr const char *FAILURE_NO_ROUTE = "no_route";

	String status = STATUS_INVALID_QUERY;
	String failure_reason = FAILURE_NONE;
	String canonicalization_reason = ReachabilityData::FAILURE_NONE;
	int32_t pass_mask = 0;
	String passability_class_name;
	Vector2 start_world;
	Vector2 effective_start_world;
	Vector2i start_navcell = Vector2i(-1, -1);
	Vector2i effective_start_navcell = Vector2i(-1, -1);
	Vector2i canonical_navcell = Vector2i(-1, -1);
	bool has_query_goal = false;
	PathGoal query_goal;
	bool has_canonical_goal = false;
	PathGoal canonical_goal;
	bool canonicalized = false;
	bool start_recovered = false;
	bool has_reachability = false;
	ReachabilityData reachability;
	std::vector<ExcludedRegion> excluded_regions;
	String post_process = LongPathQuery::POST_PROCESS_RAW;
	double waypoint_spacing = 0.0;
	std::vector<Vector2i> raw_navcell_path; // start-to-goal
	std::vector<Vector2> raw_waypoint_path; // reverse-consumption order
	std::vector<Vector2> refined_waypoint_path; // reverse-consumption order ("path")
	int64_t path_cost = 0;
	double path_length = 0.0;
	SearchDiagnostics search;

	void configure_query(const LongPathQuery &p_query, const CoreMap *p_map);
	void set_failure(const String &p_status, const String &p_reason);
	void set_paths(const String &p_status, std::vector<Vector2i> &&p_raw_cells, std::vector<Vector2> &&p_raw_path, std::vector<Vector2> &&p_refined_path, int64_t p_cost);
	bool is_success() const;
	bool has_path() const { return !refined_waypoint_path.empty(); }
};

class LongPathfinder {
public:
	static constexpr int64_t COST_HV = 65536;
	static constexpr int64_t COST_DIAG = 92682;
	static constexpr int64_t PACK_LIMIT = 65536;

	void setup(const CoreMap *p_map) { map = p_map; }
	// Frozen = a background batch is in flight: every table access must be a
	// pure read. Lazy build/repair paths are refused (loud error) instead of
	// mutating shared state under a concurrent reader.
	void set_frozen(bool p_frozen) { frozen = p_frozen; }
	bool is_frozen() const { return frozen; }
	LongPathResult compute_path_result(const LongPathQuery &p_query);
	void invalidate_jump_point_cache() { caches.clear(); }
	void prewarm_jump_point_cache(int32_t p_pass_mask);
	// Dirty-flush entry: repair every built cache for the currently-dirty
	// navcells (must run before the dirty flags are cleared).
	void repair_jump_point_caches();
	bool movement_raster_clear(const Vector2 &p_a, const Vector2 &p_b, int32_t p_pass_mask);
	// Fresh (repaired-if-needed) tables for a mask — shared with the facade's
	// segment fast path.
	JumpTables &tables_for(int32_t p_pass_mask);
	bool has_tables(int32_t p_pass_mask) const { return caches.count(p_pass_mask) > 0; }

private:
	struct JumpHit {
		enum Kind { NONE, GOAL, JUMP, OBSTRUCTION, BOUNDARY };
		int Kind_value = NONE;
		Vector2i cell;
		int32_t steps = 0;
	};

	const CoreMap *map = nullptr;
	std::unordered_map<int32_t, JumpTables> caches;
	bool frozen = false;

	// Read-only variant of tables_for: returns nullptr (with an error)
	// whenever serving the mask would mutate the cache.
	const JumpTables *_tables_for_frozen(int32_t p_pass_mask) const;

	using HeapKey = std::array<int64_t, 5>;

	static int64_t _pack_cell(const Vector2i &p_cell) { return (int64_t)p_cell.x * PACK_LIMIT + p_cell.y; }
	static Vector2i _cell_from_pack(int64_t p_packed) { return Vector2i((int)(p_packed / PACK_LIMIT), (int)(p_packed % PACK_LIMIT)); }
	static bool _key_less(const HeapKey &p_a, const HeapKey &p_b);
	static void _heap_insert(std::vector<HeapKey> &p_arr, const HeapKey &p_key);

	void _repair_cache_for_current_dirty(JumpTables &p_tables);
	bool _is_passable(const Vector2i &p_cell, int32_t p_pass_mask) const;
	bool _is_passable_with_exclusions(const Vector2i &p_cell, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded) const;
	bool _is_cell_excluded(const Vector2i &p_cell, const std::vector<ExcludedRegion> &p_excluded) const;
	bool _can_step(const Vector2i &p_from, const Vector2i &p_to, const Vector2i &p_direction, int32_t p_pass_mask) const;
	bool _can_step_with_exclusions(const Vector2i &p_from, const Vector2i &p_to, const Vector2i &p_direction, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded) const;
	int64_t _heuristic(const Vector2i &p_cell, const PathGoal &p_goal) const;
	static int64_t _octile_cost(const Vector2i &p_a, const Vector2i &p_b);
	static int64_t _movement_cost(const Vector2i &p_from, const Vector2i &p_to);

	std::vector<Vector2i> _jps_cells(const Vector2i &p_start, const PathGoal &p_goal, int32_t p_pass_mask, SearchDiagnostics &p_diag);
	int _successor_directions(const Vector2i &p_current, int64_t p_current_pack, int64_t p_start_pack, const std::unordered_map<int64_t, int64_t> &p_came_from, int32_t p_pass_mask, Vector2i *r_result) const;
	JumpHit _find_hit(const JumpTables &p_tables, const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal) const;
	Vector2i _jump(const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal, int32_t p_pass_mask, const JumpTables &p_tables) const;
	Vector2i _jump_cardinal(const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal, int32_t p_pass_mask, const JumpTables &p_tables) const;
	Vector2i _jump_diagonal(const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal, int32_t p_pass_mask, const JumpTables &p_tables) const;
	std::vector<Vector2i> _astar_cells(const Vector2i &p_start, const PathGoal &p_goal, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded, SearchDiagnostics &p_diag);
	static std::vector<Vector2i> _reconstruct_cells(const std::unordered_map<int64_t, int64_t> &p_came_from, int64_t p_start_pack, int64_t p_goal_pack);
	static std::vector<Vector2i> _expand_sparse_navcell_path(const std::vector<Vector2i> &p_cells);
	static void _expand_navcell_segment(const Vector2i &p_from, const Vector2i &p_to, std::vector<Vector2i> &r_segment);
	std::vector<Vector2> _waypoint_path_from_cells(const std::vector<Vector2i> &p_cells, const PathGoal &p_goal) const;
	// Returns the tables for a mask honoring the frozen contract, or nullptr
	// when the mask cannot be served without mutation while frozen.
	const JumpTables *_tables_for_query(int32_t p_pass_mask);
	std::vector<Vector2> _refine_waypoint_path(const std::vector<Vector2> &p_raw_path, const LongPathQuery &p_query, const String &p_post_process, double p_spacing, const JumpTables *p_segment_tables);
	std::vector<Vector2> _compress_execution_points(const Vector2 &p_start_world, const std::vector<Vector2> &p_points, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded, const JumpTables *p_segment_tables) const;
	static std::vector<Vector2> _apply_waypoint_spacing(const Vector2 &p_start_world, const std::vector<Vector2> &p_points, double p_spacing);
	bool _segment_passable_clear(const Vector2 &p_a, const Vector2 &p_b, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded, const JumpTables *p_segment_tables) const;
	static int64_t _path_cost_for_cells(const std::vector<Vector2i> &p_cells);
	static String _normalized_post_process(const String &p_post_process);
	static double _effective_waypoint_spacing(const LongPathQuery &p_query);
};

} // namespace simnav
