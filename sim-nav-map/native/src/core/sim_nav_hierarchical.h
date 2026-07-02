#pragma once

// Pure-C++ twin of pathfinding/sim_nav_hierarchical_pathfinder.gd (+ chunk +
// region-id helper). BFS expansion order, ring-scan order, and global-region
// numbering are kept identical — region ids are part of the A/B weld.

#include <map>
#include <unordered_map>
#include <vector>

#include "sim_nav_core_map.h"
#include "sim_nav_path_goal.h"

namespace simnav {

// Twin: SimNavReachabilityResult (field DTO; failure-reason strings match).
struct ReachabilityData {
	static constexpr const char *FAILURE_NONE = "none";
	static constexpr const char *FAILURE_NOT_RECOMPUTED = "not_recomputed";
	static constexpr const char *FAILURE_INVALID_QUERY = "invalid_query";
	static constexpr const char *FAILURE_NO_START_REGION = "no_start_region";
	static constexpr const char *FAILURE_ORIGINAL_GOAL_UNREACHABLE = "original_goal_unreachable";
	static constexpr const char *FAILURE_NO_REACHABLE_GOAL = "no_reachable_goal";

	bool is_reachable = false;
	bool canonicalized = false;
	String failure_reason = FAILURE_NONE;
	int32_t pass_mask = 0;
	String passability_class_name;
	Vector2i start_navcell = Vector2i(-1, -1);
	Vector2i effective_start_navcell = Vector2i(-1, -1);
	Vector2i canonical_navcell = Vector2i(-1, -1);
	int32_t start_global_region = 0;
	int32_t canonical_global_region = 0;
	bool has_query_goal = false;
	PathGoal query_goal;
	bool has_canonical_goal = false;
	PathGoal canonical_goal;

	bool is_failure() const { return failure_reason != String(FAILURE_NONE) && !has_canonical_goal; }
	void set_failure(const String &p_reason);
	void set_reachable(const PathGoal &p_goal, const Vector2i &p_navcell, int32_t p_start_global, int32_t p_canonical_global);
	void set_canonicalized(const PathGoal &p_goal, const Vector2i &p_navcell, int32_t p_start_global, int32_t p_canonical_global);
};

class Hierarchical {
public:
	static constexpr int CHUNK_SIZE = 96; // SimNavHierarchicalChunk.CHUNK_SIZE
	static constexpr int MAX_NEAREST_RADIUS = 256;
	static constexpr int FAST_NEAREST_RADIUS = 8;
	// Twin: SimNavRegionIdHelper packing.
	static constexpr int CI_SHIFT = 40;
	static constexpr int CJ_SHIFT = 16;
	static constexpr int64_t R_MASK = (1 << 16) - 1;

	struct Chunk {
		int ci = 0;
		int cj = 0;
		std::vector<int32_t> regions_id;
		std::vector<int32_t> regions;

		int32_t get_region(int p_li, int p_lj) const { return regions[(size_t)p_lj * CHUNK_SIZE + p_li]; }
	};

	void recompute(const CoreMap &p_map, const std::vector<int32_t> &p_masks);
	int recompute_dirty(const CoreMap &p_map, const std::vector<int32_t> &p_masks);
	bool is_recomputed() const { return recomputed && chunks_w > 0; }

	int64_t get_region(const CoreMap &p_map, const Vector2i &p_coord, int32_t p_pass_mask) const;
	int32_t get_global_region(const CoreMap &p_map, const Vector2i &p_coord, int32_t p_pass_mask) const;
	bool is_navcell_reachable(const CoreMap &p_map, const Vector2i &p_start, const Vector2i &p_goal, int32_t p_pass_mask) const;
	ReachabilityData query_goal_reachability(const CoreMap &p_map, const Vector2i &p_start, const PathGoal &p_goal, int32_t p_pass_mask, const String &p_class_name) const;
	Vector2i make_goal_reachable_navcell(const CoreMap &p_map, const Vector2i &p_start, const Vector2i &p_goal, int32_t p_pass_mask) const;
	Vector2i find_nearest_passable_navcell(const CoreMap &p_map, const Vector2i &p_start, int32_t p_pass_mask) const;
	// Weld/test export: full global-region grid for one mask.
	void export_connectivity(const CoreMap &p_map, int32_t p_pass_mask, std::vector<int32_t> &r_regions, int &r_global_region_count) const;
	int chunks_width() const { return chunks_w; }
	int chunks_height() const { return chunks_h; }

private:
	int chunks_w = 0;
	int chunks_h = 0;
	bool recomputed = false;
	std::unordered_map<int32_t, std::vector<Chunk>> chunks;
	// Values kept sorted-unique (twin: bsearch-insert Arrays).
	std::unordered_map<int32_t, std::unordered_map<int64_t, std::vector<int64_t>>> edges;
	std::unordered_map<int32_t, std::unordered_map<int64_t, int32_t>> global_regions;
	std::unordered_map<int32_t, int32_t> next_global_region;

	static int64_t _pack_region(int p_ci, int p_cj, int32_t p_r) {
		return ((int64_t)p_ci << CI_SHIFT) | ((int64_t)p_cj << CJ_SHIFT) | p_r;
	}
	static bool _region_invalid(int64_t p_rid) { return (p_rid & R_MASK) == 0; }

	Chunk _build_chunk(const CoreMap &p_map, int p_ci, int p_cj, int32_t p_pass_mask) const;
	static void _flood_fill_chunk(const std::vector<int32_t> &p_window, std::vector<int32_t> &p_regions, std::vector<int32_t> &p_queue, int p_start_idx, int32_t p_local_region, int32_t p_pass_mask);
	void _build_edges(int32_t p_pass_mask, const std::vector<Chunk> &p_chunks);
	static void _add_pair_if_passable(const Chunk &p_a, const Chunk &p_b, int32_t p_region_a, int32_t p_region_b, std::unordered_map<int64_t, std::vector<int64_t>> &p_edges);
	static void _insert_sorted_unique(std::unordered_map<int64_t, std::vector<int64_t>> &p_edges, int64_t p_key, int64_t p_value);
	void _compute_global_regions(int32_t p_pass_mask);

	Vector2i _find_nearest_in_global_region(const CoreMap &p_map, const Vector2i &p_start, int32_t p_target_global, int32_t p_pass_mask) const;
	Vector2i _find_nearest_goal_navcell(const CoreMap &p_map, const Vector2i &p_start, const PathGoal &p_goal, int32_t p_target_global, int32_t p_pass_mask) const;
	Vector2i _scan_ring_for_passable(const CoreMap &p_map, const Vector2i &p_center, int p_radius, int32_t p_pass_mask) const;
	Vector2i _scan_ring_for_global(const CoreMap &p_map, const Vector2i &p_center, int p_radius, int32_t p_pass_mask, int32_t p_target_global) const;
	Vector2i _scan_ring_for_goal_global(const CoreMap &p_map, const Vector2i &p_center, int p_radius, int32_t p_pass_mask, int32_t p_target_global, const PathGoal &p_goal) const;
	Vector2i _find_nearest_in_global_region_via_graph(const CoreMap &p_map, const Vector2i &p_anchor, int32_t p_target_global, int32_t p_pass_mask) const;
	Vector2i _find_nearest_in_any_region(const CoreMap &p_map, const Vector2i &p_anchor, int32_t p_pass_mask) const;
	int _goal_navcell_search_radius(const CoreMap &p_map, const PathGoal &p_goal) const;
};

} // namespace simnav
