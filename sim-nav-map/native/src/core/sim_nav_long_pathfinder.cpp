#include "sim_nav_long_pathfinder.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace simnav {

using godot::real_t;

static const Vector2i DIRECTIONS[8] = {
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
};

// ── LongPathResult ───────────────────────────────────────────────────────────

void LongPathResult::configure_query(const LongPathQuery &p_query, const CoreMap *p_map) {
	start_world = p_query.start_world;
	effective_start_world = p_query.start_world;
	pass_mask = p_query.pass_mask;
	passability_class_name = p_query.passability_class_name;
	has_query_goal = p_query.has_goal;
	query_goal = p_query.goal;
	has_canonical_goal = p_query.has_goal;
	canonical_goal = p_query.goal;
	excluded_regions = p_query.excluded_regions;
	post_process = p_query.post_process;
	waypoint_spacing = p_query.waypoint_spacing;
	if (p_map != nullptr) {
		start_navcell = p_map->world_to_navcell(p_query.start_world);
		effective_start_navcell = start_navcell;
		if (p_query.has_goal) {
			canonical_navcell = p_map->world_to_navcell(p_query.goal.center);
		}
	}
}

void LongPathResult::set_failure(const String &p_status, const String &p_reason) {
	status = p_status;
	failure_reason = p_reason;
	refined_waypoint_path.clear();
	raw_waypoint_path.clear();
	raw_navcell_path.clear();
	path_cost = 0;
	path_length = 0.0;
}

void LongPathResult::set_paths(const String &p_status, std::vector<Vector2i> &&p_raw_cells, std::vector<Vector2> &&p_raw_path, std::vector<Vector2> &&p_refined_path, int64_t p_cost) {
	status = p_status;
	failure_reason = FAILURE_NONE;
	raw_navcell_path = std::move(p_raw_cells);
	raw_waypoint_path = std::move(p_raw_path);
	refined_waypoint_path = std::move(p_refined_path);
	path_cost = p_cost;
	// Twin: _measure_path_length — reverse-consumption iteration from the
	// effective start, double accumulator over float32 distances.
	path_length = 0.0;
	if (!refined_waypoint_path.empty()) {
		Vector2 previous = effective_start_world;
		for (int i = (int)refined_waypoint_path.size() - 1; i >= 0; i--) {
			const Vector2 &point = refined_waypoint_path[(size_t)i];
			path_length += (double)previous.distance_to(point);
			previous = point;
		}
	}
}

bool LongPathResult::is_success() const {
	return status == String(STATUS_SUCCESS) || status == String(STATUS_CANONICALIZED) ||
			status == String(STATUS_START_RECOVERED) || status == String(STATUS_DIRECT_GOAL);
}

// ── Heap (sorted-array twin of SimNavPathfinderHeap) ─────────────────────────

bool LongPathfinder::_key_less(const HeapKey &p_a, const HeapKey &p_b) {
	for (int i = 0; i < 5; i++) {
		if (p_a[i] < p_b[i]) {
			return true;
		}
		if (p_a[i] > p_b[i]) {
			return false;
		}
	}
	return false;
}

void LongPathfinder::_heap_insert(std::vector<HeapKey> &p_arr, const HeapKey &p_key) {
	auto pos = std::lower_bound(p_arr.begin(), p_arr.end(), p_key, _key_less);
	p_arr.insert(pos, p_key);
}

// ── Cache management (twin of _jump_point_cache / repair entries) ────────────

JumpTables &LongPathfinder::tables_for(int32_t p_pass_mask) {
	auto found = caches.find(p_pass_mask);
	if (found == caches.end()) {
		JumpTables fresh;
		fresh.reset(*map, p_pass_mask);
		return caches.emplace(p_pass_mask, std::move(fresh)).first->second;
	}
	JumpTables &tables = found->second;
	if (tables.is_dirty()) {
		tables.reset(*map, p_pass_mask);
	} else if (map->has_dirty_navcells()) {
		_repair_cache_for_current_dirty(tables);
	}
	return tables;
}

void LongPathfinder::_repair_cache_for_current_dirty(JumpTables &p_tables) {
	int64_t revision = map->dirty_navcell_revision();
	if (p_tables.repaired_dirty_revision == revision) {
		return;
	}
	std::vector<Vector2i> dirty_cells;
	map->collect_dirty_navcells(dirty_cells);
	p_tables.repair_dirty_cells(*map, dirty_cells);
	p_tables.repaired_dirty_revision = revision;
}

void LongPathfinder::prewarm_jump_point_cache(int32_t p_pass_mask) {
	if (map == nullptr || p_pass_mask == 0) {
		return;
	}
	tables_for(p_pass_mask);
}

void LongPathfinder::repair_jump_point_caches() {
	if (map == nullptr || !map->has_dirty_navcells()) {
		return;
	}
	for (auto &entry : caches) {
		_repair_cache_for_current_dirty(entry.second);
	}
}

bool LongPathfinder::movement_raster_clear(const Vector2 &p_a, const Vector2 &p_b, int32_t p_pass_mask) {
	if (map == nullptr || p_pass_mask == 0) {
		return false;
	}
	return tables_for(p_pass_mask).movement_line_clear(p_a, p_b);
}

// ── compute_path_result (twin control flow) ──────────────────────────────────

LongPathResult LongPathfinder::compute_path_result(const LongPathQuery &p_query) {
	LongPathResult result;
	result.configure_query(p_query, map);
	result.post_process = _normalized_post_process(p_query.post_process);
	result.waypoint_spacing = _effective_waypoint_spacing(p_query);

	if (map == nullptr) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_NAV_MAP_MISSING);
		return result;
	}
	if (!p_query.has_goal) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_GOAL_MISSING);
		return result;
	}
	if (p_query.pass_mask == 0) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_PASS_MASK_MISSING);
		return result;
	}
	if (map->width >= PACK_LIMIT || map->height >= PACK_LIMIT) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_MAP_TOO_LARGE);
		return result;
	}

	Vector2i start_cell = map->world_to_navcell(p_query.start_world);
	result.start_navcell = start_cell;
	result.effective_start_navcell = start_cell;
	result.effective_start_world = p_query.start_world;
	if (!map->is_valid_navcell(start_cell)) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_START_OUT_OF_BOUNDS);
		return result;
	}
	if (!map->is_inside_playable_bounds(p_query.start_world)) {
		result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_START_OUT_OF_BOUNDS);
		return result;
	}
	if (!_is_passable_with_exclusions(start_cell, p_query.pass_mask, p_query.excluded_regions)) {
		result.set_failure(LongPathResult::STATUS_INVALID_START, LongPathResult::FAILURE_START_BLOCKED);
		return result;
	}

	if (p_query.goal.type == PathGoal::POINT) {
		Vector2i goal_cell = map->world_to_navcell(p_query.goal.center);
		result.canonical_navcell = goal_cell;
		if (!map->is_valid_navcell(goal_cell)) {
			result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_GOAL_OUT_OF_BOUNDS);
			return result;
		}
		if (!map->is_inside_playable_bounds(p_query.goal.center)) {
			result.set_failure(LongPathResult::STATUS_INVALID_QUERY, LongPathResult::FAILURE_GOAL_OUT_OF_BOUNDS);
			return result;
		}
		if (!_is_passable_with_exclusions(goal_cell, p_query.pass_mask, p_query.excluded_regions)) {
			result.set_failure(LongPathResult::STATUS_UNREACHABLE, LongPathResult::FAILURE_GOAL_BLOCKED);
			return result;
		}
	}

	if (p_query.goal.navcell_contains_goal(*map, start_cell)) {
		std::vector<Vector2> direct_path;
		direct_path.push_back(p_query.goal.nearest_point_on_goal(p_query.start_world));
		std::vector<Vector2i> direct_cells = { start_cell };
		JumpTables *segment_tables = p_query.excluded_regions.empty() ? &tables_for(p_query.pass_mask) : nullptr;
		std::vector<Vector2> refined_direct = _refine_waypoint_path(direct_path, p_query, result.post_process, result.waypoint_spacing, segment_tables);
		result.search = SearchDiagnostics();
		result.search.algorithm = "direct";
		result.set_paths(LongPathResult::STATUS_DIRECT_GOAL, std::move(direct_cells), std::move(direct_path), std::move(refined_direct), 0);
		return result;
	}

	SearchDiagnostics diagnostics;
	diagnostics.algorithm = "jps";
	std::vector<Vector2i> raw_cells;
	std::vector<Vector2i> refinement_cells;
	if (p_query.excluded_regions.empty()) {
		std::vector<Vector2i> sparse_cells = _jps_cells(start_cell, p_query.goal, p_query.pass_mask, diagnostics);
		refinement_cells = sparse_cells;
		raw_cells = _expand_sparse_navcell_path(sparse_cells);
	} else {
		diagnostics = SearchDiagnostics();
		diagnostics.algorithm = "astar_excluded";
		raw_cells = _astar_cells(start_cell, p_query.goal, p_query.pass_mask, p_query.excluded_regions, diagnostics);
		refinement_cells = raw_cells;
	}
	diagnostics.path_cell_count = (int64_t)refinement_cells.size();
	result.search = diagnostics;
	if (raw_cells.empty()) {
		result.set_failure(LongPathResult::STATUS_NO_PATH, LongPathResult::FAILURE_NO_ROUTE);
		return result;
	}

	std::vector<Vector2> raw_path = _waypoint_path_from_cells(raw_cells, p_query.goal);
	std::vector<Vector2> refinement_path = raw_path;
	if (refinement_cells.size() != raw_cells.size()) {
		refinement_path = _waypoint_path_from_cells(refinement_cells, p_query.goal);
	}
	JumpTables *segment_tables = p_query.excluded_regions.empty() ? &tables_for(p_query.pass_mask) : nullptr;
	std::vector<Vector2> refined_path = _refine_waypoint_path(refinement_path, p_query, result.post_process, result.waypoint_spacing, segment_tables);
	result.canonical_navcell = raw_cells[raw_cells.size() - 1];
	int64_t cost = _path_cost_for_cells(raw_cells);
	result.set_paths(LongPathResult::STATUS_SUCCESS, std::move(raw_cells), std::move(raw_path), std::move(refined_path), cost);
	return result;
}

// ── JPS ──────────────────────────────────────────────────────────────────────

std::vector<Vector2i> LongPathfinder::_jps_cells(const Vector2i &p_start, const PathGoal &p_goal, int32_t p_pass_mask, SearchDiagnostics &p_diag) {
	JumpTables &tables = tables_for(p_pass_mask);
	const bool use_point_jump = p_goal.type == PathGoal::POINT;
	const Vector2i point_goal_cell = use_point_jump ? map->world_to_navcell(p_goal.center) : Vector2i();
	std::vector<HeapKey> open_keys;
	std::unordered_map<int64_t, int64_t> came_from;
	std::unordered_map<int64_t, int64_t> g_score;
	std::unordered_map<int64_t, char> closed;
	int64_t insertion_seq = 0;

	const int64_t start_pack = _pack_cell(p_start);
	g_score[start_pack] = 0;
	int64_t h0 = _heuristic(p_start, p_goal);
	open_keys.push_back({ h0, h0, p_start.x, p_start.y, insertion_seq });
	insertion_seq += 1;
	p_diag.push_count += 1;
	p_diag.max_open_count = std::max(p_diag.max_open_count, (int64_t)open_keys.size());

	Vector2i successor_buf[8];
	while (!open_keys.empty()) {
		HeapKey key = open_keys.front();
		open_keys.erase(open_keys.begin());
		Vector2i current((int)key[2], (int)key[3]);
		int64_t current_pack = _pack_cell(current);
		if (closed.count(current_pack)) {
			continue;
		}
		closed[current_pack] = 1;
		p_diag.expansion_count += 1;
		p_diag.closed_count = (int64_t)closed.size();
		if (p_goal.navcell_contains_goal(*map, current)) {
			return _reconstruct_cells(came_from, start_pack, current_pack);
		}

		int64_t current_g = g_score[current_pack];
		if (current_pack == start_pack) {
			// Twin: _add_start_successors — all 8 directions, plain steps.
			for (const Vector2i &direction : DIRECTIONS) {
				Vector2i next_cell = current + direction;
				if (!_can_step(current, next_cell, direction, p_pass_mask)) {
					continue;
				}
				int64_t next_pack = _pack_cell(next_cell);
				if (closed.count(next_pack)) {
					continue;
				}
				int64_t next_g = current_g + _movement_cost(current, next_cell);
				auto existing = g_score.find(next_pack);
				if (existing != g_score.end() && next_g >= existing->second) {
					continue;
				}
				g_score[next_pack] = next_g;
				came_from[next_pack] = current_pack;
				int64_t next_h = _heuristic(next_cell, p_goal);
				_heap_insert(open_keys, { next_g + next_h, next_h, next_cell.x, next_cell.y, insertion_seq });
				insertion_seq += 1;
				p_diag.push_count += 1;
				p_diag.max_open_count = std::max(p_diag.max_open_count, (int64_t)open_keys.size());
			}
			continue;
		}
		int successor_count = _successor_directions(current, current_pack, start_pack, came_from, p_pass_mask, successor_buf);
		for (int i = 0; i < successor_count; i++) {
			const Vector2i &direction = successor_buf[i];
			p_diag.jump_count += 1;
			Vector2i jump = use_point_jump ? tables.jump_point(current, direction, point_goal_cell)
										   : _jump(current, direction, p_goal, p_pass_mask, tables);
			if (jump == current) {
				continue;
			}
			int64_t jump_pack = _pack_cell(jump);
			if (closed.count(jump_pack)) {
				continue;
			}
			int64_t jump_g = current_g + _movement_cost(current, jump);
			auto existing = g_score.find(jump_pack);
			if (existing != g_score.end() && jump_g >= existing->second) {
				continue;
			}
			g_score[jump_pack] = jump_g;
			came_from[jump_pack] = current_pack;
			int64_t jump_h = _heuristic(jump, p_goal);
			_heap_insert(open_keys, { jump_g + jump_h, jump_h, jump.x, jump.y, insertion_seq });
			insertion_seq += 1;
			p_diag.push_count += 1;
			p_diag.max_open_count = std::max(p_diag.max_open_count, (int64_t)open_keys.size());
		}
	}
	return {};
}

static void _append_successor_direction(Vector2i *p_buf, int &p_count, const Vector2i &p_direction) {
	if (p_direction == Vector2i(0, 0)) {
		return;
	}
	for (int i = 0; i < p_count; i++) {
		if (p_buf[i] == p_direction) {
			return;
		}
	}
	p_buf[p_count++] = p_direction;
}

static int _sign_int(int p_value) {
	if (p_value < 0) {
		return -1;
	}
	if (p_value > 0) {
		return 1;
	}
	return 0;
}

int LongPathfinder::_successor_directions(const Vector2i &p_current, int64_t p_current_pack, int64_t p_start_pack, const std::unordered_map<int64_t, int64_t> &p_came_from, int32_t p_pass_mask, Vector2i *r_result) const {
	int count = 0;
	auto parent_found = p_came_from.find(p_current_pack);
	if (p_current_pack == p_start_pack || parent_found == p_came_from.end()) {
		for (const Vector2i &direction : DIRECTIONS) {
			_append_successor_direction(r_result, count, direction);
		}
		return count;
	}

	Vector2i parent = _cell_from_pack(parent_found->second);
	int dx = _sign_int(p_current.x - parent.x);
	int dy = _sign_int(p_current.y - parent.y);
	if (dx != 0 && dy != 0) {
		_append_successor_direction(r_result, count, Vector2i(dx, dy));
		_append_successor_direction(r_result, count, Vector2i(dx, 0));
		_append_successor_direction(r_result, count, Vector2i(0, dy));
		if (!_is_passable(Vector2i(p_current.x - dx, p_current.y), p_pass_mask) &&
				_is_passable(Vector2i(p_current.x - dx, p_current.y + dy), p_pass_mask)) {
			_append_successor_direction(r_result, count, Vector2i(-dx, dy));
		}
		if (!_is_passable(Vector2i(p_current.x, p_current.y - dy), p_pass_mask) &&
				_is_passable(Vector2i(p_current.x + dx, p_current.y - dy), p_pass_mask)) {
			_append_successor_direction(r_result, count, Vector2i(dx, -dy));
		}
	} else if (dx != 0) {
		_append_successor_direction(r_result, count, Vector2i(dx, 0));
		if (!_is_passable(Vector2i(p_current.x - dx, p_current.y - 1), p_pass_mask)) {
			_append_successor_direction(r_result, count, Vector2i(dx, -1));
			_append_successor_direction(r_result, count, Vector2i(0, -1));
		}
		if (!_is_passable(Vector2i(p_current.x - dx, p_current.y + 1), p_pass_mask)) {
			_append_successor_direction(r_result, count, Vector2i(dx, 1));
			_append_successor_direction(r_result, count, Vector2i(0, 1));
		}
	} else if (dy != 0) {
		_append_successor_direction(r_result, count, Vector2i(0, dy));
		if (!_is_passable(Vector2i(p_current.x - 1, p_current.y - dy), p_pass_mask)) {
			_append_successor_direction(r_result, count, Vector2i(-1, dy));
			_append_successor_direction(r_result, count, Vector2i(-1, 0));
		}
		if (!_is_passable(Vector2i(p_current.x + 1, p_current.y - dy), p_pass_mask)) {
			_append_successor_direction(r_result, count, Vector2i(1, dy));
			_append_successor_direction(r_result, count, Vector2i(1, 0));
		}
	}
	return count;
}

LongPathfinder::JumpHit LongPathfinder::_find_hit(const JumpTables &p_tables, const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal) const {
	// Twin of SimNavJumpPointCache.find() minus the memo dictionary (results
	// are identical; the memo only changed lookup cost).
	JumpHit none;
	if (p_tables.is_dirty()) {
		return none;
	}
	if (!map->is_valid_navcell(p_start) || !map->is_passable_navcell(p_start, p_tables.pass_mask_value())) {
		return none;
	}
	const std::vector<int32_t> *table = nullptr;
	if (p_direction.x == 1) {
		table = &p_tables.ray_table_east();
	} else if (p_direction.x == -1) {
		table = &p_tables.ray_table_west();
	} else if (p_direction.y == 1) {
		table = &p_tables.ray_table_south();
	} else {
		table = &p_tables.ray_table_north();
	}
	int32_t entry = (*table)[(size_t)p_start.y * p_tables.width() + p_start.x];
	int32_t kind_code = entry & 3;
	if (kind_code == JumpTables::RAY_IMPASSABLE) {
		return none;
	}
	int32_t steps = entry >> 2;
	JumpHit hit;
	hit.Kind_value = JumpHit::JUMP;
	if (kind_code == JumpTables::RAY_OBSTRUCTION) {
		hit.Kind_value = JumpHit::OBSTRUCTION;
	} else if (kind_code == JumpTables::RAY_BOUNDARY) {
		hit.Kind_value = JumpHit::BOUNDARY;
	}
	hit.cell = p_start + p_direction * steps;
	hit.steps = steps;

	// _find_goal_before_hit
	int32_t max_steps = hit.steps;
	if (hit.Kind_value == JumpHit::OBSTRUCTION) {
		max_steps -= 1;
	}
	if (p_goal.type == PathGoal::POINT) {
		Vector2i goal_cell = map->world_to_navcell(p_goal.center);
		Vector2i delta = goal_cell - p_start;
		int32_t step_count = delta.x * p_direction.x + delta.y * p_direction.y;
		if (step_count >= 1 && step_count <= max_steps && p_start + p_direction * step_count == goal_cell) {
			JumpHit goal_hit;
			goal_hit.Kind_value = JumpHit::GOAL;
			goal_hit.cell = goal_cell;
			goal_hit.steps = step_count;
			return goal_hit;
		}
		return hit;
	}
	for (int32_t step = 1; step <= max_steps; step++) {
		Vector2i cell = p_start + p_direction * step;
		if (p_goal.navcell_contains_goal(*map, cell)) {
			JumpHit goal_hit;
			goal_hit.Kind_value = JumpHit::GOAL;
			goal_hit.cell = cell;
			goal_hit.steps = step;
			return goal_hit;
		}
	}
	return hit;
}

Vector2i LongPathfinder::_jump(const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal, int32_t p_pass_mask, const JumpTables &p_tables) const {
	if (p_direction.x == 0 || p_direction.y == 0) {
		return _jump_cardinal(p_start, p_direction, p_goal, p_pass_mask, p_tables);
	}
	return _jump_diagonal(p_start, p_direction, p_goal, p_pass_mask, p_tables);
}

Vector2i LongPathfinder::_jump_cardinal(const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal, int32_t p_pass_mask, const JumpTables &p_tables) const {
	(void)p_pass_mask;
	JumpHit hit = _find_hit(p_tables, p_start, p_direction, p_goal);
	if (hit.Kind_value == JumpHit::GOAL || hit.Kind_value == JumpHit::JUMP) {
		return hit.cell;
	}
	return p_start;
}

Vector2i LongPathfinder::_jump_diagonal(const Vector2i &p_start, const Vector2i &p_direction, const PathGoal &p_goal, int32_t p_pass_mask, const JumpTables &p_tables) const {
	Vector2i current = p_start;
	while (true) {
		Vector2i next = current + p_direction;
		if (!_can_step(current, next, p_direction, p_pass_mask)) {
			return p_start;
		}
		if (p_goal.navcell_contains_goal(*map, next)) {
			return next;
		}
		Vector2i horizontal_jump = _jump_cardinal(next, Vector2i(p_direction.x, 0), p_goal, p_pass_mask, p_tables);
		Vector2i vertical_jump = _jump_cardinal(next, Vector2i(0, p_direction.y), p_goal, p_pass_mask, p_tables);
		if (horizontal_jump != next || vertical_jump != next) {
			return next;
		}
		current = next;
	}
}

// ── A* with excluded regions ─────────────────────────────────────────────────

std::vector<Vector2i> LongPathfinder::_astar_cells(const Vector2i &p_start, const PathGoal &p_goal, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded, SearchDiagnostics &p_diag) {
	std::vector<HeapKey> open_keys;
	std::unordered_map<int64_t, int64_t> came_from;
	std::unordered_map<int64_t, int64_t> g_score;
	std::unordered_map<int64_t, char> closed;
	int64_t insertion_seq = 0;

	const int64_t start_pack = _pack_cell(p_start);
	g_score[start_pack] = 0;
	int64_t h0 = _heuristic(p_start, p_goal);
	open_keys.push_back({ h0, h0, p_start.x, p_start.y, insertion_seq });
	insertion_seq += 1;
	p_diag.push_count += 1;
	p_diag.max_open_count = std::max(p_diag.max_open_count, (int64_t)open_keys.size());

	while (!open_keys.empty()) {
		HeapKey key = open_keys.front();
		open_keys.erase(open_keys.begin());
		Vector2i current((int)key[2], (int)key[3]);
		int64_t current_pack = _pack_cell(current);
		if (closed.count(current_pack)) {
			continue;
		}
		closed[current_pack] = 1;
		p_diag.expansion_count += 1;
		p_diag.closed_count = (int64_t)closed.size();
		if (p_goal.navcell_contains_goal(*map, current)) {
			return _reconstruct_cells(came_from, start_pack, current_pack);
		}

		int64_t current_g = g_score[current_pack];
		for (const Vector2i &direction : DIRECTIONS) {
			Vector2i next_cell = current + direction;
			if (!_can_step_with_exclusions(current, next_cell, direction, p_pass_mask, p_excluded)) {
				continue;
			}
			int64_t next_pack = _pack_cell(next_cell);
			if (closed.count(next_pack)) {
				continue;
			}
			int64_t next_g = current_g + _movement_cost(current, next_cell);
			auto existing = g_score.find(next_pack);
			if (existing != g_score.end() && next_g >= existing->second) {
				continue;
			}
			g_score[next_pack] = next_g;
			came_from[next_pack] = current_pack;
			int64_t next_h = _heuristic(next_cell, p_goal);
			_heap_insert(open_keys, { next_g + next_h, next_h, next_cell.x, next_cell.y, insertion_seq });
			insertion_seq += 1;
			p_diag.push_count += 1;
			p_diag.max_open_count = std::max(p_diag.max_open_count, (int64_t)open_keys.size());
		}
	}
	return {};
}

std::vector<Vector2i> LongPathfinder::_reconstruct_cells(const std::unordered_map<int64_t, int64_t> &p_came_from, int64_t p_start_pack, int64_t p_goal_pack) {
	std::vector<int64_t> reverse_cells = { p_goal_pack };
	int64_t current = p_goal_pack;
	while (current != p_start_pack) {
		auto found = p_came_from.find(current);
		if (found == p_came_from.end()) {
			return {};
		}
		current = found->second;
		reverse_cells.push_back(current);
	}
	std::vector<Vector2i> cells;
	cells.reserve(reverse_cells.size());
	for (int i = (int)reverse_cells.size() - 1; i >= 0; i--) {
		cells.push_back(_cell_from_pack(reverse_cells[(size_t)i]));
	}
	return cells;
}

// ── Path expansion / refinement ──────────────────────────────────────────────

std::vector<Vector2i> LongPathfinder::_expand_sparse_navcell_path(const std::vector<Vector2i> &p_cells) {
	if (p_cells.size() <= 1) {
		return p_cells;
	}
	std::vector<Vector2i> expanded = { p_cells[0] };
	std::vector<Vector2i> segment;
	for (size_t i = 1; i < p_cells.size(); i++) {
		_expand_navcell_segment(p_cells[i - 1], p_cells[i], segment);
		for (size_t j = 1; j < segment.size(); j++) {
			expanded.push_back(segment[j]);
		}
	}
	return expanded;
}

void LongPathfinder::_expand_navcell_segment(const Vector2i &p_from, const Vector2i &p_to, std::vector<Vector2i> &r_segment) {
	r_segment.clear();
	r_segment.push_back(p_from);
	Vector2i delta = p_to - p_from;
	int step_count = std::max(std::abs(delta.x), std::abs(delta.y));
	if (step_count <= 0) {
		return;
	}
	for (int step = 1; step <= step_count; step++) {
		double t = (double)step / (double)step_count;
		Vector2i cell(
				p_from.x + (int)std::round((double)delta.x * t),
				p_from.y + (int)std::round((double)delta.y * t));
		if (r_segment.back() != cell) {
			r_segment.push_back(cell);
		}
	}
	if (r_segment.back() != p_to) {
		r_segment.push_back(p_to);
	}
}

std::vector<Vector2> LongPathfinder::_waypoint_path_from_cells(const std::vector<Vector2i> &p_cells, const PathGoal &p_goal) const {
	std::vector<Vector2> path;
	for (int i = (int)p_cells.size() - 1; i > 0; i--) {
		Vector2 point = map->navcell_center_world(p_cells[(size_t)i]);
		if (i == (int)p_cells.size() - 1) {
			point = p_goal.nearest_point_on_goal(point);
		}
		path.push_back(point);
	}
	return path;
}

std::vector<Vector2> LongPathfinder::_refine_waypoint_path(const std::vector<Vector2> &p_raw_path, const LongPathQuery &p_query, const String &p_post_process, double p_spacing, JumpTables *p_segment_tables) {
	if (p_raw_path.empty()) {
		return {};
	}
	if (p_post_process == String(LongPathQuery::POST_PROCESS_RAW)) {
		return p_raw_path;
	}
	// _path_to_execution_points: reverse into consumption order.
	std::vector<Vector2> execution_points;
	execution_points.reserve(p_raw_path.size());
	for (int i = (int)p_raw_path.size() - 1; i >= 0; i--) {
		execution_points.push_back(p_raw_path[(size_t)i]);
	}
	execution_points = _compress_execution_points(p_query.start_world, execution_points, p_query.pass_mask, p_query.excluded_regions, p_segment_tables);
	if (p_spacing > 0.0) {
		execution_points = _apply_waypoint_spacing(p_query.start_world, execution_points, p_spacing);
	}
	// _execution_points_to_path: reverse back to reverse-consumption order.
	std::vector<Vector2> path;
	path.reserve(execution_points.size());
	for (int i = (int)execution_points.size() - 1; i >= 0; i--) {
		path.push_back(execution_points[(size_t)i]);
	}
	return path;
}

std::vector<Vector2> LongPathfinder::_compress_execution_points(const Vector2 &p_start_world, const std::vector<Vector2> &p_points, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded, JumpTables *p_segment_tables) const {
	if (p_points.empty()) {
		return {};
	}
	std::vector<Vector2> result;
	Vector2 anchor = p_start_world;
	int idx = 0;
	while (idx < (int)p_points.size()) {
		int chosen = idx;
		for (int j = (int)p_points.size() - 1; j >= idx; j--) {
			if (_segment_passable_clear(anchor, p_points[(size_t)j], p_pass_mask, p_excluded, p_segment_tables)) {
				chosen = j;
				break;
			}
		}
		result.push_back(p_points[(size_t)chosen]);
		anchor = p_points[(size_t)chosen];
		idx = chosen + 1;
	}
	return result;
}

std::vector<Vector2> LongPathfinder::_apply_waypoint_spacing(const Vector2 &p_start_world, const std::vector<Vector2> &p_points, double p_spacing) {
	if (p_spacing <= 0.0 || p_points.empty()) {
		return p_points;
	}
	std::vector<Vector2> result;
	Vector2 anchor = p_start_world;
	for (const Vector2 &point : p_points) {
		double distance = (double)anchor.distance_to(point);
		int steps = std::max(1, (int)std::ceil(distance / p_spacing));
		for (int step = 1; step <= steps; step++) {
			result.push_back(anchor.lerp(point, (real_t)((double)step / (double)steps)));
		}
		anchor = point;
	}
	return result;
}

bool LongPathfinder::_segment_passable_clear(const Vector2 &p_a, const Vector2 &p_b, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded, JumpTables *p_segment_tables) const {
	if (p_segment_tables != nullptr) {
		return p_segment_tables->segment_clear(p_a, p_b);
	}
	// Generic Amanatides-Woo walk with exclusions (twin of the GDScript body).
	constexpr double INF = std::numeric_limits<double>::infinity();
	double cell_size = map->navcell_size;
	Vector2 origin = map->origin;
	int i0 = (int)std::floor(((double)p_a.x - (double)origin.x) / cell_size);
	int j0 = (int)std::floor(((double)p_a.y - (double)origin.y) / cell_size);
	int i1 = (int)std::floor(((double)p_b.x - (double)origin.x) / cell_size);
	int j1 = (int)std::floor(((double)p_b.y - (double)origin.y) / cell_size);
	if (!_is_passable_with_exclusions(Vector2i(i0, j0), p_pass_mask, p_excluded)) {
		return false;
	}
	if (i0 == i1 && j0 == j1) {
		return true;
	}
	double dx = (double)p_b.x - (double)p_a.x;
	double dy = (double)p_b.y - (double)p_a.y;
	int step_i = 0;
	int step_j = 0;
	double t_max_x = INF;
	double t_max_y = INF;
	double delta_t_x = INF;
	double delta_t_y = INF;
	if (dx > 0.0) {
		step_i = 1;
		t_max_x = ((double)origin.x + (double)(i0 + 1) * cell_size - (double)p_a.x) / dx;
		delta_t_x = cell_size / dx;
	} else if (dx < 0.0) {
		step_i = -1;
		t_max_x = ((double)origin.x + (double)i0 * cell_size - (double)p_a.x) / dx;
		delta_t_x = -cell_size / dx;
	}
	if (dy > 0.0) {
		step_j = 1;
		t_max_y = ((double)origin.y + (double)(j0 + 1) * cell_size - (double)p_a.y) / dy;
		delta_t_y = cell_size / dy;
	} else if (dy < 0.0) {
		step_j = -1;
		t_max_y = ((double)origin.y + (double)j0 * cell_size - (double)p_a.y) / dy;
		delta_t_y = -cell_size / dy;
	}
	int i = i0;
	int j = j0;
	int max_steps = std::abs(i1 - i0) + std::abs(j1 - j0) + 4;
	while (i != i1 || j != j1) {
		if (max_steps <= 0) {
			return false;
		}
		max_steps -= 1;
		if (i == i1) {
			j += step_j;
			t_max_y += delta_t_y;
		} else if (j == j1) {
			i += step_i;
			t_max_x += delta_t_x;
		} else if (t_max_x < t_max_y) {
			i += step_i;
			t_max_x += delta_t_x;
		} else {
			j += step_j;
			t_max_y += delta_t_y;
		}
		if (!_is_passable_with_exclusions(Vector2i(i, j), p_pass_mask, p_excluded)) {
			return false;
		}
	}
	return true;
}

// ── Shared predicates / costs ────────────────────────────────────────────────

bool LongPathfinder::_is_passable(const Vector2i &p_cell, int32_t p_pass_mask) const {
	return map->is_passable_navcell(p_cell, p_pass_mask);
}

bool LongPathfinder::_is_passable_with_exclusions(const Vector2i &p_cell, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded) const {
	if (!map->is_passable_navcell(p_cell, p_pass_mask)) {
		return false;
	}
	if (_is_cell_excluded(p_cell, p_excluded)) {
		return false;
	}
	return true;
}

bool LongPathfinder::_is_cell_excluded(const Vector2i &p_cell, const std::vector<ExcludedRegion> &p_excluded) const {
	if (p_excluded.empty() || !map->is_valid_navcell(p_cell)) {
		return false;
	}
	Vector2 center = map->navcell_center_world(p_cell);
	for (const ExcludedRegion &region : p_excluded) {
		double radius = std::max(0.0, region.radius);
		if (radius <= 0.0) {
			continue;
		}
		if ((double)center.distance_to(region.center) <= radius) {
			return true;
		}
	}
	return false;
}

bool LongPathfinder::_can_step(const Vector2i &p_from, const Vector2i &p_to, const Vector2i &p_direction, int32_t p_pass_mask) const {
	if (!_is_passable(p_to, p_pass_mask)) {
		return false;
	}
	if (p_direction.x != 0 && p_direction.y != 0) {
		if (!_is_passable(Vector2i(p_from.x + p_direction.x, p_from.y), p_pass_mask)) {
			return false;
		}
		if (!_is_passable(Vector2i(p_from.x, p_from.y + p_direction.y), p_pass_mask)) {
			return false;
		}
	}
	return true;
}

bool LongPathfinder::_can_step_with_exclusions(const Vector2i &p_from, const Vector2i &p_to, const Vector2i &p_direction, int32_t p_pass_mask, const std::vector<ExcludedRegion> &p_excluded) const {
	if (!_is_passable_with_exclusions(p_to, p_pass_mask, p_excluded)) {
		return false;
	}
	if (p_direction.x != 0 && p_direction.y != 0) {
		if (!_is_passable_with_exclusions(Vector2i(p_from.x + p_direction.x, p_from.y), p_pass_mask, p_excluded)) {
			return false;
		}
		if (!_is_passable_with_exclusions(Vector2i(p_from.x, p_from.y + p_direction.y), p_pass_mask, p_excluded)) {
			return false;
		}
	}
	return true;
}

int64_t LongPathfinder::_heuristic(const Vector2i &p_cell, const PathGoal &p_goal) const {
	if (p_goal.type == PathGoal::POINT) {
		Vector2i goal_cell = map->world_to_navcell(p_goal.center);
		return _octile_cost(p_cell, goal_cell);
	}
	Vector2 center_world = map->navcell_center_world(p_cell);
	return (int64_t)std::round(p_goal.distance_to_point(center_world) / map->navcell_size * (double)COST_HV);
}

int64_t LongPathfinder::_octile_cost(const Vector2i &p_a, const Vector2i &p_b) {
	int64_t dx = std::abs(p_a.x - p_b.x);
	int64_t dy = std::abs(p_a.y - p_b.y);
	int64_t diagonal = std::min(dx, dy);
	int64_t straight = std::max(dx, dy) - diagonal;
	return diagonal * COST_DIAG + straight * COST_HV;
}

int64_t LongPathfinder::_movement_cost(const Vector2i &p_from, const Vector2i &p_to) {
	return _octile_cost(p_from, p_to);
}

int64_t LongPathfinder::_path_cost_for_cells(const std::vector<Vector2i> &p_cells) {
	int64_t total = 0;
	for (size_t i = 1; i < p_cells.size(); i++) {
		total += _movement_cost(p_cells[i - 1], p_cells[i]);
	}
	return total;
}

String LongPathfinder::_normalized_post_process(const String &p_post_process) {
	if (p_post_process == String(LongPathQuery::POST_PROCESS_RAW) ||
			p_post_process == String(LongPathQuery::POST_PROCESS_LINE_OF_SIGHT) ||
			p_post_process == String(LongPathQuery::POST_PROCESS_MAX_SPACING)) {
		return p_post_process;
	}
	return LongPathQuery::POST_PROCESS_RAW;
}

double LongPathfinder::_effective_waypoint_spacing(const LongPathQuery &p_query) {
	if (p_query.post_process == String(LongPathQuery::POST_PROCESS_RAW)) {
		return 0.0;
	}
	if (p_query.waypoint_spacing > 0.0) {
		return p_query.waypoint_spacing;
	}
	if (p_query.has_goal && p_query.goal.maxdist > 0.0) {
		return p_query.goal.maxdist;
	}
	return 0.0;
}

} // namespace simnav
