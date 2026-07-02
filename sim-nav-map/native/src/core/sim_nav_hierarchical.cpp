#include "sim_nav_hierarchical.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <set>

#include <godot_cpp/core/error_macros.hpp>

namespace simnav {

// ── ReachabilityData ─────────────────────────────────────────────────────────

void ReachabilityData::set_failure(const String &p_reason) {
	failure_reason = p_reason;
	is_reachable = false;
	canonicalized = false;
	has_canonical_goal = false;
	canonical_navcell = Vector2i(-1, -1);
	canonical_global_region = 0;
}

void ReachabilityData::set_reachable(const PathGoal &p_goal, const Vector2i &p_navcell, int32_t p_start_global, int32_t p_canonical_global) {
	is_reachable = true;
	canonicalized = false;
	failure_reason = FAILURE_NONE;
	has_canonical_goal = true;
	canonical_goal = p_goal;
	canonical_navcell = p_navcell;
	start_global_region = p_start_global;
	canonical_global_region = p_canonical_global;
}

void ReachabilityData::set_canonicalized(const PathGoal &p_goal, const Vector2i &p_navcell, int32_t p_start_global, int32_t p_canonical_global) {
	is_reachable = false;
	canonicalized = true;
	failure_reason = FAILURE_ORIGINAL_GOAL_UNREACHABLE;
	has_canonical_goal = true;
	canonical_goal = p_goal;
	canonical_navcell = p_navcell;
	start_global_region = p_start_global;
	canonical_global_region = p_canonical_global;
}

// ── Rebuild ──────────────────────────────────────────────────────────────────

void Hierarchical::recompute(const CoreMap &p_map, const std::vector<int32_t> &p_masks) {
	chunks_w = (p_map.width + CHUNK_SIZE - 1) / CHUNK_SIZE;
	chunks_h = (p_map.height + CHUNK_SIZE - 1) / CHUNK_SIZE;
	chunks.clear();
	edges.clear();
	global_regions.clear();
	next_global_region.clear();
	recomputed = true;

	for (int32_t pass_mask : p_masks) {
		if (pass_mask == 0) {
			ERR_PRINT("[SimNavNativeFacade] recompute: pass_mask 0 is invalid");
			continue;
		}
		std::vector<Chunk> mask_chunks;
		mask_chunks.resize((size_t)chunks_w * chunks_h);
		for (int cj = 0; cj < chunks_h; cj++) {
			for (int ci = 0; ci < chunks_w; ci++) {
				mask_chunks[(size_t)cj * chunks_w + ci] = _build_chunk(p_map, ci, cj, pass_mask);
			}
		}
		_build_edges(pass_mask, mask_chunks);
		chunks[pass_mask] = std::move(mask_chunks);
		_compute_global_regions(pass_mask);
	}
}

int Hierarchical::recompute_dirty(const CoreMap &p_map, const std::vector<int32_t> &p_masks) {
	int expected_chunks_w = (p_map.width + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int expected_chunks_h = (p_map.height + CHUNK_SIZE - 1) / CHUNK_SIZE;
	if (!is_recomputed() || chunks_w != expected_chunks_w || chunks_h != expected_chunks_h) {
		recompute(p_map, p_masks);
		return expected_chunks_w * expected_chunks_h;
	}

	std::vector<Vector2i> dirty_cells;
	p_map.collect_dirty_navcells(dirty_cells);
	std::set<std::pair<int, int>> dirty_chunks;
	for (const Vector2i &coord : dirty_cells) {
		int ci = coord.x / CHUNK_SIZE;
		int cj = coord.y / CHUNK_SIZE;
		if (ci >= 0 && cj >= 0 && ci < chunks_w && cj < chunks_h) {
			dirty_chunks.insert({ ci, cj });
		}
	}
	if (dirty_chunks.empty()) {
		return 0;
	}

	for (int32_t pass_mask : p_masks) {
		if (pass_mask == 0) {
			ERR_PRINT("[SimNavNativeFacade] recompute_dirty: pass_mask 0 is invalid");
			continue;
		}
		auto found = chunks.find(pass_mask);
		if (found == chunks.end() || found->second.size() != (size_t)chunks_w * chunks_h) {
			recompute(p_map, p_masks);
			return expected_chunks_w * expected_chunks_h;
		}
		std::vector<Chunk> &mask_chunks = found->second;
		for (const auto &chunk_coord : dirty_chunks) {
			mask_chunks[(size_t)chunk_coord.second * chunks_w + chunk_coord.first] =
					_build_chunk(p_map, chunk_coord.first, chunk_coord.second, pass_mask);
		}
		_build_edges(pass_mask, mask_chunks);
		_compute_global_regions(pass_mask);
	}
	return (int)dirty_chunks.size();
}

Hierarchical::Chunk Hierarchical::_build_chunk(const CoreMap &p_map, int p_ci, int p_cj, int32_t p_pass_mask) const {
	Chunk chunk;
	chunk.ci = p_ci;
	chunk.cj = p_cj;
	std::vector<int32_t> window;
	p_map.composed_navcell_data_rect(
			Vector2i(p_ci * CHUNK_SIZE, p_cj * CHUNK_SIZE),
			Vector2i(CHUNK_SIZE, CHUNK_SIZE), window);
	std::vector<int32_t> regions((size_t)CHUNK_SIZE * CHUNK_SIZE, 0);
	std::vector<int32_t> queue;
	int32_t next_local_region = 1;
	for (int idx = 0; idx < CHUNK_SIZE * CHUNK_SIZE; idx++) {
		if (regions[(size_t)idx] != 0) {
			continue;
		}
		if ((window[(size_t)idx] & p_pass_mask) != 0) {
			continue;
		}
		_flood_fill_chunk(window, regions, queue, idx, next_local_region, p_pass_mask);
		chunk.regions_id.push_back(next_local_region);
		next_local_region += 1;
	}
	chunk.regions = std::move(regions);
	return chunk;
}

void Hierarchical::_flood_fill_chunk(const std::vector<int32_t> &p_window, std::vector<int32_t> &p_regions, std::vector<int32_t> &p_queue, int p_start_idx, int32_t p_local_region, int32_t p_pass_mask) {
	p_queue.clear();
	p_queue.push_back(p_start_idx);
	size_t head = 0;
	// Neighbors in (+x, -x, +y, -y) order — region numbering is bit-identical
	// to the GDScript twin.
	while (head < p_queue.size()) {
		int idx = p_queue[head];
		head += 1;
		if (p_regions[(size_t)idx] != 0) {
			continue;
		}
		p_regions[(size_t)idx] = p_local_region;
		int local_i = idx % CHUNK_SIZE;
		int local_j = idx / CHUNK_SIZE;
		if (local_i + 1 < CHUNK_SIZE) {
			int east = idx + 1;
			if ((p_window[(size_t)east] & p_pass_mask) == 0 && p_regions[(size_t)east] == 0) {
				p_queue.push_back(east);
			}
		}
		if (local_i > 0) {
			int west = idx - 1;
			if ((p_window[(size_t)west] & p_pass_mask) == 0 && p_regions[(size_t)west] == 0) {
				p_queue.push_back(west);
			}
		}
		if (local_j + 1 < CHUNK_SIZE) {
			int south = idx + CHUNK_SIZE;
			if ((p_window[(size_t)south] & p_pass_mask) == 0 && p_regions[(size_t)south] == 0) {
				p_queue.push_back(south);
			}
		}
		if (local_j > 0) {
			int north = idx - CHUNK_SIZE;
			if ((p_window[(size_t)north] & p_pass_mask) == 0 && p_regions[(size_t)north] == 0) {
				p_queue.push_back(north);
			}
		}
	}
}

void Hierarchical::_build_edges(int32_t p_pass_mask, const std::vector<Chunk> &p_chunks) {
	std::unordered_map<int64_t, std::vector<int64_t>> mask_edges;
	for (int cj = 0; cj < chunks_h; cj++) {
		for (int ci = 0; ci < chunks_w; ci++) {
			const Chunk &chunk = p_chunks[(size_t)cj * chunks_w + ci];
			if (ci + 1 < chunks_w) {
				const Chunk &right = p_chunks[(size_t)cj * chunks_w + ci + 1];
				for (int local_j = 0; local_j < CHUNK_SIZE; local_j++) {
					_add_pair_if_passable(
							chunk, right,
							chunk.regions[(size_t)local_j * CHUNK_SIZE + CHUNK_SIZE - 1],
							right.regions[(size_t)local_j * CHUNK_SIZE],
							mask_edges);
				}
			}
			if (cj + 1 < chunks_h) {
				const Chunk &bottom = p_chunks[(size_t)(cj + 1) * chunks_w + ci];
				const int last_row = (CHUNK_SIZE - 1) * CHUNK_SIZE;
				for (int local_i = 0; local_i < CHUNK_SIZE; local_i++) {
					_add_pair_if_passable(
							chunk, bottom,
							chunk.regions[(size_t)last_row + local_i],
							bottom.regions[(size_t)local_i],
							mask_edges);
				}
			}
		}
	}
	edges[p_pass_mask] = std::move(mask_edges);
}

void Hierarchical::_add_pair_if_passable(const Chunk &p_a, const Chunk &p_b, int32_t p_region_a, int32_t p_region_b, std::unordered_map<int64_t, std::vector<int64_t>> &p_edges) {
	if (p_region_a == 0 || p_region_b == 0) {
		return;
	}
	int64_t a = _pack_region(p_a.ci, p_a.cj, p_region_a);
	int64_t b = _pack_region(p_b.ci, p_b.cj, p_region_b);
	if (a == b) {
		return;
	}
	_insert_sorted_unique(p_edges, a, b);
	_insert_sorted_unique(p_edges, b, a);
}

void Hierarchical::_insert_sorted_unique(std::unordered_map<int64_t, std::vector<int64_t>> &p_edges, int64_t p_key, int64_t p_value) {
	std::vector<int64_t> &arr = p_edges[p_key];
	auto pos = std::lower_bound(arr.begin(), arr.end(), p_value);
	if (pos != arr.end() && *pos == p_value) {
		return;
	}
	arr.insert(pos, p_value);
}

void Hierarchical::_compute_global_regions(int32_t p_pass_mask) {
	const auto &mask_edges = edges[p_pass_mask];
	const auto &mask_chunks = chunks[p_pass_mask];
	std::vector<int64_t> all_region_ids;
	for (const Chunk &chunk : mask_chunks) {
		for (int32_t local_region : chunk.regions_id) {
			all_region_ids.push_back(_pack_region(chunk.ci, chunk.cj, local_region));
		}
	}
	std::sort(all_region_ids.begin(), all_region_ids.end());

	std::unordered_map<int64_t, int32_t> global;
	int32_t next_global = 1;
	std::vector<int64_t> queue;
	for (int64_t rid : all_region_ids) {
		if (global.count(rid)) {
			continue;
		}
		queue.clear();
		queue.push_back(rid);
		size_t head = 0;
		while (head < queue.size()) {
			int64_t current = queue[head];
			head += 1;
			if (global.count(current)) {
				continue;
			}
			global[current] = next_global;
			auto found = mask_edges.find(current);
			if (found != mask_edges.end()) {
				for (int64_t neighbor : found->second) {
					if (!global.count(neighbor)) {
						queue.push_back(neighbor);
					}
				}
			}
		}
		next_global += 1;
	}
	global_regions[p_pass_mask] = std::move(global);
	next_global_region[p_pass_mask] = next_global;
}

// ── Queries ──────────────────────────────────────────────────────────────────

int64_t Hierarchical::get_region(const CoreMap &p_map, const Vector2i &p_coord, int32_t p_pass_mask) const {
	if (!p_map.is_valid_navcell(p_coord)) {
		return 0; // SimNavRegionIdHelper.INVALID
	}
	int ci = p_coord.x / CHUNK_SIZE;
	int cj = p_coord.y / CHUNK_SIZE;
	if (ci < 0 || cj < 0 || ci >= chunks_w || cj >= chunks_h) {
		return 0;
	}
	auto found = chunks.find(p_pass_mask);
	if (found == chunks.end() || found->second.empty()) {
		return 0;
	}
	const Chunk &chunk = found->second[(size_t)cj * chunks_w + ci];
	int local_i = p_coord.x % CHUNK_SIZE;
	int local_j = p_coord.y % CHUNK_SIZE;
	int32_t local_r = chunk.get_region(local_i, local_j);
	if (local_r == 0) {
		return 0;
	}
	return _pack_region(ci, cj, local_r);
}

int32_t Hierarchical::get_global_region(const CoreMap &p_map, const Vector2i &p_coord, int32_t p_pass_mask) const {
	int64_t rid = get_region(p_map, p_coord, p_pass_mask);
	if (_region_invalid(rid)) {
		return 0;
	}
	auto mask_found = global_regions.find(p_pass_mask);
	if (mask_found == global_regions.end()) {
		return 0;
	}
	auto found = mask_found->second.find(rid);
	return found == mask_found->second.end() ? 0 : found->second;
}

bool Hierarchical::is_navcell_reachable(const CoreMap &p_map, const Vector2i &p_start, const Vector2i &p_goal, int32_t p_pass_mask) const {
	int32_t start_global = get_global_region(p_map, p_start, p_pass_mask);
	if (start_global == 0) {
		return false;
	}
	return get_global_region(p_map, p_goal, p_pass_mask) == start_global;
}

ReachabilityData Hierarchical::query_goal_reachability(const CoreMap &p_map, const Vector2i &p_start, const PathGoal &p_goal, int32_t p_pass_mask, const String &p_class_name) const {
	ReachabilityData result;
	result.start_navcell = p_start;
	result.effective_start_navcell = p_start;
	result.pass_mask = p_pass_mask;
	result.passability_class_name = p_class_name;
	result.has_query_goal = true;
	result.query_goal = p_goal;
	if (!is_recomputed() || !chunks.count(p_pass_mask)) {
		result.set_failure(ReachabilityData::FAILURE_NOT_RECOMPUTED);
		return result;
	}
	if (p_pass_mask == 0) {
		result.set_failure(ReachabilityData::FAILURE_INVALID_QUERY);
		return result;
	}

	Vector2i effective_start = p_start;
	int32_t start_global = get_global_region(p_map, effective_start, p_pass_mask);
	if (start_global == 0) {
		effective_start = find_nearest_passable_navcell(p_map, p_start, p_pass_mask);
		if (effective_start == Vector2i(-1, -1)) {
			result.set_failure(ReachabilityData::FAILURE_NO_START_REGION);
			return result;
		}
		start_global = get_global_region(p_map, effective_start, p_pass_mask);
		if (start_global == 0) {
			result.set_failure(ReachabilityData::FAILURE_NO_START_REGION);
			return result;
		}
	}
	result.effective_start_navcell = effective_start;
	result.start_global_region = start_global;

	Vector2i anchor = p_map.world_to_navcell(p_goal.center);
	Vector2i reachable_goal = _find_nearest_goal_navcell(p_map, anchor, p_goal, start_global, p_pass_mask);
	if (reachable_goal != Vector2i(-1, -1)) {
		result.set_reachable(p_goal, reachable_goal, start_global, get_global_region(p_map, reachable_goal, p_pass_mask));
		return result;
	}

	Vector2i fallback = _find_nearest_in_global_region(p_map, anchor, start_global, p_pass_mask);
	if (fallback == Vector2i(-1, -1)) {
		result.set_failure(ReachabilityData::FAILURE_NO_REACHABLE_GOAL);
		result.start_global_region = start_global;
		result.effective_start_navcell = effective_start;
		return result;
	}

	result.set_canonicalized(
			PathGoal::point(p_map.navcell_center_world(fallback)),
			fallback,
			start_global,
			get_global_region(p_map, fallback, p_pass_mask));
	return result;
}

Vector2i Hierarchical::make_goal_reachable_navcell(const CoreMap &p_map, const Vector2i &p_start, const Vector2i &p_goal, int32_t p_pass_mask) const {
	ReachabilityData result = query_goal_reachability(
			p_map, p_start, PathGoal::point(p_map.navcell_center_world(p_goal)), p_pass_mask, String());
	if (result.has_canonical_goal) {
		return result.canonical_navcell;
	}
	return p_goal;
}

Vector2i Hierarchical::find_nearest_passable_navcell(const CoreMap &p_map, const Vector2i &p_start, int32_t p_pass_mask) const {
	if (p_map.is_passable_navcell(p_start, p_pass_mask)) {
		return p_start;
	}
	for (int radius = 1; radius <= FAST_NEAREST_RADIUS; radius++) {
		Vector2i found = _scan_ring_for_passable(p_map, p_start, radius, p_pass_mask);
		if (found != Vector2i(-1, -1)) {
			return found;
		}
	}
	return _find_nearest_in_any_region(p_map, p_start, p_pass_mask);
}

void Hierarchical::export_connectivity(const CoreMap &p_map, int32_t p_pass_mask, std::vector<int32_t> &r_regions, int &r_global_region_count) const {
	r_regions.clear();
	r_global_region_count = 0;
	if (!is_recomputed() || !chunks.count(p_pass_mask)) {
		return;
	}
	r_regions.resize((size_t)p_map.width * p_map.height);
	for (int y = 0; y < p_map.height; y++) {
		for (int x = 0; x < p_map.width; x++) {
			r_regions[(size_t)y * p_map.width + x] = get_global_region(p_map, Vector2i(x, y), p_pass_mask);
		}
	}
	auto found = next_global_region.find(p_pass_mask);
	int next = found == next_global_region.end() ? 1 : found->second;
	r_global_region_count = std::max(0, next - 1);
}

// ── Nearest scans ────────────────────────────────────────────────────────────

Vector2i Hierarchical::_find_nearest_in_global_region(const CoreMap &p_map, const Vector2i &p_start, int32_t p_target_global, int32_t p_pass_mask) const {
	if (p_target_global == 0) {
		return Vector2i(-1, -1);
	}
	if (get_global_region(p_map, p_start, p_pass_mask) == p_target_global) {
		return p_start;
	}
	for (int radius = 1; radius <= FAST_NEAREST_RADIUS; radius++) {
		Vector2i found = _scan_ring_for_global(p_map, p_start, radius, p_pass_mask, p_target_global);
		if (found != Vector2i(-1, -1)) {
			return found;
		}
	}
	return _find_nearest_in_global_region_via_graph(p_map, p_start, p_target_global, p_pass_mask);
}

Vector2i Hierarchical::_find_nearest_goal_navcell(const CoreMap &p_map, const Vector2i &p_start, const PathGoal &p_goal, int32_t p_target_global, int32_t p_pass_mask) const {
	if (p_target_global == 0) {
		return Vector2i(-1, -1);
	}
	if (p_goal.type == PathGoal::POINT) {
		if (get_global_region(p_map, p_start, p_pass_mask) == p_target_global) {
			return p_start;
		}
		return Vector2i(-1, -1);
	}
	if (p_goal.navcell_contains_goal(p_map, p_start) && get_global_region(p_map, p_start, p_pass_mask) == p_target_global) {
		return p_start;
	}
	int max_radius = _goal_navcell_search_radius(p_map, p_goal);
	for (int radius = 1; radius <= max_radius; radius++) {
		Vector2i found = _scan_ring_for_goal_global(p_map, p_start, radius, p_pass_mask, p_target_global, p_goal);
		if (found != Vector2i(-1, -1)) {
			return found;
		}
	}
	return Vector2i(-1, -1);
}

Vector2i Hierarchical::_scan_ring_for_passable(const CoreMap &p_map, const Vector2i &p_center, int p_radius, int32_t p_pass_mask) const {
	for (int dx = -p_radius; dx <= p_radius; dx++) {
		for (int dy = -p_radius; dy <= p_radius; dy++) {
			if (std::max(std::abs(dx), std::abs(dy)) != p_radius) {
				continue;
			}
			Vector2i coord(p_center.x + dx, p_center.y + dy);
			if (p_map.is_passable_navcell(coord, p_pass_mask)) {
				return coord;
			}
		}
	}
	return Vector2i(-1, -1);
}

Vector2i Hierarchical::_scan_ring_for_global(const CoreMap &p_map, const Vector2i &p_center, int p_radius, int32_t p_pass_mask, int32_t p_target_global) const {
	for (int dx = -p_radius; dx <= p_radius; dx++) {
		for (int dy = -p_radius; dy <= p_radius; dy++) {
			if (std::max(std::abs(dx), std::abs(dy)) != p_radius) {
				continue;
			}
			Vector2i coord(p_center.x + dx, p_center.y + dy);
			if (get_global_region(p_map, coord, p_pass_mask) == p_target_global) {
				return coord;
			}
		}
	}
	return Vector2i(-1, -1);
}

Vector2i Hierarchical::_scan_ring_for_goal_global(const CoreMap &p_map, const Vector2i &p_center, int p_radius, int32_t p_pass_mask, int32_t p_target_global, const PathGoal &p_goal) const {
	for (int dx = -p_radius; dx <= p_radius; dx++) {
		for (int dy = -p_radius; dy <= p_radius; dy++) {
			if (std::max(std::abs(dx), std::abs(dy)) != p_radius) {
				continue;
			}
			Vector2i coord(p_center.x + dx, p_center.y + dy);
			if (!p_goal.navcell_contains_goal(p_map, coord)) {
				continue;
			}
			if (get_global_region(p_map, coord, p_pass_mask) == p_target_global) {
				return coord;
			}
		}
	}
	return Vector2i(-1, -1);
}

Vector2i Hierarchical::_find_nearest_in_global_region_via_graph(const CoreMap &p_map, const Vector2i &p_anchor, int32_t p_target_global, int32_t p_pass_mask) const {
	auto chunks_found = chunks.find(p_pass_mask);
	if (chunks_found == chunks.end() || chunks_found->second.empty() || p_target_global == 0) {
		return Vector2i(-1, -1);
	}
	auto globals_found = global_regions.find(p_pass_mask);
	if (globals_found == global_regions.end() || globals_found->second.empty()) {
		return Vector2i(-1, -1);
	}
	const auto &globals_map = globals_found->second;
	Vector2i best_cell(-1, -1);
	double best_dist_sq = std::numeric_limits<double>::infinity();
	for (int cj = 0; cj < chunks_h; cj++) {
		for (int ci = 0; ci < chunks_w; ci++) {
			const Chunk &chunk = chunks_found->second[(size_t)cj * chunks_w + ci];
			for (int lj = 0; lj < CHUNK_SIZE; lj++) {
				int base_y = cj * CHUNK_SIZE + lj;
				if (base_y >= p_map.height) {
					break;
				}
				for (int li = 0; li < CHUNK_SIZE; li++) {
					int base_x = ci * CHUNK_SIZE + li;
					if (base_x >= p_map.width) {
						break;
					}
					int32_t local_r = chunk.get_region(li, lj);
					if (local_r == 0) {
						continue;
					}
					int64_t rid = _pack_region(ci, cj, local_r);
					auto global_found = globals_map.find(rid);
					if (global_found == globals_map.end() || global_found->second != p_target_global) {
						continue;
					}
					double dx = (double)(base_x - p_anchor.x);
					double dy = (double)(base_y - p_anchor.y);
					double d = dx * dx + dy * dy;
					if (d < best_dist_sq) {
						best_dist_sq = d;
						best_cell = Vector2i(base_x, base_y);
					}
				}
			}
		}
	}
	return best_cell;
}

Vector2i Hierarchical::_find_nearest_in_any_region(const CoreMap &p_map, const Vector2i &p_anchor, int32_t p_pass_mask) const {
	auto chunks_found = chunks.find(p_pass_mask);
	if (chunks_found == chunks.end() || chunks_found->second.empty()) {
		return Vector2i(-1, -1);
	}
	Vector2i best_cell(-1, -1);
	double best_dist_sq = std::numeric_limits<double>::infinity();
	for (int cj = 0; cj < chunks_h; cj++) {
		for (int ci = 0; ci < chunks_w; ci++) {
			const Chunk &chunk = chunks_found->second[(size_t)cj * chunks_w + ci];
			for (int lj = 0; lj < CHUNK_SIZE; lj++) {
				int base_y = cj * CHUNK_SIZE + lj;
				if (base_y >= p_map.height) {
					break;
				}
				for (int li = 0; li < CHUNK_SIZE; li++) {
					int base_x = ci * CHUNK_SIZE + li;
					if (base_x >= p_map.width) {
						break;
					}
					if (chunk.get_region(li, lj) == 0) {
						continue;
					}
					double dx = (double)(base_x - p_anchor.x);
					double dy = (double)(base_y - p_anchor.y);
					double d = dx * dx + dy * dy;
					if (d < best_dist_sq) {
						best_dist_sq = d;
						best_cell = Vector2i(base_x, base_y);
					}
				}
			}
		}
	}
	return best_cell;
}

int Hierarchical::_goal_navcell_search_radius(const CoreMap &p_map, const PathGoal &p_goal) const {
	double extent = 0.0;
	switch (p_goal.type) {
		case PathGoal::CIRCLE:
		case PathGoal::INVERTED_CIRCLE:
			extent = p_goal.hw;
			break;
		case PathGoal::SQUARE:
		case PathGoal::INVERTED_SQUARE:
			extent = p_goal.hw + p_goal.hh;
			break;
		default:
			return 0;
	}
	double cell_size = std::max(p_map.navcell_size, 0.001);
	return std::min(MAX_NEAREST_RADIUS, (int)std::ceil(extent / cell_size) + 2);
}

} // namespace simnav
